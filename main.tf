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

# ALB (Application Load Balancer)
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name    = "blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups    = [module.blog_sg.security_group_id]
  load_balancer_type = "application"
  internal           = false

  # HTTP listener
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  # Target group
  target_groups = [
    {
      name_prefix      = "blog-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]

  tags = {
    Name = "blog-alb"
  }
}

# Auto Scaling Group
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "8.3.0"

  name     = "blog"
  min_size = 1
  max_size = 2

  vpc_zone_identifier = module.blog_vpc.public_subnets
  security_groups     = [module.blog_sg.security_group_id]

  # Launch template configuration
  launch_template_name        = "blog-launch-template"
  launch_template_description = "Launch template for blog application"
  update_default_version      = true

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Явное присоединение Target Group к Auto Scaling Group
resource "aws_autoscaling_attachment" "blog_asg_attachment" {
  autoscaling_group_name = module.autoscaling.autoscaling_group_name
  lb_target_group_arn   = module.blog_alb.target_group_arns[0]
}