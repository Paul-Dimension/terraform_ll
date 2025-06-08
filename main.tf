# Получение актуального AMI от Bitnami с Tomcat
data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

# VPC модуль
module "blog_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs            = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Security Group модуль
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name        = "blog-sg"
  description = "Allow HTTP/HTTPS in, all traffic out"
  vpc_id      = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

# EC2 instance (Tomcat)
resource "aws_instance" "blog" {
  ami                    = data.aws_ami.app_ami.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [module.blog_sg.security_group_id]
  subnet_id              = module.blog_vpc.public_subnets[0]
  associate_public_ip_address = true

  tags = {
    Name = "HelloWorld"
  }
}

# ALB (Application Load Balancer)
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.9.0"

  name    = "blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.blog_sg.security_group_id]

  load_balancer_type = "application"
  internal           = false

  target_groups = {
    ex-instance = {
      name_prefix   = "blog"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      targets = [{
        target_id = aws_instance.blog.id
        port      = 80
      }]
    }
  }

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      default_action = {
        type             = "forward"
        target_group_key = "ex-instance"
      }
    }
  }

  tags = {
    Name = "blog-alb"
  }
}