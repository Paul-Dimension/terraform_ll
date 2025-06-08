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

# Получение VPC по умолчанию
data "aws_vpc" "default" {
  default = true
}

# Подключение готового модуля security group с доступом по 80/443 и всем выходящим трафиком
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name    = "blog_sg"
  vpc_id  = data.aws_vpc.default.id

  # Разрешаем входящий HTTP и HTTPS трафик от всех
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  # Разрешаем весь исходящий трафик
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

# EC2 инстанс с использованием модуля SG
resource "aws_instance" "blog" {
  ami                    = data.aws_ami.app_ami.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [module.blog_sg.security_group_id]

  tags = {
    Name = "HelloWorld"
  }
}

# Тип инстанса как переменная
variable "instance_type" {
  description = "Type of EC2 instance to provision"
  default     = "t3.nano"
}
