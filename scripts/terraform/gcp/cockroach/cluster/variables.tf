### Required ###

variable "name" {
  type         = string
  description  = "Name for this infrastructure"
  default      = "amd-tpcc-crdb"
}

variable env {
  type         = string
  description  = "Environment for this infrastructure"
  default      = "dev"
}

variable "region" {
  type         = string
  description  = "Region for this infrastructure"
  default      = "us-east4"
}

variable "zones" {}
variable "subnetId" {}
variable "vm_user" {}
variable "ssh_key_owner" {}

variable "public_key_name" {
  type = string
  description = "Public key name for our cluster"
}

variable "instance_tags" {
  type        = map(any)
  description = "Any tags you'd like to associate with the cluster"
}

variable "image" {
  type        = string
  description = "Image qualifier used by the GCE instance"
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
  default     = "e2-micro"
  description = "GCE instance type"
}

variable "service_account" {
  type         = string
  description  = "Service account for this infrastructure"
  default      = "amd-tpcc-crdb@amd-dev-413115.iam.gserviceaccount.com"
}

variable "instance_architecture" {
  type        = string
  default     = "amd64"
  description = "GCE instance architecture"
}

variable "proxy_defaults" {
  description = "Default settings to be used for our gce instances that will be used to proxy requests."
  type        = object({
    image                 = string
    instance_type         = string
  })
  default     = {
    image                 = "debian-cloud/debian-12"
    instance_type         = "c3d-highcpu-4"
  }
}

variable "workload_defaults" {
  description = "Default settings to be used for our gce instances that will execute the workload."
  type        = object({
    image                 = string
    instance_type         = string
  })
  default     = {
    image                 = "debian-cloud/debian-12"
    instance_type         = "c3d-highcpu-4"
  }
}
