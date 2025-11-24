
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
  default      = "amd-gcp"
}

variable "ip_cidr_range" {
  type        = list(string)
  description = "List of The range of internal addresses that are owned by this subnetwork."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "ssh_ip_range" {
  type        = string
  description = "Your public IP for SSHing to gcp instances"
  default     = "0.0.0.0/0"

  validation {
    condition     = length(split("/", var.ssh_ip_range)) == 2
    error_message = "You must supply a cidr range with a '/', e.g. 0.0.0.0/0"
  }

  validation {
    condition     = length(split(".", split("/", var.ssh_ip_range)[0])) == 4
    error_message = "IP in cidr range must be separated by 3 periods '.' e.g. 0.0.0.0"
  }

  validation {
    condition     = length([for elem in split(".", split("/", var.ssh_ip_range)[0]) : tonumber(elem)]) == 4
    error_message = "IP part of cidr range must consists of integers."
  }
}

variable "project_tags" {
  type        = map(string)
  description = "Tags used for gcp tutorial"
  default = {
    project = "gcp-terraform-test"
  }
}

#variable "region_number" {
#  # Arbitrary mapping of region name to number to use in a VPC's CIDR prefix.
#  default = {
#    us-east1       = 1
#    us-east4       = 2
#    us-east5       = 3
#    us-south1      = 4
#    us-central1    = 5
#    us-west1       = 6
#    us-west2       = 7
#    us-west3       = 8
#    us-west4       = 9
#  }
#}

#variable "az_number" {
#  # Assign a number to each AZ letter used in our configuration
#  default = {
#    us-east4-a = 1
#    us-east4-b = 2
#    us-east4-c = 3
#    # and so on, up to n = 14 if that many letters are assigned
#  }
#}
