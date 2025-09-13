terraform {
  required_providers {
    virtualbox = {
      source = "registry.local/local/virtualbox"
      version = "5.0.0"
    }
  }
  required_version = ">= 1.4"
}