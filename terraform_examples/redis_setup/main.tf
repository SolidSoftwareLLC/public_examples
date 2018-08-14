provider "aws" {
  region     = "us-west-2"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_s3_bucket" "backups" {
  bucket = "${var.backup_s3_bucket_name}"
  acl    = "private"
}

module "ec2_redis_sg" {
  source = "terraform-aws-modules/security-group/aws"
  name = "ec2_redis_sg"
  vpc_id = "${data.aws_vpc.default.id}"

  ingress_with_cidr_blocks = [
    {
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      description = "Intra-VPC Redis"
      cidr_blocks = "172.31.0.0/16"
    },
    {
      rule  = "ssh-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  egress_rules = [ "all-all" ]
}

data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "role" {
  name = "ec2_redis_role"
  assume_role_policy = "${data.aws_iam_policy_document.instance-assume-role-policy.json}"
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "ec2_redis_instance_profile"
  role = "${aws_iam_role.role.name}"
}

resource "aws_iam_policy" "policy" {
  name = "ec2_redis_policy"
  description = "For writing to backup bucket"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.backups.id}",
                "arn:aws:s3:::${aws_s3_bucket.backups.id}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attachment" {
  role       = "${aws_iam_role.role.name}"
  policy_arn = "${aws_iam_policy.policy.arn}"
}

resource "aws_instance" "ec2_redis" {
  instance_type = "${var.instance_type}"
  vpc_security_group_ids = ["${module.ec2_redis_sg.this_security_group_id}"]
  ami = "${var.instance_ami}"
  key_name = "${var.instance_key}"
  iam_instance_profile = "${aws_iam_instance_profile.instance_profile.name}"
}
