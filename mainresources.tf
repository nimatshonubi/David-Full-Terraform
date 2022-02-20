resource "aws_vpc" "vpc" {
  cidr_block           = var.vpccidr
  enable_dns_hostnames = true
  tags                 = { Name = "vpc" }
}

# internet gateway
resource "aws_internet_gateway" "igwe" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "igwe" }
}

# publicsubnets
resource "aws_subnet" "pubsub1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.pubsub1cidr
  availability_zone       = var.az1
  map_public_ip_on_launch = true
  tags                    = { Name = "pubsub1" }
}


resource "aws_subnet" "pubsub2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.pubsub2cidr
  availability_zone       = var.az2
  map_public_ip_on_launch = true
  tags                    = { Name = "pubsub2" }
}


# private subnets
resource "aws_subnet" "prisub1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.prisub1cidr
  availability_zone       = var.az1
  map_public_ip_on_launch = false
  tags                    = { Name = "prisub1" }
}


resource "aws_subnet" "prisub2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.prisub2cidr
  availability_zone       = var.az2
  map_public_ip_on_launch = false
  tags                    = { Name = "prisub2" }
}

#public routetable
resource "aws_route_table" "publicrt" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "publicrt" }
}

# public route

resource "aws_route" "publicrou" {
  route_table_id         = aws_route_table.publicrt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igwe.id
}


#public routetable asso
resource "aws_route_table_association" "u" {
  subnet_id      = aws_subnet.pubsub1.id
  route_table_id = aws_route_table.publicrt.id
}


resource "aws_route_table_association" "v" {
  subnet_id      = aws_subnet.pubsub2.id
  route_table_id = aws_route_table.publicrt.id
}


#private table
resource "aws_route_table" "prirt" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "prirt" }
}


#private route

resource "aws_route" "prirou" {
  route_table_id         = aws_route_table.prirt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.natgwe.id
}

#elasticIP
resource "aws_eip" "myeip" {
  vpc = true
}


#nat gatway
resource "aws_nat_gateway" "natgwe" {
  allocation_id = aws_eip.myeip.id
  subnet_id     = aws_subnet.pubsub1.id
  tags          = { Name = "natgwe" }
  depends_on    = [aws_internet_gateway.igwe]
}

# iam_ssm role
resource "aws_iam_role" "EC2_SSMrole" {
  name = "EC2_SSMrole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  tags = { Name = "EC2_SSMrole" }
}


#iam_ssm policy
resource "aws_iam_role_policy" "ec2_ssm_policy" {
  name = "ec2_ssm_policy"
  role = aws_iam_role.EC2_SSMrole.id
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "Stmt1637866715430",
          "Action" : [
            "ssm:AddTagsToResource",
            "ssm:CreateDocument",
            "ssm:CreateMaintenanceWindow",
            "ssm:CreatePatchBaseline",
            "ssm:DeleteDocument",
            "ssm:DeleteMaintenanceWindow",
            "ssm:DeletePatchBaseline",
            "ssm:GetAutomationExecution",
            "ssm:GetCommandInvocation",
            "ssm:GetDocument",
            "ssm:GetInventory",
            "ssm:GetMaintenanceWindow",
            "ssm:ListTagsForResource",
            "ssm:RemoveTagsFromResource",
            "ssm:ResumeSession",
            "ssm:SendAutomationSignal",
            "ssm:SendCommand",
            "ssm:StartAutomationExecution",
            "ssm:StartSession",
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel",
            "ssm:UpdateInstanceInformation",
            "ssm:TerminateSession"
          ],
          "Effect" : "Allow",
          "Resource" : "*"
        },
        {
          "Sid" : "Stmt1637878136438",
          "Action" : "ssm:*",
          "Effect" : "Allow",
          "Resource" : "*"
        }

      ]
  })
}



resource "aws_security_group" "sg1" {
  name        = "sg1"
  depends_on  = [aws_vpc.vpc]
  description = "Allow SSH/ HTTP access"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
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


#iam instance profile
resource "aws_iam_instance_profile" "ec2ssminstanceprofile" {
  name = "ec2ssminstanceprofile"
  role = aws_iam_role.EC2_SSMrole.name
}


# launch configuration
resource "aws_launch_configuration" "ssmlconfig" {
  name                 = "ssmlconfig"
  image_id             = var.imaged
  instance_type        = var.instancetype
  security_groups      = [aws_security_group.sg1.id]
  iam_instance_profile = aws_iam_instance_profile.ec2ssminstanceprofile.name
}


resource "aws_autoscaling_group" "vpcasg" {
  name                      = "vpcasg"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 4
  force_delete              = true
  launch_configuration      = aws_launch_configuration.ssmlconfig.name
  vpc_zone_identifier       = [aws_subnet.pubsub1.id, aws_subnet.pubsub2.id, aws_subnet.prisub1.id, aws_subnet.prisub2.id]
  tag {
    key                 = "Name"
    value               = "vpcasg"
    propagate_at_launch = false
  }
}


resource "aws_security_group" "albsg2" {
  name        = "albsg2"
  depends_on  = [aws_vpc.vpc]
  description = "enable HTTP access on port 80"
  vpc_id      = aws_vpc.vpc.id
  ingress {
    description = "enable access to HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "albsg2" }
}



resource "aws_alb_target_group" "vpctargetgroup" {
  name                 = "vpctargetgroup"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = aws_vpc.vpc.id
  protocol_version     = "HTTP1"
  deregistration_delay = 300
  health_check {
    path                = "/"
    timeout             = 10
    unhealthy_threshold = 2
    matcher             = "200,202"
    port                = "traffic-port"
  }
}



resource "aws_lb" "albal" {
  name                             = "albal"
  internal                         = false
  load_balancer_type               = "application"
  security_groups                  = [aws_security_group.sg1.id, aws_security_group.albsg2.id]
  idle_timeout                     = 60
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = false
  subnet_mapping {
    subnet_id = aws_subnet.pubsub1.id
  }
  subnet_mapping {
    subnet_id = aws_subnet.pubsub2.id
  }
  tags = { Environment = "prod" }
}



resource "aws_autoscaling_policy" "asgpolicyout" {
  name                   = "asgpolicyout"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 100
  policy_type            = "SimpleScaling"
  autoscaling_group_name = aws_autoscaling_group.vpcasg.name
}


resource "aws_autoscaling_policy" "asgpolicyin" {
  name                   = "asgpolicyin"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 100
  policy_type            = "SimpleScaling"
  autoscaling_group_name = aws_autoscaling_group.vpcasg.name
}



resource "aws_cloudwatch_metric_alarm" "alarmout" {
  alarm_name          = "alarmout"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.vpcasg.name
  }
  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.asgpolicyout.arn]
}



resource "aws_cloudwatch_metric_alarm" "alarmin" {
  alarm_name          = "alarmin"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "35"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.vpcasg.name
  }
  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.asgpolicyin.arn]
}



resource "aws_autoscaling_lifecycle_hook" "lifecycle_hookout" {
  name                   = "lifecycle_hookout"
  autoscaling_group_name = aws_autoscaling_group.vpcasg.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 2000
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
}



resource "aws_autoscaling_lifecycle_hook" "lifecycle_hookin" {
  name                   = "lifecycle_hookin"
  autoscaling_group_name = aws_autoscaling_group.vpcasg.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 2000
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}



resource "aws_vpc_endpoint" "interface_ssm" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.prisub1.id, aws_subnet.prisub2.id]
  policy = jsonencode(
    {
      "Statement" : [
        {
          "Action" : "*",
          "Effect" : "Allow",
          "Resource" : "*",
          "Principal" : "*"
        }
      ]
  })
  tags                = { Name = "interface_ssm" }
  security_group_ids  = [aws_security_group.sg1.id]
  private_dns_enabled = true
}



resource "aws_vpc_endpoint" "interface_ssmmessages" {
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.us-east-1.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prisub1.id, aws_subnet.prisub2.id]
  tags                = { Name = "interface_ssmmessages" }
  security_group_ids  = [aws_security_group.sg1.id]
  private_dns_enabled = true
}



resource "aws_vpc_endpoint" "interface_ec2" {
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.us-east-1.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prisub1.id, aws_subnet.prisub2.id]
  tags                = { Name = "interface_ec2" }
  security_group_ids  = [aws_security_group.sg1.id]
  private_dns_enabled = true
}



resource "aws_vpc_endpoint" "interface_ec2messages" {
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.us-east-1.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.prisub1.id, aws_subnet.prisub2.id]
  tags                = { Name = "interface_ec2messages" }
  security_group_ids  = [aws_security_group.sg1.id]
  private_dns_enabled = true
}






