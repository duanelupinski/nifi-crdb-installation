terraform {
  required_version = ">= 0.14.9"
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">= 5.14.0"
    }
  }
}

data "google_compute_zones" "available" {
  region  = var.region
  project = var.project
  status = "UP"
}

locals {
  type  = ["public", "private"]
  zones = data.google_compute_zones.available.names
}

# VPC
resource "google_compute_network" "vpc" {
  name                            = "${var.name}-vpc"
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
}

# SUBNETS
resource "google_compute_subnetwork" "subnets" {
  count                    = 2
  name                     = "${var.name}-${local.type[count.index]}-subnetwork"
  ip_cidr_range            = var.ip_cidr_range[count.index]
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# FIREWALL
resource "google_compute_firewall" "allow-internal" {
  name    = "${var.name}-fw-allow-internal"
  network = google_compute_network.vpc.id
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  source_ranges = [
    google_compute_subnetwork.subnets[0].ip_cidr_range,
    google_compute_subnetwork.subnets[1].ip_cidr_range
  ]
}

resource "google_compute_firewall" "allow-http" {
  name    = "${var.name}-fw-allow-http"
  network = google_compute_network.vpc.id
  allow {
    protocol = "tcp"
    ports    = ["53", "80", "443", "4432", "8000", "8080", "9100", "26257"]
  }
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  target_tags = ["http"] 
  source_ranges = [
    var.ssh_ip_range
  ]
}

resource "google_compute_firewall" "allow-bastion" {
  name    = "${var.name}-fw-allow-bastion"
  network = google_compute_network.vpc.id
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  target_tags = ["ssh"]
  source_ranges = [
    var.ssh_ip_range
  ]
}

# NAT ROUTER
resource "google_compute_router" "router" {
  name    = "${var.name}-${local.type[1]}-router"
  region  = google_compute_subnetwork.subnets[1].region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name}-${local.type[1]}-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = "${var.name}-${local.type[1]}-subnetwork"
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

