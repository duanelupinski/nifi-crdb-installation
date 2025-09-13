terraform {
  required_version = ">= 0.14.9"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 4.59.0"
    }
  }
}



## VPC AND ZONES ##

# the default vpc for the current region
resource "aws_default_vpc" "default" {
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.project_tags,
    {
      Name = "Default VPC"
    }
  )
}

# the existing internet gateway for the vpc
data "aws_internet_gateway" "internet" {
  filter {
    name   = "attachment.vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

# Determine all of the available availability zones in the current AWS region.
data "aws_availability_zones" "available" {
  state = "available"
}

# This additional data source determines some additional
# details about each VPC, including its suffix letter.
data "aws_availability_zone" "all" {
  for_each = toset(data.aws_availability_zones.available.names)
  name = each.key
}



## SUBNETS AND GATEWAYS ##

# the default subnets for each availability zone in the region
resource "aws_default_subnet" "subnets" {
  for_each = data.aws_availability_zone.all
  availability_zone = each.value.name

  tags = merge(
    var.project_tags,
    {
      Name = each.value.name
    }
  )
}

# A nat gateway for each subnet
resource "aws_nat_gateway" "nat_gateways" {
  for_each = resource.aws_default_subnet.subnets

  connectivity_type = "private"
  subnet_id         = each.value.id

  tags = merge(
    var.project_tags,
    {
      Zone = each.value.availability_zone
    }
  )

  depends_on = [data.aws_internet_gateway.internet]
}



## ROUTES AND NACLS ##

# the default route table to associate with each subnet
resource "aws_default_route_table" "route_table" {
  default_route_table_id = aws_default_vpc.default.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.internet.id
  }

  tags = merge(
    var.project_tags,
    {
      Name = "Default Route Table"
    }
  )
}

resource "aws_route_table_association" "route_table_association" {
  for_each       = resource.aws_default_subnet.subnets
  subnet_id      = each.value.id
  route_table_id = aws_default_route_table.route_table.default_route_table_id
}

# the default access control list to associate with each subnet
resource "aws_default_network_acl" "nacl" {
  default_network_acl_id = aws_default_vpc.default.default_network_acl_id

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    var.project_tags,
    {
      Name = "Default Network ACL"
    }
  )
}

resource "aws_network_acl_association" "nacl_association" {
  for_each       = resource.aws_default_subnet.subnets
  subnet_id      = each.value.id
  network_acl_id = aws_default_network_acl.nacl.default_network_acl_id
}



## OBSOLETE CONFIG ##

#locals {
  #all_subnets = concat(var.subnets, var.extra_subnets)

#  all_route_tables      = concat(var.route_tables, var.extra_route_tables)
#  all_route_table_rules = concat(var.route_table_rules, var.extra_route_table_rules)

#  all_gateways = concat(var.gateways, var.extra_gateways)

#  internet_gateways = [for gateway in local.all_gateways : gateway if gateway.type == "internet"]
#  nat_gateways      = [for gateway in local.all_gateways : gateway if gateway.type == "nat"]

#  all_nacls      = concat(var.nacls, var.extra_nacls)
#  all_nacl_rules = concat(var.nacl_rules, var.extra_nacl_rules)
#}

#resource "aws_vpc" "main" {
#  cidr_block                     = var.vpc["cidr_block"]
#  enable_dns_hostnames           = true
#  enable_dns_support             = true
#
#  tags = merge(
#    var.project_tags,
#    {
#      Name = var.vpc.name
#    },
#  var.vpc)
#}

#resource "aws_subnet" "subnets" {
#  for_each          = { for subnet in local.all_subnets : subnet.name => subnet }
#  vpc_id            = aws_vpc.main.id
#  cidr_block        = each.value.cidr_block
#  availability_zone = each.value.availability_zone
#
#  tags = merge(
#    var.project_tags,
#    {
#      Name = each.value.name
#    },
#    each.value
#  )
#}

### Gateways ###

#resource "aws_internet_gateway" "internet" {
#  for_each = { for gateway in local.internet_gateways : gateway.name => gateway }
#  vpc_id   = aws_vpc.main.id
#
#  tags = merge(
#    var.project_tags,
#    {
#      Name = each.value.name
#    },
#    each.value
#  )
#}

#resource "aws_eip" "nat_ips" {
#  for_each = { for gateway in local.nat_gateways : gateway.name => gateway }
#  domain   = "vpc"
#}

#resource "aws_nat_gateway" "nat_gateways" {
#  for_each = { for gateway in local.nat_gateways : gateway.name => gateway }
#
#  allocation_id = aws_eip.nat_ips[each.value.name].id
#  subnet_id     = aws_subnet.subnets[each.value.associate_with_subnet].id
#
#  tags = merge(
#    var.project_tags,
#    {
#      Name = each.value.name
#    },
#    each.value
#  )
#}

### Route Tables ###

#resource "aws_route_table" "route_tables" {
#  for_each = { for route_table in local.all_route_tables : route_table.name => route_table }
#  vpc_id   = aws_vpc.main.id
#
#  dynamic "route" {
#    for_each = { for rule in local.all_route_table_rules : rule.name => rule if rule.associate_with_route_table == each.value.name }
#    content {
#      cidr_block     = route.value.cidr_block
#      gateway_id     = route.value.gateway_type == "internet" ? aws_internet_gateway.internet[route.value.associate_with_gateway].id : null
#      nat_gateway_id = route.value.gateway_type == "nat" ? aws_nat_gateway.nat_gateways[route.value.associate_with_gateway].id : null
#    }
#  }
#
#  tags = merge(
#    var.project_tags,
#    {
#      Name = each.value.name
#    }
#  )
#}


#resource "aws_route_table_association" "route_table_association" {
#  for_each       = { for route_table in local.all_route_tables : route_table.name => route_table }
#  subnet_id      = aws_subnet.subnets[each.value.associate_with_subnet].id
#  route_table_id = aws_route_table.route_tables[each.value.name].id
#}

### NACLs ###

#resource "aws_network_acl" "nacls" {
#  for_each = { for nacl in local.all_nacls : nacl.name => nacl }
#  vpc_id   = aws_vpc.main.id
#
#  dynamic "egress" {
#    for_each = { for rule in local.all_nacl_rules : rule.name => rule if rule.rule_type == "egress" && rule.associate_with_nacl == each.value.name }
#    content {
#      protocol   = egress.value.protocol
#      rule_no    = egress.value.rule_no
#      action     = egress.value.action
#      cidr_block = egress.value.cidr_block
#      from_port  = egress.value.from_port
#      to_port    = egress.value.to_port
#    }
#  }
#
#  dynamic "ingress" {
#    for_each = { for rule in local.all_nacl_rules : rule.name => rule if rule.rule_type == "ingress" && rule.associate_with_nacl == each.value.name }
#    content {
#      protocol   = ingress.value.protocol
#      rule_no    = ingress.value.rule_no
#      action     = ingress.value.action
#      cidr_block = ingress.value.cidr_block
#      from_port  = ingress.value.from_port
#      to_port    = ingress.value.to_port
#    }
#  }
#
#  ingress {
#    protocol   = "tcp"
#    rule_no    = 120
#    action     = "allow"
#    cidr_block = var.ssh_ip_range
#    from_port  = 22
#    to_port    = 22
#  }
#
#  tags = merge(
#    var.project_tags,
#    {
#      Name = each.value.name
#    }
#  )
#}

#resource "aws_network_acl_association" "nacl_association" {
#  for_each       = { for nacl in local.all_nacls : nacl.name => nacl }
#  network_acl_id = aws_network_acl.nacls[each.value.name].id
#  subnet_id      = aws_subnet.subnets[each.value.associate_with_subnet].id
#}
