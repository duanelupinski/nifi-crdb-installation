### Required ###

variable "security_group_id" {
  type        = string
  description = "The security group the cluster will belong to"
}

variable "public_key_name" {
  type = string
  description = "Public key name for our cluster"
}

variable "instance_tags" {
  type        = map(any)
  description = "Any tags you'd like to associate with the cluster"
}

variable "ami_id" {
  type        = string
  description = "AMI ID used by the EC2 instance"
}

variable "project_tags" {
  type        = map(any)
  description = "Any tags you want to associate with this module"
}

variable "disk_size" {}
variable "disk_iops" {}

### Optional ###

variable "cloud_init_vars" {
  type        = map(any)
  description = "variables used by cloud_init script"
  default     = {}
}

variable "cloud_init_node" {
  type        = string
  description = "filepath to node cloud-init script"
}

variable "cloud_init_proxy" {
  type        = string
  description = "filepath to proxy cloud-init script"
}

variable "cloud_init_workload" {
  type        = string
  description = "filepath to workload cloud-init script"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 instance type"
}

variable "instance_architecture" {
  type        = string
  default     = "amd64"
  description = "EC2 instance architecture"
}

variable "proxy_defaults" {
  description = "Default settings to be used for our aws instances that will be used to proxy requests."
  type        = object({
    ami_id                = string
    instance_type         = string
  })
  default     = {
    ami_id                = "ami-06db4d78cb1d3bbf9"
    instance_type         = "c6a.xlarge"
  }
}

variable "workload_defaults" {
  description = "Default settings to be used for our aws instances that will execute the workload."
  type        = object({
    ami_id                = string
    instance_type         = string
  })
  default     = {
    ami_id                = "ami-06db4d78cb1d3bbf9"
    instance_type         = "c6a.xlarge"
  }
}
