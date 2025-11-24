terraform {
  required_version = ">= 0.14.9"
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">= 5.14.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

data "google_client_openid_userinfo" "me" {
}

resource "google_os_login_ssh_public_key" "default" {
  project = var.project
  user    = data.google_client_openid_userinfo.me.email
  key     = file(var.ssh_public_key)
}

### Modules ###

module "gcp_vpc" {
  source  = "../../gcp-vpc"

  region = var.region
  project = var.project
  name = var.name
  ssh_ip_range = var.ip_range
}

### Locals ###

locals {
  cloud_init_node = "./cloud-init/start-node.yml"
  cloud_init_proxy = "./cloud-init/start-proxy.yml"
  cloud_init_workload = "./cloud-init/start-workload.yml"
  cloud_init_vars = {
    gce_region   = var.region
    vm_user      = var.vm_user
    ssh_key      = var.ssh_key_value
  }

  cluster_config = {
    project_tags             = var.project_tags
    cloud_init_node          = local.cloud_init_node
    cloud_init_proxy         = local.cloud_init_proxy
    cloud_init_workload      = local.cloud_init_workload
    cloud_init_vars          = local.cloud_init_vars
  }

  # define cluster definitions for the system under test
  test_clusters = {
    c2d-highcpu-2 = {
      instance_type = "c2d-highcpu-2"
      instance_memory = 4
    }
    c3d-highcpu-4 = {
      instance_type = "c3d-highcpu-4"
      instance_memory = 8
    }
    c3d-highcpu-8 = {
      instance_type = "c3d-highcpu-8"
      instance_memory = 16
    }
    c3d-highmem-8 = {
      instance_type = "c3d-highmem-8"
      instance_memory = 64
    }
    c3d-standard-8 = {
      instance_type = "c3d-standard-8"
      instance_memory = 32
    }
    c3-highcpu-8 = {
      instance_type = "c3-highcpu-8"
      instance_memory = 16
    }
    c3-highmem-8 = {
      instance_type = "c3-highmem-8"
      instance_memory = 64
    }
    c3-standard-8 = {
      instance_type = "c3-standard-8"
      instance_memory = 32
    }
    c2d-highcpu-16 = {
      instance_type = "c2d-highcpu-16"
      instance_memory = 32
    }
    c2d-highcpu-32 = {
      instance_type = "c2d-highcpu-32"
      instance_memory = 64 
    }
    c2d-highmem-16 = {
      instance_type = "c2d-highmem-16"
      instance_memory = 128
    }
    c2d-highmem-32 = {
      instance_type = "c2d-highmem-32"
      instance_memory = 256
    }
    c2d-standard-16 = {
      instance_type = "c2d-standard-16"
      instance_memory = 64
    }
    c2d-standard-32 = {
      instance_type = "c2d-standard-32"
      instance_memory = 128
    }
    c2-standard-16 = {
      instance_type = "c2-standard-16"
      instance_memory = 64
    }
    c2-standard-30 = {
      instance_type = "c2-standard-30"
      instance_memory = 128
    }
    c3d-highcpu-16 = {
      instance_type = "c3d-highcpu-16"
      instance_memory = 32
    }
    c3d-highmem-16 = {
      instance_type = "c3d-highmem-16"
      instance_memory = 128
    }
    c3d-standard-16 = {
      instance_type = "c3d-standard-16"
      instance_memory = 64
    }
    c3d-standard-30 = {
      instance_type = "c3d-standard-30"
      instance_memory = 128
    }
    e2-highcpu-16 = {
      instance_type = "e2-highcpu-16"
      instance_memory = 16
    }
    e2-highcpu-32 = {
      instance_type = "e2-highcpu-32"
      instance_memory = 32
    }
    e2-highmem-16 = {
      instance_type = "e2-highmem-16"
      instance_memory = 128
    }
    e2-standard-16 = {
      instance_type = "e2-standard-16"
      instance_memory = 64
    }
    e2-standard-32 = {
      instance_type = "e2-standard-32"
      instance_memory = 128
    }
    n1-standard-32 = {
      instance_type = "n1-standard-32"
      instance_memory = 128
    }
    n2d-highcpu-16 = {
      instance_type = "n2d-highcpu-16"
      instance_memory = 16
    }
    n2d-highcpu-32 = {
      instance_type = "n2d-highcpu-32"
      instance_memory = 32
    }
    n2d-highmem-16 = {
      instance_type = "n2d-highmem-16"
      instance_memory = 128
    }
    n2d-highmem-32 = {
      instance_type = "n2d-highmem-32"
      instance_memory = 256
    }
    n2d-standard-16 = {
      instance_type = "n2d-standard-16"
      instance_memory = 64
    }
    n2d-standard-32 = {
      instance_type = "n2d-standard-32"
      instance_memory = 128
    }
    n2-highcpu-16 = {
      instance_type = "n2-highcpu-16"
      instance_memory = 16
    }
    n2-highcpu-32 = {
      instance_type = "n2-highcpu-32"
      instance_memory = 32
    }
    n2-highmem-16 = {
      instance_type = "n2-highmem-16"
      instance_memory = 128
    }
    n2-highmem-32 = {
      instance_type = "n2-highmem-32"
      instance_memory = 256
    }
    n2-standard-16 = {
      instance_type = "n2-standard-16"
      instance_memory = 64
    }
    n2-standard-32 = {
      instance_type = "n2-standard-32"
      instance_memory = 128
    }
    t2d-standard-16 = {
      instance_type = "t2d-standard-16"
      instance_memory = 64
    }
    t2d-standard-32 = {
      instance_type = "t2d-standard-32"
      instance_memory = 128
    }
  }

  # merge cluster default settings with the config and specific cluster settings defined above
  clusters = {
    for cluster, settings in local.test_clusters : cluster => merge(
      var.cluster_defaults,
      local.cluster_config,
      settings
    )
  }
}

module "cluster" {
  source = "./cluster"

  depends_on = [
    google_os_login_ssh_public_key.default,
    module.gcp_vpc
  ]

  for_each = local.clusters

  name          = var.name
  env           = var.env
  region        = var.region
  zones         = module.gcp_vpc.zones
  subnetId      = module.gcp_vpc.subnets[0].id
  vm_user       = var.vm_user
  ssh_key_owner = var.ssh_key_owner
  project_tags  = each.value.project_tags
  disk_size     = floor((floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) > 1 ? floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) : 10) * 10 * 0.2 + 0.5)
  disk_iops     = min(50 * floor((floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) > 1 ? floor(each.value.instance_memory / 4 / 0.1 * var.disk_scale * 0.9 / 10) : 10) * 10 * 0.2 + 0.5), 3000)

  public_key_name       = var.ssh_key_name
  image                 = each.value.image
  instance_type         = each.value.instance_type
  instance_architecture = each.value.instance_architecture
  instance_tags         = merge(each.value.instance_tags, {type = each.value.instance_type})
  cloud_init_node       = each.value.cloud_init_node
  cloud_init_proxy      = each.value.cloud_init_proxy
  cloud_init_workload   = each.value.cloud_init_workload
  cloud_init_vars       = each.value.cloud_init_vars
}
