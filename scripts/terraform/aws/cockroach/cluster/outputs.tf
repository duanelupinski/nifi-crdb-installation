output "instance_id" {
  value = aws_instance.proxy.id
}

output "private_dns" {
  description = "The private DNS name assigned to the cluster. Can only be used inside the Amazon EC2, and only available if you've enabled DNS hostnames for your VPC"
  value = aws_instance.proxy.private_dns
}

output "public_dns" {
  description = "The public DNS name assigned to the cluster. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value = aws_instance.proxy.public_dns
}

output "public_ip" {
  description = "The public IP address assigned to the cluster, if applicable. NOTE: If you are using an aws_eip with your cluster, you should refer to the EIP's address directly and not use `public_ip` as this field will change after the EIP is attached"
  value = aws_instance.proxy.public_ip
}

output "private_ip" {
  description = "The private IP address assigned to the cluster"
  value = aws_instance.proxy.private_ip
}

output "node1_dns" {
  description = "The public DNS name assigned to the node1 instance. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value = aws_instance.node1.public_dns
}

output "node1_ip" {
  description = "The public IP address assigned to the node1 instance, if applicable. NOTE: If you are using an aws_eip with your node1 instance, you should refer to the EIP's address directly and not use `public_ip` as this field will change after the EIP is attached"
  value = aws_instance.node1.public_ip
}

output "node2_dns" {
  description = "The public DNS name assigned to the node2 instance. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value = aws_instance.node2.public_dns
}

output "node2_ip" {
  description = "The public IP address assigned to the node2 instance, if applicable. NOTE: If you are using an aws_eip with your node2 instance, you should refer to the EIP's address directly and not use `public_ip` as this field will change after the EIP is attached"
  value = aws_instance.node2.public_ip
}

output "node3_dns" {
  description = "The public DNS name assigned to the node3 instance. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value = aws_instance.node3.public_dns
}

output "node3_ip" {
  description = "The public IP address assigned to the node3 instance, if applicable. NOTE: If you are using an aws_eip with your node3 instance, you should refer to the EIP's address directly and not use `public_ip` as this field will change after the EIP is attached"
  value = aws_instance.node3.public_ip
}

output "proxy_dns" {
  description = "The public DNS name assigned to the proxy instance. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value = aws_instance.proxy.public_dns
}

output "proxy_ip" {
  description = "The public IP address assigned to the proxy instance, if applicable. NOTE: If you are using an aws_eip with your proxy instance, you should refer to the EIP's address directly and not use `public_ip` as this field will change after the EIP is attached"
  value = aws_instance.proxy.public_ip
}

output "workload_dns" {
  description = "The public DNS name assigned to the workload instance. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value = aws_instance.workload.public_dns
}

output "workload_ip" {
  description = "The public IP address assigned to the workload instance, if applicable. NOTE: If you are using an aws_eip with your workload instance, you should refer to the EIP's address directly and not use `public_ip` as this field will change after the EIP is attached"
  value = aws_instance.workload.public_ip
}
