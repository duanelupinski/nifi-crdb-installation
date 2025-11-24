
variable "region" {
  type         = string
  description  = "Region for this infrastructure"
  default      = "us-east4"
}

variable "project" {
  type         = string
  description  = "Project ID"
  default      = "amd-dev-413115"
}

variable "name" {
  type         = string
  description  = "Name for this infrastructure"
  default      = "amd-tpcc-crdb"
}

variable env { default = "dev" }
# variable create_default_vpc{ default = true }
variable enable_autoscaling {default = true}

variable "ssh_public_key" {}
variable "ssh_key_name" {}
variable "ssh_key_value" {}
variable "disk_scale" {}

variable "ip_range" {
  type    = string
  default = "69.120.106.187/32"
}

variable "project_tags" {
  type        = map(string)
  description = "Tags used for gcp workload"
  default = {
    project = "gcp-tpcc-workload"
  }
}

variable "ssh_key_owner" {
  type        = string
  default     = "llong_adapture_com"
  description = "GCE user required for public key authorization"
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

variable "cluster_defaults" {
  description = "Default settings to be used for our aws clusters so we don't need to provide them for each machine separately."
  type        = object({
    image                 = string
    instance_architecture = string
    instance_type         = string
    instance_memory       = number
    instance_tags         = map(string)
  })
  default     = {
    image                 = "debian-cloud/debian-12"
    instance_architecture = "amd64"
    instance_type         = "e2-micro"
    instance_memory       = 32
    instance_tags         = {
      name = "dev"
    }
  }
}
