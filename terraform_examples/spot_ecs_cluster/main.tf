provider "aws" {
  region     = "us-west-2"
}

# Define some variables we'll use later.
locals {
  instance_type = "m4.large"
  spot_price = "0.10"
  key_name = "solid"
  ecs_cluster_name = "default"
  max_spot_instances = 10
  min_spot_instances = 3

  max_ondemand_instances = 3
  min_ondemand_instances = 3
}

# Set the default vpc
data "aws_vpc" "default" {
  default = true
}

# Read all subnet ids for this vpc/region.
data "aws_subnet_ids" "all_subnets" {
  vpc_id = "${data.aws_vpc.default.id}"
}

# Lookup the current ECS AMI.
# In a production environment you probably want to 
# hardcode the AMI ID, to prevent upgrading to a 
# new and potentially broken release.
data "aws_ami" "ecs" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["591542846629"] # Amazon
}

# Create a Security Group with SSH access from the world
resource "aws_security_group" "ecs_cluster" {
  name        = "${local.ecs_cluster_name}_ecs_cluster"
  description = "An ecs cluster"
  vpc_id      = "${data.aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }
}

# Create an IAM role for the ECS instances.
resource "aws_iam_role" "ecs_instance" {
  name  = "ecs_instance"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create and attach an IAM role policy which alllows the necessary
# permissions for the ECS agent to function. 
data "aws_iam_policy_document" "ecs_instance_role_policy_doc" {
  statement {
    actions = [
      "ecs:CreateCluster",
      "ecs:DeregisterContainerInstance",
      "ecs:DiscoverPollEndpoint",
      "ecs:Poll",
      "ecs:RegisterContainerInstance",
      "ecs:StartTelemetrySession",
      "ecs:Submit*",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents" 
    ]
    resources = [
      "*",
    ]
  }
}

resource "aws_iam_policy" "ecs_role_permissions" {
  name        = "ecs_role_permissions"
  description = "ECS instance permissions"
  path   = "/"
  policy      = "${data.aws_iam_policy_document.ecs_instance_role_policy_doc.json}"
}


resource "aws_iam_policy_attachment" "ecs_instance_role_policy_attachment" {
  name       = "ecs_instance_role_policy_attachment"
  roles      = ["${aws_iam_role.ecs_instance.name}"]
  policy_arn = "${aws_iam_policy.ecs_role_permissions.arn}"
}

resource "aws_iam_instance_profile" "ecs_iam_profile" {
  name = "ecs_role_instance_profile"
  role = "${aws_iam_role.ecs_instance.name}"
}

# Create two launch configs one for ondemand instances and the other for spot.
resource "aws_launch_configuration" "ecs_config_launch_config_spot" {
  name_prefix   = "${local.ecs_cluster_name}_ecs_cluster_spot"
  image_id      = "${data.aws_ami.ecs.id}"
  instance_type = "${local.instance_type}"
  spot_price    = "${local.spot_price}"
  enable_monitoring = true
  lifecycle {
    create_before_destroy = true
  }
  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${local.ecs_cluster_name} >> /etc/ecs/ecs.config
echo ECS_INSTANCE_ATTRIBUTES={\"purchase-option\":\"spot\"} >> /etc/ecs/ecs.config
EOF
  security_groups = ["${aws_security_group.ecs_cluster.id}"]
  key_name = "${local.key_name}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs_iam_profile.arn}"
}

resource "aws_launch_configuration" "ecs_config_launch_config_ondemand" {
  name_prefix   = "${local.ecs_cluster_name}_ecs_cluster_ondemand"
  image_id      = "${data.aws_ami.ecs.id}"
  instance_type = "${local.instance_type}"
  enable_monitoring = true
  lifecycle {
    create_before_destroy = true
  }
  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${local.ecs_cluster_name} >> /etc/ecs/ecs.config
echo ECS_INSTANCE_ATTRIBUTES={\"purchase-option\":\"ondemand\"} >> /etc/ecs/ecs.config
EOF
  security_groups = ["${aws_security_group.ecs_cluster.id}"]
  key_name = "${local.key_name}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs_iam_profile.arn}"
}

# Create two autoscaling groups one for spot and the other for spot.
resource "aws_autoscaling_group" "ecs_cluster_ondemand" {
  name_prefix               = "${aws_launch_configuration.ecs_config_launch_config_ondemand.name}_ecs_cluster_ondemand"
  termination_policies = ["OldestInstance"]
  max_size                  = "${local.max_ondemand_instances}"
  min_size                  = "${local.min_ondemand_instances}"
  launch_configuration      = "${aws_launch_configuration.ecs_config_launch_config_ondemand.name}"
  timeouts {
    delete = "15m"
  }
  lifecycle {
    create_before_destroy = true
  }
  vpc_zone_identifier       = ["${data.aws_subnet_ids.all_subnets.ids}"]
}

resource "aws_autoscaling_group" "ecs_cluster_spot" {
  name_prefix               = "${aws_launch_configuration.ecs_config_launch_config_spot.name}_ecs_cluster_spot"
  termination_policies = ["OldestInstance"]
  max_size                  = "${local.max_spot_instances}"
  min_size                  = "${local.min_spot_instances}"
  launch_configuration      = "${aws_launch_configuration.ecs_config_launch_config_spot.name}"
  timeouts {
    delete = "15m"
  }
  lifecycle {
    create_before_destroy = true
  }
  vpc_zone_identifier       = ["${data.aws_subnet_ids.all_subnets.ids}"]
}

# Attach an autoscaling policy to the spot cluster to target 70% MemoryReservation on the ECS cluster.
resource "aws_autoscaling_policy" "ecs_cluster_scale_policy" {
  name                   = "${local.ecs_cluster_name}_ecs_cluster_spot_scale_policy"
  policy_type            = "TargetTrackingScaling"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = "${aws_autoscaling_group.ecs_cluster_spot.name}"

  target_tracking_configuration {
  customized_metric_specification {
    metric_dimension {
      name = "ClusterName"
      value = "${local.ecs_cluster_name}"
    }
    metric_name = "MemoryReservation"
    namespace = "AWS/ECS"
    statistic = "Average"
  }
  target_value = 70.0
  }
}


resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${local.ecs_cluster_name}"
}
