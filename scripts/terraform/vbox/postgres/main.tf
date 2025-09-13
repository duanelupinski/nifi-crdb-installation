locals {
  # define instance definitions for the system under test
  test_instances = {
    pg-small = {
      instance_name = "pg-small"
    }
    pg-one = {
      instance_name = "pg-one"
    }
    pg-two = {
      instance_name = "pg-two"
    }
    pg-three = {
      instance_name = "pg-three"
    }
    pg-four = {
      instance_name = "pg-four"
    }
    pg-five = {
      instance_name = "pg-five"
    }
    pg-six = {
      instance_name = "pg-six"
    }
    pg-seven = {
      instance_name = "pg-seven"
    }
    pg-eight = {
      instance_name = "pg-eight"
    }
    pg-nine = {
      instance_name = "pg-nine"
    }
    pg-medium = {
      instance_name   = "pg-medium"
      postgres_image  = "/mnt/vbox/postgres-medium-image.box"
      postgres_cpus   = 4
      postgres_memory = "8192 mib"
    }
    pg-large = {
      instance_name   = "pg-large"
      postgres_image  = "/mnt/vbox/postgres-large-image.box"
      postgres_cpus   = 8
      postgres_memory = "16384 mib"
    }
    pg-xlarge = {
      instance_name   = "pg-xlarge"
      postgres_image  = "/mnt/vbox/postgres-xlarge-image.box"
      postgres_cpus   = 16
      postgres_memory = "32768 mib"
    }
  }

  # merge instance default settings with specific instance settings defined above
  instances = {
    for instance, settings in local.test_instances : instance => merge(
      var.instance_defaults,
      settings
    )
  }
}

module "instance" {
  source = "./instance"

  for_each = local.instances

  instance_name            = each.value.instance_name
  instance_user            = each.value.instance_user
  public_key_name          = var.ssh_key_name
  network_adapter_settings = each.value.adapter_settings
  
  postgres_image           = each.value.postgres_image
  postgres_cpus            = each.value.postgres_cpus
  postgres_memory          = each.value.postgres_memory
  
  workload_image           = each.value.workload_image
  workload_cpus            = each.value.workload_cpus
  workload_memory          = each.value.workload_memory
}
