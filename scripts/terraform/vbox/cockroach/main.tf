locals {
  # define cluster definitions for the system under test
  test_clusters = {
    crdb-small = {
      cluster_name = "crdb-small"
    }
    crdb-medium = {
      cluster_name = "crdb-medium"
      cockroach_image  = "/mnt/vbox/cockroach-medium-image.box"
      cockroach_cpus   = 4
      cockroach_memory = "8192 mib"
    }
  }

  # merge cluster default settings with specific cluster settings defined above
  clusters = {
    for cluster, settings in local.test_clusters : cluster => merge(
      var.cluster_defaults,
      settings
    )
  }
}

module "cluster" {
  source = "./cluster"

  for_each = local.clusters

  cluster_name             = each.value.cluster_name
  cluster_user             = each.value.cluster_user
  public_key_name          = var.ssh_key_name
  network_adapter_settings = each.value.adapter_settings
  
  cockroach_image          = each.value.cockroach_image
  cockroach_cpus           = each.value.cockroach_cpus
  cockroach_memory         = each.value.cockroach_memory
  
  proxy_image              = each.value.proxy_image
  proxy_cpus               = each.value.proxy_cpus
  proxy_memory             = each.value.proxy_memory
  
  workload_image           = each.value.workload_image
  workload_cpus            = each.value.workload_cpus
  workload_memory          = each.value.workload_memory
}
