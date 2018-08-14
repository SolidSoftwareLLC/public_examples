######### Inputs ##########

variable "backup_s3_bucket_name" {
  description = "Name of S3 bucket for backups"
}

variable "instance_key" {
  description = "Name of SSH key to connect to server"
}

variable "instance_type" {
  description = "The instance type like t2.micro"  
  default = "t2.micro"
}

variable "instance_ami" {
  description = "The AMI for the instance"
  # Ubuntu Server 16.04 LTS (HVM), SSD Volume Type - Ubuntu 16.04 in us-west-2
  # TODO make this a map that then is keyed on aws_region
  default = "ami-ba602bc2"
}

######### End Inputs ##########
