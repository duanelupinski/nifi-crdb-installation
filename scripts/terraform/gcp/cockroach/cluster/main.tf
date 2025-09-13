terraform {
  required_version = ">= 0.14.9"
  required_providers {
    google = {
      source = "hashicorp/google"
      version = ">= 5.14.0"
    }
  }
}

data "template_file" "node" {
  template = file(var.cloud_init_node)

  vars = merge(
    var.cloud_init_vars,
    {
      architecture: var.instance_architecture
      instance_type: var.instance_type
    }
  )
}

data "template_file" "proxy" {
  template = file(var.cloud_init_proxy)

  vars = merge(
    var.cloud_init_vars,
    {
      architecture: var.instance_architecture
      instance_type: var.instance_type
    }
  )
}

data "template_file" "workload" {
  template = file(var.cloud_init_workload)
  vars = var.cloud_init_vars
}

resource random_id node1 {
  byte_length = 2
}

resource random_id node2 {
  byte_length = 2
}

resource random_id node3 {
  byte_length = 2
}

resource random_id proxy {
  byte_length = 2
}

resource random_id workload {
  byte_length = 2
}

locals {
  workload_zone_index = random_id.workload.dec % length(var.zones)
  proxy_zone_index = random_id.proxy.dec % length(var.zones)
  node1_zone_index = random_id.node1.dec % length(var.zones)
  node2_zone_index = random_id.node2.dec % length(var.zones)
  node3_zone_index = random_id.node3.dec % length(var.zones)
}

### GCE ###

resource "google_compute_disk" "node1" {
  name    = "${format("%s","${var.instance_type}-node1")}"
  zone    = var.zones[local.node1_zone_index]
  type    = "pd-ssd"
  size    = var.disk_size
  labels  = merge(var.project_tags, var.instance_tags)
  #provisioned_iops  = var.disk_iops
}

resource "google_compute_disk" "node2" {
  name    = "${format("%s","${var.instance_type}-node2")}"
  zone    = var.zones[local.node2_zone_index]
  type    = "pd-ssd"
  size    = var.disk_size
  labels  = merge(var.project_tags, var.instance_tags)
  #provisioned_iops  = var.disk_iops
}

resource "google_compute_disk" "node3" {
  name    = "${format("%s","${var.instance_type}-node3")}"
  zone    = var.zones[local.node3_zone_index]
  type    = "pd-ssd"
  size    = var.disk_size
  labels  = merge(var.project_tags, var.instance_tags)
  #provisioned_iops  = var.disk_iops
}

resource "google_compute_disk" "proxy" {
  name    = "${format("%s","${var.instance_type}-proxy")}"
  zone    = var.zones[local.proxy_zone_index]
  type    = "pd-ssd"
  size    = 50
  labels  = merge(var.project_tags, var.instance_tags)
  #provisioned_iops  = 1000
}

resource "google_compute_instance" "node1" {
  name         = "${format("%s","${var.name}-${var.instance_type}-node1")}"
  machine_type = var.instance_type
  zone         = var.zones[local.node1_zone_index]
  tags         = ["ssh", "http"]

  service_account {
    email  = var.service_account
    scopes = ["cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  attached_disk {
    source      = google_compute_disk.node1.id
    device_name = google_compute_disk.node1.name
  }

  labels = merge(var.project_tags, var.instance_tags)

  network_interface {
    subnetwork = var.subnetId

    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = <<-CLOUD_INIT
#!/bin/bash

if ! type cloud-init > /dev/null 2>&1 ; then
  echo "Ran - `date`" >> /root/startup
  sleep 30
  apt-get install -y cloud-init

  if [ $? == 0 ]; then
    echo "Ran - Success - `date`" >> /root/startup
    systemctl enable cloud-init
  else
    echo "Ran - Fail - `date`" >> /root/startup
  fi

  reboot
fi

CLOUD_INIT

  metadata = {
    ssh-keys = "${var.ssh_key_owner}:${file(var.public_key_name)}"
    user-data = "${data.template_file.node.rendered}"
  }
}

resource "google_compute_instance" "node2" {
  name         = "${format("%s","${var.name}-${var.instance_type}-node2")}"
  machine_type = var.instance_type
  zone         = var.zones[local.node2_zone_index]
  tags         = ["ssh", "http"]

  service_account {
    email  = var.service_account                                
    scopes = ["cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  attached_disk {
    source      = google_compute_disk.node2.id
    device_name = google_compute_disk.node2.name
  }

  labels = merge(var.project_tags, var.instance_tags)

  network_interface {
    subnetwork = var.subnetId

    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = <<-CLOUD_INIT
#!/bin/bash

if ! type cloud-init > /dev/null 2>&1 ; then
  echo "Ran - `date`" >> /root/startup
  sleep 30
  apt-get install -y cloud-init

  if [ $? == 0 ]; then
    echo "Ran - Success - `date`" >> /root/startup
    systemctl enable cloud-init
  else
    echo "Ran - Fail - `date`" >> /root/startup
  fi

  reboot
fi

CLOUD_INIT

  metadata = {
    ssh-keys = "${var.ssh_key_owner}:${file(var.public_key_name)}"
    user-data = "${data.template_file.node.rendered}"
  }
}

resource "google_compute_instance" "node3" {
  name         = "${format("%s","${var.name}-${var.instance_type}-node3")}"
  machine_type = var.instance_type
  zone         = var.zones[local.node3_zone_index]
  tags         = ["ssh", "http"]

  service_account {
    email  = var.service_account                                
    scopes = ["cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = var.image
    }
  }

  attached_disk {
    source      = google_compute_disk.node3.id
    device_name = google_compute_disk.node3.name
  }

  labels = merge(var.project_tags, var.instance_tags)

  network_interface {
    subnetwork = var.subnetId

    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = <<-CLOUD_INIT
#!/bin/bash

if ! type cloud-init > /dev/null 2>&1 ; then
  echo "Ran - `date`" >> /root/startup
  sleep 30
  apt-get install -y cloud-init

  if [ $? == 0 ]; then
    echo "Ran - Success - `date`" >> /root/startup
    systemctl enable cloud-init
  else
    echo "Ran - Fail - `date`" >> /root/startup
  fi

  reboot
fi

CLOUD_INIT

  metadata = {
    ssh-keys = "${var.ssh_key_owner}:${file(var.public_key_name)}"
    user-data = "${data.template_file.node.rendered}"
  }
}

resource "google_compute_instance" "proxy" {
  name         = "${format("%s","${var.name}-${var.instance_type}-proxy")}"
  machine_type = var.proxy_defaults.instance_type
  zone         = var.zones[local.proxy_zone_index]
  tags         = ["ssh", "http"]

  service_account {
    email  = var.service_account                                
    scopes = ["cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = var.proxy_defaults.image
    }
  }

  attached_disk {
    source      = google_compute_disk.proxy.id
    device_name = google_compute_disk.proxy.name
  }

  labels = merge(var.project_tags, var.instance_tags)

  network_interface {
    subnetwork = var.subnetId

    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = <<-CLOUD_INIT
#!/bin/bash

if ! type cloud-init > /dev/null 2>&1 ; then
  echo "Ran - `date`" >> /root/startup
  sleep 30
  apt-get install -y cloud-init

  if [ $? == 0 ]; then
    echo "Ran - Success - `date`" >> /root/startup
    systemctl enable cloud-init
  else
    echo "Ran - Fail - `date`" >> /root/startup
  fi

  reboot
fi

CLOUD_INIT

  metadata = {
    ssh-keys = "${var.ssh_key_owner}:${file(var.public_key_name)}"
    user-data = "${data.template_file.proxy.rendered}"
  }
}

resource "google_compute_instance" "workload" {
  name         = "${format("%s","${var.name}-${var.instance_type}-workload")}"
  machine_type = var.workload_defaults.instance_type
  zone         = var.zones[local.workload_zone_index]
  tags         = ["ssh", "http"]

  service_account {
    email  = var.service_account                                
    scopes = ["cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = var.workload_defaults.image
    }
  }

  labels = merge(var.project_tags, var.instance_tags)

  network_interface {
    subnetwork = var.subnetId

    access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = <<-CLOUD_INIT
#!/bin/bash

if ! type cloud-init > /dev/null 2>&1 ; then
  echo "Ran - `date`" >> /root/startup
  sleep 30
  apt-get install -y cloud-init

  if [ $? == 0 ]; then
    echo "Ran - Success - `date`" >> /root/startup
    systemctl enable cloud-init
  else
    echo "Ran - Fail - `date`" >> /root/startup
  fi

  reboot
fi

CLOUD_INIT

  metadata = {
    ssh-keys = "${var.ssh_key_owner}:${file(var.public_key_name)}"
    user-data = "${data.template_file.workload.rendered}"
  }
}

resource "terraform_data" "cluster" {
  depends_on = [
    google_compute_instance.node1,
    google_compute_instance.node2,
    google_compute_instance.node3,
    google_compute_instance.proxy,
    google_compute_instance.workload
  ]

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.node1.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'connected to node1!'", 
      "echo 'Waiting for user data script to finish'",  
      "cloud-init status --wait > /dev/null",
      "mkdir certs"
    ]  
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.node2.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'connected to node2!'", 
      "echo 'Waiting for user data script to finish'",  
      "cloud-init status --wait > /dev/null",
      "mkdir certs" 
    ]  
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.node3.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'connected to node3!'", 
      "echo 'Waiting for user data script to finish'",  
      "cloud-init status --wait > /dev/null",
      "mkdir certs"
    ]  
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.proxy.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'connected to proxy!'", 
      "echo 'Waiting for user data script to finish'",  
      "cloud-init status --wait > /dev/null",
      "mkdir certs"
    ]
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.workload.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.workload.vars.vm_user
      private_key = file(var.public_key_name)
   }

    inline = [
      "echo 'connected to workload!'",
      "echo 'Waiting for user data script to finish'",
      "cloud-init status --wait > /dev/null",
      "mkdir certs"
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
    echo 'creating certificates for node1 at ${google_compute_instance.node1.network_interface.0.access_config.0.nat_ip}'
    cockroach cert create-node ${google_compute_instance.node1.network_interface.0.access_config.0.nat_ip} ${google_compute_instance.node1.network_interface.0.network_ip} localhost 127.0.0.1 ${google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip} ${google_compute_instance.proxy.network_interface.0.network_ip} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${data.template_file.node.vars.vm_user}@${google_compute_instance.node1.network_interface.0.access_config.0.nat_ip}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${google_compute_instance.node1.network_interface.0.network_ip} --join=${google_compute_instance.node1.network_interface.0.network_ip},${google_compute_instance.node2.network_interface.0.network_ip},${google_compute_instance.node3.network_interface.0.network_ip} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
    TimeoutStopSec=300
    Restart=always
    RestartSec=10
    StandardOutput=syslog
    StandardError=syslog
    SyslogIdentifier=cockroach
    User=cockroach
    [Install]
    WantedBy=default.target
    EOF
    
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${data.template_file.node.vars.vm_user}@${google_compute_instance.node1.network_interface.0.access_config.0.nat_ip}:/home/${data.template_file.node.vars.vm_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
    echo 'creating certificates for node2 at ${google_compute_instance.node2.network_interface.0.access_config.0.nat_ip}'
    cockroach cert create-node ${google_compute_instance.node2.network_interface.0.access_config.0.nat_ip} ${google_compute_instance.node2.network_interface.0.network_ip} localhost 127.0.0.1 ${google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip} ${google_compute_instance.proxy.network_interface.0.network_ip} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${data.template_file.node.vars.vm_user}@${google_compute_instance.node2.network_interface.0.access_config.0.nat_ip}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${google_compute_instance.node2.network_interface.0.network_ip} --join=${google_compute_instance.node1.network_interface.0.network_ip},${google_compute_instance.node2.network_interface.0.network_ip},${google_compute_instance.node3.network_interface.0.network_ip} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
    TimeoutStopSec=300
    Restart=always
    RestartSec=10
    StandardOutput=syslog
    StandardError=syslog
    SyslogIdentifier=cockroach
    User=cockroach
    [Install]
    WantedBy=default.target
    EOF
    
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${data.template_file.node.vars.vm_user}@${google_compute_instance.node2.network_interface.0.access_config.0.nat_ip}:/home/${data.template_file.node.vars.vm_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
    echo 'creating certificates for node3 at ${google_compute_instance.node3.network_interface.0.access_config.0.nat_ip}'
    cockroach cert create-node ${google_compute_instance.node3.network_interface.0.access_config.0.nat_ip} ${google_compute_instance.node3.network_interface.0.network_ip} localhost 127.0.0.1 ${google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip} ${google_compute_instance.proxy.network_interface.0.network_ip} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${data.template_file.node.vars.vm_user}@${google_compute_instance.node3.network_interface.0.access_config.0.nat_ip}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${google_compute_instance.node3.network_interface.0.network_ip} --join=${google_compute_instance.node1.network_interface.0.network_ip},${google_compute_instance.node2.network_interface.0.network_ip},${google_compute_instance.node3.network_interface.0.network_ip} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
    TimeoutStopSec=300
    Restart=always
    RestartSec=10
    StandardOutput=syslog
    StandardError=syslog
    SyslogIdentifier=cockroach
    User=cockroach
    [Install]
    WantedBy=default.target
    EOF
    
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${data.template_file.node.vars.vm_user}@${google_compute_instance.node3.network_interface.0.access_config.0.nat_ip}:/home/${data.template_file.node.vars.vm_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.node1.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'starting cockroach on node1!'",
      "sudo mv certs /var/lib/cockroach/",
      "sudo chown -R cockroach /var/lib/cockroach",
      "sudo cp cockroachdb.service /etc/systemd/system/.",
      "rm cockroachdb.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable cockroachdb",
      "sudo systemctl start cockroachdb"
    ]
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.node2.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'starting cockroach on node2!'",
      "sudo mv certs /var/lib/cockroach/",
      "sudo chown -R cockroach /var/lib/cockroach",
      "sudo cp cockroachdb.service /etc/systemd/system/.",
      "rm cockroachdb.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable cockroachdb",
      "sudo systemctl start cockroachdb"
    ]
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.node3.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'starting cockroach on node3!'",
      "sudo mv certs /var/lib/cockroach/",
      "sudo chown -R cockroach /var/lib/cockroach",
      "sudo cp cockroachdb.service /etc/systemd/system/.",
      "rm cockroachdb.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable cockroachdb",
      "sudo systemctl start cockroachdb"
    ]
  }

  provisioner "local-exec" {
    environment = {
      USERNAME = data.template_file.node.vars.vm_user
      PROXY    = google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip
    }

    command = <<-EOT
    echo 'creating certificates for proxy server at ${google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip}'
    cockroach cert create-client root --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/client.root.crt /crdb/certs/client.root.key ${data.template_file.node.vars.vm_user}@${google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/client.root.crt /crdb/certs/client.root.key
    EOT
  }

  provisioner "remote-exec" {
    connection {
      host        = google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'initializing cluster from proxy server!'",
      "sleep 30",
      "cockroach init --certs-dir=certs --host=${google_compute_instance.node1.network_interface.0.network_ip}",
      "sleep 30",
      "sudo mv certs /var/lib/postgresql/",
      "sudo chown -R postgres:postgres /var/lib/postgresql",
      "sudo cockroach gen haproxy --certs-dir=/var/lib/postgresql/certs --host=${google_compute_instance.node1.network_interface.0.network_ip} --port=26257",
      "sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak",
      "sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg",
      "sudo systemctl reload haproxy",
      "echo export INTERNAL_ADDRESS=$(curl -s --request GET --header \"Metadata-Flavor: Google\" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip) | sudo tee -a /etc/profile.d/database.sh"
    ]
  }
}
