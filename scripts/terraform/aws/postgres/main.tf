terraform {
  required_version = ">= 0.14.9"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 4.59.0"
    }
  }
}

provider "aws" {
  region = var.region
}

### Locals ###

locals {
  aws_security_group_rules = [
    {
      type        = "ingress"
      description = "TLS from VPC"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ip_range]
    },
    {
      type        = "ingress"
      description = "dns-udp"
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      cidr_blocks = [var.anywhere_cidr]
    },
    {
      type        = "ingress"
      description = "dns-tcp"
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      cidr_blocks = [var.anywhere_cidr]
    },
    {
      type        = "ingress"
      description = "https"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [var.anywhere_cidr]
    },
    {
      type        = "ingress"
      description = "postgres"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [var.ip_range]
    },
    {
      type        = "ingress"
      description = "ext-pgbouncer"
      from_port   = 4432
      to_port     = 4432
      protocol    = "tcp"
      cidr_blocks = [var.ip_range]
    },
    {
      type        = "ingress"
      description = "int-pgbouncer"
      from_port   = 4432
      to_port     = 4432
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    },
    {
      type        = "ingress"
      description = "nodeexporter"
      from_port   = 9100
      to_port     = 9100
      protocol    = "tcp"
      cidr_blocks = [var.ip_range]
    },
    {
      type        = "ingress"
      description = "pgexporter"
      from_port   = 9187
      to_port     = 9187
      protocol    = "tcp"
      cidr_blocks = [var.ip_range]
    },
    {
      type        = "egress"
      description = "connect to internet"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [var.anywhere_cidr]
    }
  ]

  cloud_init_filepath = "./cloud-init/start-instance.yml"
  cloud_init_workload = "./cloud-init/start-workload.yml"
  cloud_init_vars = {
    aws_region = var.region
    aws_key    = var.key
    aws_secret = var.secret
    vm_user   = var.vm_user
    ssh_key    = var.ssh_key_value
  }

  instance_config = {
    project_tags             = var.project_tags
    cloud_init_filepath      = local.cloud_init_filepath
    cloud_init_workload      = local.cloud_init_workload
    cloud_init_vars          = local.cloud_init_vars
  }

  # define instance definitions for the system under test
  test_instances = {
#    t3a-micro = {
#      instance_type = "t3a.micro"
#    }
    c6in-4xlarge = {
      instance_type = "c6in.4xlarge"
    }
    c6id-4xlarge = {
      instance_type = "c6id.4xlarge"
    }
    c6i-4xlarge = {
      instance_type = "c6i.4xlarge"
    }
    c5d-4xlarge = {
      instance_type = "c5d.4xlarge"
    }
    c5-4xlarge = {
      instance_type = "c5.4xlarge"
    }
    c7g-4xlarge = {
      instance_type = "c7g.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
    }
    c6g-4xlarge = {
      instance_type = "c6g.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
    }
    c6gn-4xlarge = {
      instance_type = "c6gn.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
    }
    c6gd-4xlarge = {
      instance_type = "c6gd.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
    }
    c6a-4xlarge = {
      instance_type = "c6a.4xlarge"
    }
    c5ad-4xlarge = {
      instance_type = "c5ad.4xlarge"
    }
    c5a-4xlarge = {
      instance_type = "c5a.4xlarge"
    }
    c7a-4xlarge = {
      instance_type = "c7a.4xlarge"
    }
    c7i-4xlarge = {
      instance_type = "c7i.4xlarge"
    }
    m5d-4xlarge = {
      instance_type = "m5d.4xlarge"
      instance_memory = 64
    }
    m5-4xlarge = {
      instance_type = "m5.4xlarge"
      instance_memory = 64
    }
    m4-4xlarge = {
      instance_type = "m4.4xlarge"
      instance_memory = 64
    }
    c6in-8xlarge = {
      instance_type = "c6in.8xlarge"
      instance_memory = 64
    }
    m5a-4xlarge = {
      instance_type = "m5a.4xlarge"
      instance_memory = 64
    }
    m5ad-4xlarge = {
      instance_type = "m5ad.4xlarge"
      instance_memory = 64
    }
    c6id-8xlarge = {
      instance_type = "c6id.8xlarge"
      instance_memory = 64
    }
    c6i-8xlarge = {
      instance_type = "c6i.8xlarge"
      instance_memory = 64
    }
    m6in-4xlarge = {
      instance_type = "m6in.4xlarge"
      instance_memory = 64
    }
    m6idn-4xlarge = {
      instance_type = "m6idn.4xlarge"
      instance_memory = 64
    }
    m6id-4xlarge = {
      instance_type = "m6id.4xlarge"
      instance_memory = 64
    }
    m6i-4xlarge = {
      instance_type = "m6i.4xlarge"
      instance_memory = 64
    }
    m5n-4xlarge = {
      instance_type = "m5n.4xlarge"
      instance_memory = 64
    }
    m5dn-4xlarge = {
      instance_type = "m5dn.4xlarge"
      instance_memory = 64
    }
    c5a-8xlarge = {
      instance_type = "c5a.8xlarge"
      instance_memory = 64
    }
    c5ad-8xlarge = {
      instance_type = "c5ad.8xlarge"
      instance_memory = 64
    }
    c7g-8xlarge = {
      instance_type = "c7g.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 64
    }
    m6a-4xlarge = {
      instance_type = "m6a.4xlarge"
      instance_memory = 64
    }
    m7g-4xlarge = {
      instance_type = "m7g.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 64
    }
    c6a-8xlarge = {
      instance_type = "c6a.8xlarge"
      instance_memory = 64
    }
    c7a-8xlarge = {
      instance_type = "c7a.8xlarge"
      instance_memory = 64
    }
    c7i-8xlarge = {
      instance_type = "c7i.8xlarge"
      instance_memory = 64
    }
    m7a-4xlarge = {
      instance_type = "m7a.4xlarge"
      instance_memory = 64
    }
    m7i-4xlarge = {
      instance_type = "m7i.4xlarge"
      instance_memory = 64
    }
    m7i-flex-4xlarge = {
      instance_type = "m7i-flex.4xlarge"
      instance_memory = 64
    }
    c6g-8xlarge = {
      instance_type = "c6g.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 64
    }
    m6gd-4xlarge = {
      instance_type = "m6gd.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 64
    }
    m6g-4xlarge = {
      instance_type = "m6g.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 64
    }
    c6gn-8xlarge = {
      instance_type = "c6gn.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 64
    }
    c6gd-8xlarge = {
      instance_type = "c6gd.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 64
    }
    m5d-8xlarge = {
      instance_type = "m5d.8xlarge"
      instance_memory = 128
    }
    m5-8xlarge = {
      instance_type = "m5.8xlarge"
      instance_memory = 128
    }
    r5d-4xlarge = {
      instance_type = "r5d.4xlarge"
      instance_memory = 128
    }
    r5-4xlarge = {
      instance_type = "r5.4xlarge"
      instance_memory = 128
    }
    m6in-8xlarge = {
      instance_type = "m6in.8xlarge"
      instance_memory = 128
    }
    m6idn-8xlarge = {
      instance_type = "m6idn.8xlarge"
      instance_memory = 128
    }
    r5a-4xlarge = {
      instance_type = "r5a.4xlarge"
      instance_memory = 128
    }
    r5ad-4xlarge = {
      instance_type = "r5ad.4xlarge"
      instance_memory = 128
    }
    m5a-8xlarge = {
      instance_type = "m5a.8xlarge"
      instance_memory = 128
    }
    m5ad-8xlarge = {
      instance_type = "m5ad.8xlarge"
      instance_memory = 128
    }
    m6id-8xlarge = {
      instance_type = "m6id.8xlarge"
      instance_memory = 128
    }
    m6i-8xlarge = {
      instance_type = "m6i.8xlarge"
      instance_memory = 128
    }
    r6in-4xlarge = {
      instance_type = "r6in.4xlarge"
      instance_memory = 128
    }
    r6idn-4xlarge = {
      instance_type = "r6idn.4xlarge"
      instance_memory = 128
    }
    r6id-4xlarge = {
      instance_type = "r6id.4xlarge"
      instance_memory = 128
    }
    r6i-4xlarge = {
      instance_type = "r6i.4xlarge"
      instance_memory = 128
    }
    m5n-8xlarge = {
      instance_type = "m5n.8xlarge"
      instance_memory = 128
    }
    m5dn-8xlarge = {
      instance_type = "m5dn.8xlarge"
      instance_memory = 128
    }
    r6a-4xlarge = {
      instance_type = "r6a.4xlarge"
      instance_memory = 128
    }
    r5n-4xlarge = {
      instance_type = "r5n.4xlarge"
      instance_memory = 128
    }
    m6a-8xlarge = {
      instance_type = "m6a.8xlarge"
      instance_memory = 128
    }
    r5dn-4xlarge = {
      instance_type = "r5dn.4xlarge"
      instance_memory = 128
    }
    r5b-4xlarge = {
      instance_type = "r5b.4xlarge"
      instance_memory = 128
    }
    m7a-8xlarge = {
      instance_type = "m7a.8xlarge"
      instance_memory = 128
    }
    m7i-8xlarge = {
      instance_type = "m7i.8xlarge"
      instance_memory = 128
    } 
    m7i-flex-8xlarge = {
      instance_type = "m7i-flex.8xlarge"
      instance_memory = 128
    }
    r7a-4xlarge = {
      instance_type = "r7a.4xlarge"
      instance_memory = 128
    }  
    r7i-4xlarge = {
      instance_type = "r7i.4xlarge"
      instance_memory = 128
    }
    r7iz-4xlarge = {
      instance_type = "r7iz.4xlarge"
      instance_memory = 128
    }
    m7g-8xlarge = {
      instance_type = "m7g.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 128
    }
    r6g-4xlarge = {
      instance_type = "r6g.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 128
    }
    r6gd-4xlarge = {
      instance_type = "r6gd.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 128
    }
    r7g-4xlarge = {
      instance_type = "r7g.4xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 128
    }
    m6gd-8xlarge = {
      instance_type = "m6gd.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 128
    }
    m6g-8xlarge = {
      instance_type = "m6g.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 128
    }
    r5d-8xlarge = {
      instance_type = "r5d.8xlarge"
      instance_memory = 256
    }
    r5-8xlarge = {
      instance_type = "r5.8xlarge"
      instance_memory = 256
    }
    r6in-8xlarge = {
      instance_type = "r6in.8xlarge"
      instance_memory = 256
    }
    r6idn-8xlarge = {
      instance_type = "r6idn.8xlarge"
      instance_memory = 256
    }
    r6id-8xlarge = {
      instance_type = "r6id.8xlarge"
      instance_memory = 256
    }
    r6i-8xlarge = {
      instance_type = "r6i.8xlarge"
      instance_memory = 256
    }
    r5n-8xlarge = {
      instance_type = "r5n.8xlarge"
      instance_memory = 256
    }
    r5dn-8xlarge = {
      instance_type = "r5dn.8xlarge"
      instance_memory = 256
    }
    r5b-8xlarge = {
      instance_type = "r5b.8xlarge"
      instance_memory = 256
    }
    r7g-8xlarge = {
      instance_type = "r7g.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 256
    }
    r5a-8xlarge = {
      instance_type = "r5a.8xlarge"
      instance_memory = 256
    }
    r5ad-8xlarge = {
      instance_type = "r5ad.8xlarge"
      instance_memory = 256
    }
    r6gd-8xlarge = {
      instance_type = "r6gd.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 256
    }
    r6g-8xlarge = {
      instance_type = "r6g.8xlarge"
      ami_id = "ami-0d3eda47adff3e44b"
      instance_architecture = "arm64"
      instance_memory = 256
    }
    r6a-8xlarge = {
      instance_type = "r6a.8xlarge"
      instance_memory = 256
    }
    r7a-8xlarge = {
      instance_type = "r7a.8xlarge"
      instance_memory = 256
    }
    r7i-8xlarge = {
      instance_type = "r7i.8xlarge"
      instance_memory = 256
    }
    r7iz-8xlarge = {
      instance_type = "r7iz.8xlarge"
      instance_memory = 256
    }
  }

  # merge instance default settings with the config and specific instance settings defined above
  instances = {
    for instance, settings in local.test_instances : instance => merge(
      var.instance_defaults,
      local.instance_config,
      settings
    )
  }
}

### Security Groups ###

resource "aws_default_security_group" "rules" {
  vpc_id = module.aws_vpc.vpc_id

  dynamic "ingress" {
    for_each = { for rule in local.aws_security_group_rules : rule.description => rule if rule.type == "ingress" }

    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = { for rule in local.aws_security_group_rules : rule.description => rule if rule.type == "egress" }

    content {
      description = egress.value.description
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = { for subnet in module.aws_vpc.subnets : subnet.availability_zone => subnet }
    content {
      description = "all traffic from ${ingress.value.availability_zone}"
      from_port   = 0
      to_port     = 0
      protocol    = -1
      cidr_blocks = [ingress.value.cidr_block]
    }
  }
}

### SSH Key ###

resource "aws_key_pair" "security" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_key_value
}

### Modules ###

module "aws_vpc" {
  source  = "../../aws-vpc"

  ssh_ip_range = var.ip_range
}

module "instance" {
  source = "./instance"

  depends_on = [
    aws_default_security_group.rules,
    aws_key_pair.security,
    module.aws_vpc
  ]

  for_each = local.instances

  security_group_id     = aws_default_security_group.rules.id
  project_tags          = each.value.project_tags
  disk_size             = floor((floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) > 1 ? floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) : 10) * 10 * 0.2 + 0.5)
  disk_iops             = min(50 * floor((floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) > 1 ? floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) : 10) * 10 * 0.2 + 0.5), 3000)

  ami_id                = each.value.ami_id
  public_key_name       = var.ssh_key_name

  instance_type         = each.value.instance_type
  instance_architecture = each.value.instance_architecture
  instance_tags         = merge(each.value.instance_tags, {Type = each.value.instance_type})
  cloud_init_filepath   = each.value.cloud_init_filepath
  cloud_init_workload   = each.value.cloud_init_workload
  cloud_init_vars       = each.value.cloud_init_vars
}
