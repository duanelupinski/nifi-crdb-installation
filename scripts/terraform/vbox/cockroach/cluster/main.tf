### VBOX ###

resource "virtualbox_vm" "node1" {
  name            = "${var.cluster_name}-node1"
  image           = var.cockroach_image
  cpus            = var.cockroach_cpus
  memory          = var.cockroach_memory

  network_adapter {
    type           = var.network_adapter_settings.type
    host_interface = var.network_adapter_settings.host_interface
  }
}

resource "virtualbox_vm" "node2" {
  name            = "${var.cluster_name}-node2"
  image           = var.cockroach_image
  cpus            = var.cockroach_cpus
  memory          = var.cockroach_memory

  network_adapter {
    type           = var.network_adapter_settings.type
    host_interface = var.network_adapter_settings.host_interface
  }
}

resource "virtualbox_vm" "node3" {
  name            = "${var.cluster_name}-node3"
  image           = var.cockroach_image
  cpus            = var.cockroach_cpus
  memory          = var.cockroach_memory

  network_adapter {
    type           = var.network_adapter_settings.type
    host_interface = var.network_adapter_settings.host_interface
  }
}

resource "virtualbox_vm" "proxy" {
  name            = "${var.cluster_name}-proxy"
  image           = var.proxy_image
  cpus            = var.proxy_cpus
  memory          = var.proxy_memory

  network_adapter {
    type           = var.network_adapter_settings.type
    host_interface = var.network_adapter_settings.host_interface
  }
}

resource "virtualbox_vm" "workload" {
  name            = "${var.cluster_name}-workload"
  image           = var.workload_image
  cpus            = var.workload_cpus
  memory          = var.workload_memory

  network_adapter {
    type           = var.network_adapter_settings.type
    host_interface = var.network_adapter_settings.host_interface
  }
}

resource "terraform_data" "cluster" {
  provisioner "remote-exec" {
    connection {
      host        = virtualbox_vm.node1.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
      host        = virtualbox_vm.node2.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
      host        = virtualbox_vm.node3.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
      host        = virtualbox_vm.proxy.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
      host        = virtualbox_vm.workload.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
    echo 'creating certificates for node1 at ${virtualbox_vm.node1.network_adapter.0.ipv4_address}'
    cockroach cert create-node ${virtualbox_vm.node1.network_adapter.0.ipv4_address} localhost 127.0.0.1 ${virtualbox_vm.proxy.network_adapter.0.ipv4_address} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${var.cluster_user}@${virtualbox_vm.node1.network_adapter.0.ipv4_address}:/home/${var.cluster_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${virtualbox_vm.node1.network_adapter.0.ipv4_address} --join=${virtualbox_vm.node1.network_adapter.0.ipv4_address},${virtualbox_vm.node2.network_adapter.0.ipv4_address},${virtualbox_vm.node3.network_adapter.0.ipv4_address} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
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
    
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${var.cluster_user}@${virtualbox_vm.node1.network_adapter.0.ipv4_address}:/home/${var.cluster_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
    echo 'creating certificates for node2 at ${virtualbox_vm.node2.network_adapter.0.ipv4_address}'
    cockroach cert create-node ${virtualbox_vm.node2.network_adapter.0.ipv4_address} localhost 127.0.0.1 ${virtualbox_vm.proxy.network_adapter.0.ipv4_address} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${var.cluster_user}@${virtualbox_vm.node2.network_adapter.0.ipv4_address}:/home/${var.cluster_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${virtualbox_vm.node2.network_adapter.0.ipv4_address} --join=${virtualbox_vm.node1.network_adapter.0.ipv4_address},${virtualbox_vm.node2.network_adapter.0.ipv4_address},${virtualbox_vm.node3.network_adapter.0.ipv4_address} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
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
    
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${var.cluster_user}@${virtualbox_vm.node2.network_adapter.0.ipv4_address}:/home/${var.cluster_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
    echo 'creating certificates for node3 at ${virtualbox_vm.node3.network_adapter.0.ipv4_address}'
    cockroach cert create-node ${virtualbox_vm.node3.network_adapter.0.ipv4_address} localhost 127.0.0.1 ${virtualbox_vm.proxy.network_adapter.0.ipv4_address} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${var.cluster_user}@${virtualbox_vm.node3.network_adapter.0.ipv4_address}:/home/${var.cluster_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${virtualbox_vm.node3.network_adapter.0.ipv4_address} --join=${virtualbox_vm.node1.network_adapter.0.ipv4_address},${virtualbox_vm.node2.network_adapter.0.ipv4_address},${virtualbox_vm.node3.network_adapter.0.ipv4_address} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
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
    
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${var.cluster_user}@${virtualbox_vm.node3.network_adapter.0.ipv4_address}:/home/${var.cluster_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "remote-exec" {
    connection {
      host        = virtualbox_vm.node1.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
      host        = virtualbox_vm.node2.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
      host        = virtualbox_vm.node3.network_adapter.0.ipv4_address
      user        = var.cluster_user
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
      USERNAME = var.cluster_user
      PROXY    = virtualbox_vm.proxy.network_adapter.0.ipv4_address
    }

    command = <<-EOT
    echo 'creating certificates for proxy server at ${virtualbox_vm.proxy.network_adapter.0.ipv4_address}'
    cockroach cert create-client root --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/client.root.crt /crdb/certs/client.root.key ${var.cluster_user}@${virtualbox_vm.proxy.network_adapter.0.ipv4_address}:/home/${var.cluster_user}/certs
    rm /crdb/certs/client.root.crt /crdb/certs/client.root.key
    EOT
  }

  provisioner "remote-exec" {
    connection {
      host        = virtualbox_vm.proxy.network_adapter.0.ipv4_address
      user        = var.cluster_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'initializing cluster from proxy server!'",
      "sleep 30",
      "cockroach init --certs-dir=certs --host=${virtualbox_vm.node1.network_adapter.0.ipv4_address}",
      "sleep 30",
      "sudo mv certs /var/lib/postgresql/",
      "sudo chown -R postgres:postgres /var/lib/postgresql",
      "sudo cockroach gen haproxy --certs-dir=/var/lib/postgresql/certs --host=${virtualbox_vm.node1.network_adapter.0.ipv4_address} --port=26257",
      "sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak",
      "sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg",
      "sudo systemctl reload haproxy"
    ]
  }
}
