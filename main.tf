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

data "aws_vpc" "default" {
  default = true
}


resource "aws_instance" "blog" {
  ami           = data.aws_ami.app_ami.id
  instance_type = var.instance_type

  subnet_id = module.blog_vpc.public_subnets[0]
  vpc_security_group_ids = [module.blog_sg.security_group_id]

  tags = {
    Name = "Learning Terraform"
  }
}


module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}


module "alb" {
  source = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"

  # Truncated for brevity ...
  name = "blog-alb"
  load_balancer_type = "application"

  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]

  target_groups = [
    {
      name_prefix = "blog-"
      backend_protocol = "HTTP"
      backend_port = 80
      target_type = "instance"
      targets = {
        my_target = {
          target_id = aws_instance.blog.id
          port = 80
        }
      }
    }
  ]

  http_tcp_listeners = [
    {
      port = 80
      protocol = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"
  name = "sg_new"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules = ["http-80-tcp","https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "7.3.0"
  name    = "blog"

  min_size                  = 1
  max_size                  = 2

  vpc_zone_identifier       = module.blog_vpc.public_subnets
  target_group_arns         = module.alb.target_group_arns
  security_groups           = [module.blog_sg.security_group_id] 

  ami           = data.aws_ami.app_ami.id
  instance_type = var.instance_type

}