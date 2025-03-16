variable "region" {
  description = "The region in which the resources will be created"
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "The availability zone in which the resources will be created"
  default     = "us-east-1a"
}

variable "AMI" {
  description = "The AMI to use for the EC2 instance"
  default     = "ami-04b4f1a9cf54c11d0"
}

variable "instance_type" {
  description = "The type of EC2 instance to create"
  default     = "t2.medium"
}

variable "codegenitor_keypair" {
  description = "The name of the key pair to use for the EC2 instance"
  default     = "codegenitor_keypair"
}

variable "VPC_ID" {
  description = "The VPC ID to use for the instance"
  default     = "vpc-0c4be51003fc3c274"
}

variable "volume_size" {
  description = "The size of the EBS volume to attach to the instance"
  default     = 50

}