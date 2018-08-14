# Setup a Redis instance on EC2 with periodic backups to S3

## To run

* Install Terraform
* Run `terraform init`
* Review and edit `variables.tf` and `main.tf` as you'd like (e.g. change the region, instance type, AMI, etc)
* Run `terraform apply`
  * Answer the prompt questions if you didn't fill in all the variable values
* Once it finishes, you should have a new EC2 instance with permission to write to a new S3 bucket 
* Configure the instance for redis, check out: https://github.com/SolidSoftwareLLC/public_examples/tree/master/scripts/redis_setup
