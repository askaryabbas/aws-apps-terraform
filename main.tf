terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# Lookup the Default VPC
data "aws_vpc" "abbas_vpc" {
  default = true
}

# Get All Subnets in Default VPC
data "aws_subnets" "abbas_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.abbas_vpc.id]
  }
}

# Security Group for the EC2 Instances
resource "aws_security_group" "abbas_web_sg" {
  name   = "abbas-web-sg"
  vpc_id = data.aws_vpc.abbas_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

# Launch Template for EC2 Instances
resource "aws_launch_template" "abbas_web_template" {
  name_prefix   = "abbas-web-launch-template"
  image_id      = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.abbas_web_sg.id]
  }

  user_data = base64encode(<<-EOF
            #!/bin/bash
            echo "Hello, Abbas World" > /var/www/html/index.html
            nohup busybox httpd -f -p 80 &
            EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "abbas-web-server-instance" }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "abbas_web_asg" {
  desired_capacity    = 2
  max_size            = 10
  min_size            = 2
  vpc_zone_identifier = data.aws_subnets.abbas_subnets.ids

  launch_template {
    id      = aws_launch_template.abbas_web_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "abbas-terraform-web-asg"
    propagate_at_launch = true
  }
}

# Load Balancer
resource "aws_lb" "abbas_web_alb" {
  name               = "abbas-web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.abbas_web_sg.id]
  subnets            = data.aws_subnets.abbas_subnets.ids

  tags = { Name = "abbas-WebALB" }
}

# Target Group
resource "aws_lb_target_group" "abbas_web_tg" {
  name     = "abbas-web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.abbas_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ALB Listener
resource "aws_lb_listener" "abbas_web_listener" {
  load_balancer_arn = aws_lb.abbas_web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.abbas_web_tg.arn
  }
}

# Attach ASG to Target Group
resource "aws_autoscaling_attachment" "abbas_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.abbas_web_asg.id
  lb_target_group_arn    = aws_lb_target_group.abbas_web_tg.arn
}

# Output Load Balancer DNS Name
output "abbas_load_balancer_dns" {
  value       = aws_lb.abbas_web_alb.dns_name
  description = "Load Balancer URL for Abbas Web Cluster"
}