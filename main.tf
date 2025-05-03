provider "aws" {
  region = var.aws_region
  default_tags {
    tags = merge({
      terraform   = "true"
      owner       = var.owner
      environment = var.environment
      stack       = var.stack
      team        = var.team
    }, var.additional_tags)
  }
}

data "aws_ami" "this" {
  owners      = ["131827586825"]
  most_recent = true

  filter {
    name   = "name"
    values = ["OL9.*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_route53_zone" "this" {
  id = var.zone_id
}

locals {
  name = "${var.deployment_name}-${var.environment}-${var.stack}"
}

####################################################################################################
# VPN instance
####################################################################################################
resource "aws_instance" "this" {
  ami                         = data.aws_ami.this.id
  instance_type               = var.instance_type
  vpc_security_group_ids      = ["${aws_security_group.this.id}"]
  associate_public_ip_address = true
  subnet_id                   = var.subnet_id
  iam_instance_profile        = module.iam.instance_profile_name
  user_data_replace_on_change = true
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }
  user_data = <<USERDATA
    sudo tee /etc/yum.repos.d/mongodb-org.repo << EOF
    [mongodb-org]
    name=MongoDB Repository
    baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/
    gpgcheck=1
    enabled=1
    gpgkey=https://pgp.mongodb.com/server-8.0.asc
    EOF

    sudo tee /etc/yum.repos.d/pritunl.repo << EOF
    [pritunl]
    name=Pritunl Repository
    baseurl=https://repo.pritunl.com/stable/yum/oraclelinux/9/
    gpgcheck=1
    enabled=1
    gpgkey=https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc
    EOF

    sudo dnf -y update

    sudo dnf -y remove iptables-services
    sudo systemctl stop firewalld.service
    sudo systemctl disable firewalld.service

    sudo dnf -y install pritunl pritunl-openvpn wireguard-tools mongodb-org
    sudo systemctl enable mongod pritunl
    sudo systemctl start mongod pritunl
  USERDATA

  tags = {
    Name = local.name
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
####################################################################################################
# Network
####################################################################################################
resource "aws_security_group" "this" {
  name        = local.name
  description = "Allow VPN access to the ${local.name} instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id
}

resource "aws_route53_record" "vpn" {
  zone_id = var.zone_id
  name    = "vpn.${data.aws_route53_zone.this.name}"
  type    = "A"
  ttl     = "300"
  records = [aws_eip.this.public_ip]
}

####################################################################################################
# IAM
####################################################################################################
module "iam" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "5.55.0"

  create_role             = true
  role_name               = local.name
  role_requires_mfa       = false
  create_instance_profile = true
  trusted_role_arns       = []
  trusted_role_services   = ["ec2.amazonaws.com"]
  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
}
