
variable "region" {}
variable "key" {}
variable "secret" {}
variable "ssh_key_name" {}
variable "ssh_key_value" {}
variable "disk_scale" {}

variable "ip_range" {
  type    = string
  default = "69.120.106.187/32"
}

variable "project_tags" {
  type        = map(string)
  description = "Tags used for aws workload"
  default = {
    project = "aws-tpcc-workload"
  }
}

variable "vm_user" {
  type        = string
  default     = "debian"
  description = "Sudo user who we'll create upon initialization"
}

variable "anywhere_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "all IPs. Used for internet access"
}

variable "instance_defaults" {
  description = "Default settings to be used for our aws instances so we don't need to provide them for each machine separately."
  type        = object({
    ami_id                = string
    instance_architecture = string
    instance_type         = string
    instance_memory       = number
    instance_tags         = map(string)
  })
  default     = {
    ami_id                = "ami-06db4d78cb1d3bbf9"
    instance_architecture = "amd64"
    instance_type         = "t2.micro"
    instance_memory       = 32
    instance_tags         = {
      Name = "dev"
    }
  }
}
