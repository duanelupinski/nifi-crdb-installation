variable "ssh_ip_range" {
  type        = string
  description = "Your public IP for SSHing to aws instances"
  default     = "0.0.0.0/0"

  validation {
    condition     = length(split("/", var.ssh_ip_range)) == 2
    error_message = "You must supply a cidr range with a '/', e.g. 0.0.0.0/0."
  }

  validation {
    condition     = length(split(".", split("/", var.ssh_ip_range)[0])) == 4
    error_message = "IP in cidr range must be separated by 4 periods '.' e.g. 0.0.0.0 ."
  }

  validation {
    condition     = length([for elem in split(".", split("/", var.ssh_ip_range)[0]) : tonumber(elem)]) == 4
    error_message = "IP part of cidr range must consists of integers."
  }
}

variable "project_tags" {
  type        = map(string)
  description = "Tags used for aws tutorial"
  default = {
    project = "aws-terraform-test"
  }
}

variable "region_number" {
  # Arbitrary mapping of region name to number to use in a VPC's CIDR prefix.
  default = {
    us-east-1      = 1
    us-east-2      = 2
    us-west-1      = 3
    us-west-2      = 4
  }
}

variable "az_number" {
  # Assign a number to each AZ letter used in our configuration
  default = {
    us-east-1a = 1
    us-east-1b = 2
    us-east-1c = 3
    us-east-1d = 4
    us-east-1e = 5
    us-east-1f = 6
    # and so on, up to n = 14 if that many letters are assigned
  }
}



## OBSOLETE CONFIG ##

#variable "vpc" {
#  type = object({
#    cidr_block = string
#    name       = string
#  })
#  description = "VPC Related data"
#  default = {
#    cidr_block = "10.0.0.0/16",
#    name       = "main"
#  }
#}

#variable "subnets" {
#  type = list(object({
#    name              = string
#    description       = string
#    cidr_block        = string
#    type              = string
#    availability_zone = string
#  }))
#  description = "Subnet data"
#  default = [
#    {
#      name              = "amd-tpcc-pgdb-subnet-1",
#      description       = "AMD TPCC PGDB public subnets",
#      cidr_block        = "10.0.1.0/24",
#      type              = "public",
#      availability_zone = "us-east-1a"
#    }
#  ]
#}

#variable "extra_subnets" {
#  type = list(object({
#    name              = string
#    description       = string
#    cidr_block        = string
#    type              = string
#    availability_zone = string
#  }))
#  description = "Extra non-default subnet data"
#  default     = []
#}

#variable "gateways" {
#  type = list(object({
#    name                  = string
#    type                  = string
#    associate_with_subnet = string
#  }))
#  description = "Default gateways"
#  default = [
#    {
#      name                  = "internet GW",
#      type                  = "internet",
#      associate_with_subnet = null
#    },
#    {
#      name                  = "NAT GW",
#      type                  = "nat",
#      associate_with_subnet = "amd-tpcc-pgdb-subnet-1"
#    }
#  ]
#
#  validation {
#    # check type
#    condition     = length([for gateway in var.gateways : true if gateway.type == "nat" || gateway.type == "internet"]) == length(var.gateways)
#    error_message = "Only two gateways types--'nat' or 'internet'--are allowed for this current version."
#  }
#}

#variable "extra_gateways" {
#  type = list(object({
#    name                  = string
#    type                  = string
#    associate_with_subnet = string
#  }))
#  description = "Extra gateways"
#  default     = []
#}

#variable "route_tables" {
#  type = list(object({
#    name                  = string
#    description           = string
#    associate_with_subnet = string
#  }))
#  description = "Route tables for VPC"
#  default = [
#    {
#      name                  = "amd-tpcc-pgdb-route-table-1",
#      description           = "AMD TPCC PGDB public route table",
#      associate_with_subnet = "amd-tpcc-pgdb-subnet-1"
#    }
#  ]
#}

#variable "extra_route_tables" {
#  type = list(object({
#    name                  = string
#    description           = string
#    associate_with_subnet = string
#  }))
#  description = "Extra route tables"
#  default     = []
#}

#variable "route_table_rules" {
#  type = list(object({
#    name                       = string
#    description                = string
#    cidr_block                 = string
#    associate_with_route_table = string
#    associate_with_gateway     = string
#    gateway_type               = string
#  }))
#  description = "Default route table rules"
#  default = [
#    {
#      name                       = "amd-tpcc-pgdb-1-internet",
#      description                = "Route to the internet",
#      cidr_block                 = "0.0.0.0/0",
#      associate_with_route_table = "amd-tpcc-pgdb-route-table-1",
#      associate_with_gateway     = "internet GW",
#      gateway_type               = "internet"
#    }
#  ]
#}

#variable "extra_route_table_rules" {
#  type = list(object({
#    name                       = string
#    description                = string
#    cidr_block                 = string
#    associate_with_route_table = string
#    associate_with_gateway     = string
#    gateway_type               = string
#  }))
#  description = "Default route table rules"
#  default     = []
#}

#variable "nacls" {
#  type = list(object({
#    name                  = string
#    associate_with_subnet = string
#  }))
#  description = "Default NACLs"
#  default = [
#    {
#      name                  = "amd-tpcc-pgdb-nacl-1",
#      associate_with_subnet = "amd-tpcc-pgdb-subnet-1"
#    }
#  ]
#}

#variable "extra_nacls" {
#  type = list(object({
#    name                  = string
#    associate_with_subnet = string
#  }))
#  description = "Extra NACLs"
#  default     = []
#}

#variable "nacl_rules" {
#  type = list(object({
#    name                = string
#    rule_type           = string
#    associate_with_nacl = string
#    protocol            = string
#    rule_no             = string
#    action              = string
#    cidr_block          = string
#    from_port           = string
#    to_port             = string
#  }))
#  description = "Default NACL rules"
#  default = [
#    {
#      name                = "http-port80-egress",
#      rule_type           = "egress",
#      associate_with_nacl = "amd-tpcc-pgdb-nacl-1",
#      protocol            = "tcp",
#      rule_no             = 100,
#      action              = "allow",
#      cidr_block          = "0.0.0.0/0",
#      from_port           = 80
#      to_port             = 80
#    },
#    {
#      name                = "http-port443-egress",
#      rule_type           = "egress",
#      associate_with_nacl = "amd-tpcc-pgdb-nacl-1",
#      protocol            = "tcp",
#      rule_no             = 110,
#      action              = "allow",
#      cidr_block          = "0.0.0.0/0",
#      from_port           = 443
#      to_port             = 443
#    },
#    {
#      name                = "port-22-egress",
#      rule_type           = "egress",
#      associate_with_nacl = "amd-tpcc-pgdb-nacl-1",
#      protocol            = "tcp",
#      rule_no             = 150,
#      action              = "allow",
#      cidr_block          = "10.0.1.0/24",
#      from_port           = 22
#      to_port             = 22
#    },
#    {
#      name                = "dynamic-port-egress",
#      rule_type           = "egress",
#      associate_with_nacl = "amd-tpcc-pgdb-nacl-1",
#      protocol            = "tcp",
#      rule_no             = 140,
#      action              = "allow",
#      cidr_block          = "0.0.0.0/0",
#      from_port           = 1024
#      to_port             = 65535
#    },
#    {
#      name                = "http-port80-ingress",
#      rule_type           = "ingress",
#      associate_with_nacl = "amd-tpcc-pgdb-nacl-1",
#      protocol            = "tcp",
#      rule_no             = 100,
#      action              = "allow",
#      cidr_block          = "0.0.0.0/0",
#      from_port           = 80
#      to_port             = 80
#    },
#    {
#      name                = "http-port443-ingress",
#      rule_type           = "ingress",
#      associate_with_nacl = "amd-tpcc-pgdb-nacl-1",
#      protocol            = "tcp",
#      rule_no             = 110,
#      action              = "allow",
#      cidr_block          = "0.0.0.0/0",
#      from_port           = 443
#      to_port             = 443
#    },
#    {
#      name                = "dynamic-ports-ingress",
#      rule_type           = "ingress",
#      associate_with_nacl = "amd-tpcc-pgdb-nacl-1",
#      protocol            = "tcp",
#      rule_no             = 140,
#      action              = "allow",
#      cidr_block          = "0.0.0.0/0",
#      from_port           = 1024
#      to_port             = 65535
#    }
#  ]
#}

#variable "extra_nacl_rules" {
#  type = list(object({
#    name                = string
#    rule_type           = string
#    associate_with_nacl = string
#    protocol            = string
#    rule_no             = string
#    action              = string
#    cidr_block          = string
#    from_port           = string
#    to_port             = string
#  }))
#  description = "Extra NACL rules"
#  default     = []
#}
