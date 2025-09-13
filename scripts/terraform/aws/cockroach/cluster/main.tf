terraform {
  required_version = ">= 0.14.9"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 4.59.0"
    }
  }
}

data "template_file" "node" {
  template = file(var.cloud_init_node)

  vars = merge(
    var.cloud_init_vars,
	{
	  architecture: var.instance_architecture
	}
  )
}

data "template_file" "proxy" {
  template = file(var.cloud_init_proxy)

  vars = merge(
    var.cloud_init_vars,
	{
	  architecture: var.instance_architecture
	}
  )
}

data "template_file" "workload" {
  template = file(var.cloud_init_workload)
  vars = var.cloud_init_vars
}

### EC2 ###

resource "aws_instance" "node1" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    var.security_group_id,
  ]
  associate_public_ip_address = true
  key_name  = var.public_key_name
  user_data = base64gzip(data.template_file.node.rendered)

  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_instance" "node2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    var.security_group_id,
  ]
  associate_public_ip_address = true
  key_name  = var.public_key_name
  user_data = base64gzip(data.template_file.node.rendered)

  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_instance" "node3" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    var.security_group_id,
  ]
  associate_public_ip_address = true
  key_name  = var.public_key_name
  user_data = base64gzip(data.template_file.node.rendered)

  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_instance" "proxy" {
  ami           = var.proxy_defaults.ami_id
  instance_type = var.proxy_defaults.instance_type
  vpc_security_group_ids = [
    var.security_group_id,
  ]
  associate_public_ip_address = true
  key_name  = var.public_key_name
  user_data = base64gzip(data.template_file.proxy.rendered)

  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_instance" "workload" {
  ami           = var.workload_defaults.ami_id
  instance_type = var.workload_defaults.instance_type
  vpc_security_group_ids = [
    var.security_group_id,
  ]
  associate_public_ip_address = true
  key_name  = var.public_key_name
  user_data = base64gzip(data.template_file.workload.rendered)

  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_ebs_volume" "ebs1" {
  availability_zone = aws_instance.node1.availability_zone
  size = var.disk_size
  type = "io1"
  iops = var.disk_iops
  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_volume_attachment" "volume1" {
  device_name = "/dev/sdp"
  volume_id = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.node1.id
}

resource "aws_ebs_volume" "ebs2" {
  availability_zone = aws_instance.node2.availability_zone
  size = var.disk_size
  type = "io1"
  iops = var.disk_iops
  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_volume_attachment" "volume2" {
  device_name = "/dev/sdp"
  volume_id = aws_ebs_volume.ebs2.id
  instance_id = aws_instance.node2.id
}

resource "aws_ebs_volume" "ebs3" {
  availability_zone = aws_instance.node3.availability_zone
  size = var.disk_size
  type = "io1"
  iops = var.disk_iops
  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_volume_attachment" "volume3" {
  device_name = "/dev/sdp"
  volume_id = aws_ebs_volume.ebs3.id
  instance_id = aws_instance.node3.id
}

resource "aws_ebs_volume" "ebs4" {
  availability_zone = aws_instance.proxy.availability_zone
  size = 50
  type = "io1"
  iops = 1000
  tags = merge(var.project_tags, var.instance_tags)
}

resource "aws_volume_attachment" "volume4" {
  device_name = "/dev/sdp"
  volume_id = aws_ebs_volume.ebs4.id
  instance_id = aws_instance.proxy.id
}

resource "terraform_data" "cluster" {
  provisioner "remote-exec" {
    connection {
      host        = aws_instance.node1.public_dns
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
      host        = aws_instance.node2.public_dns
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
      host        = aws_instance.node3.public_dns
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
      host        = aws_instance.proxy.public_dns
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
      host        = aws_instance.workload.public_dns
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
    echo 'creating certificates for node1 at ${aws_instance.node1.public_dns}'
    cockroach cert create-node ${aws_instance.node1.public_dns} localhost 127.0.0.1 ${aws_instance.proxy.public_dns} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${data.template_file.node.vars.vm_user}@${aws_instance.node1.public_dns}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${aws_instance.node1.public_dns} --join=${aws_instance.node1.public_dns},${aws_instance.node2.public_dns},${aws_instance.node3.public_dns} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
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
    
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${data.template_file.node.vars.vm_user}@${aws_instance.node1.public_dns}:/home/${data.template_file.node.vars.vm_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
    echo 'creating certificates for node2 at ${aws_instance.node2.public_dns}'
    cockroach cert create-node ${aws_instance.node2.public_dns} localhost 127.0.0.1 ${aws_instance.proxy.public_dns} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${data.template_file.node.vars.vm_user}@${aws_instance.node2.public_dns}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${aws_instance.node2.public_dns} --join=${aws_instance.node1.public_dns},${aws_instance.node2.public_dns},${aws_instance.node3.public_dns} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
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
    
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${data.template_file.node.vars.vm_user}@${aws_instance.node2.public_dns}:/home/${data.template_file.node.vars.vm_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "local-exec" {
    command = <<-EOT
    echo 'creating certificates for node3 at ${aws_instance.node3.public_dns}'
    cockroach cert create-node ${aws_instance.node3.public_dns} localhost 127.0.0.1 ${aws_instance.proxy.public_dns} --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/node.crt /crdb/certs/node.key ${data.template_file.node.vars.vm_user}@${aws_instance.node3.public_dns}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/node.crt /crdb/certs/node.key
    
    cat > /crdb/cockroachdb.service<< EOF
    [Unit]
    Description=Cockroach Database cluster node
    Requires=network.target
    [Service]
    Type=notify
    WorkingDirectory=/var/lib/cockroach
    ExecStart=/usr/local/bin/cockroach start --certs-dir=certs --advertise-addr=${aws_instance.node3.public_dns} --join=${aws_instance.node1.public_dns},${aws_instance.node2.public_dns},${aws_instance.node3.public_dns} --cache=.25 --max-sql-memory=.25 --store=/mnt/cockroach-data --http-port=8080
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
    
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/cockroachdb.service ${data.template_file.node.vars.vm_user}@${aws_instance.node3.public_dns}:/home/${data.template_file.node.vars.vm_user}/
    rm /crdb/cockroachdb.service
    EOT
  }

  provisioner "remote-exec" {
    connection {
      host        = aws_instance.node1.public_dns
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
      host        = aws_instance.node2.public_dns
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
      host        = aws_instance.node3.public_dns
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
      PROXY    = aws_instance.proxy.public_dns
    }

    command = <<-EOT
    echo 'creating certificates for proxy server at ${aws_instance.proxy.public_dns}'
    cockroach cert create-client root --certs-dir=/crdb/certs --ca-key=/crdb/my-safe-directory/ca.key
    scp -i ${var.public_key_name} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /crdb/certs/ca.crt /crdb/certs/client.root.crt /crdb/certs/client.root.key ${data.template_file.node.vars.vm_user}@${aws_instance.proxy.public_dns}:/home/${data.template_file.node.vars.vm_user}/certs
    rm /crdb/certs/client.root.crt /crdb/certs/client.root.key
    EOT
  }

  provisioner "remote-exec" {
    connection {
      host        = aws_instance.proxy.public_dns
      user        = data.template_file.node.vars.vm_user
      private_key = file(var.public_key_name)
    }

    inline = [
      "echo 'initializing cluster from proxy server!'",
      "sleep 30",
      "cockroach init --certs-dir=certs --host=${aws_instance.node1.public_dns}",
      "sleep 30",
      "sudo mv certs /var/lib/postgresql/",
      "sudo chown -R postgres:postgres /var/lib/postgresql",
      "sudo cockroach gen haproxy --certs-dir=/var/lib/postgresql/certs --host=${aws_instance.node1.public_dns} --port=26257",
      "sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak",
      "sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg",
      "sudo systemctl reload haproxy"
    ]
  }
}
