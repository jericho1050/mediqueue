variable "instance_name" {
  description = "Value of the tag for the EC2 instance"
  type        = string
  default     = "mediqueue-instance"
} 

variable "ec2_instance_type" {
  description = "Value of the tag for the EC2 instance type"
  type        = string
  default     = "m5.large"
}


variable "cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_1_cidr_block" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_2_cidr_block" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_subnet_cidr_block" {
  type    = string
  default = "10.0.3.0/24" # Fixed: was overlapping with public_subnet_2
}

variable "availability_zone_1" {
  type    = string
  default = "us-east-1a"
}

variable "availability_zone_2" {
  type    = string
  default = "us-east-1b"
}

variable "allowed_ip" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR block allowed to access resources"
}

variable "image_repository_api" {
  type    = string
  default = "mediqueue/api"
}

variable "image_repository_worker" {
  type    = string
  default = "mediqueue/worker"
}

variable "image_repository_frontend" {
  type    = string
  default = "mediqueue/frontend"
}

variable "image_tag_api" {
  type    = string
  default = "latest"
}

variable "image_tag_worker" {
  type    = string
  default = "latest"
}

variable "image_tag_frontend" {
  type    = string
  default = "latest"
}

