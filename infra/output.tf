# Output the Elastic IP (static) of the K8s node
output "k8s_node_ip" {
  description = "Static Elastic IP address of the K8s node"
  value       = aws_eip.k8s_node_eip.public_ip
}

output "k8s_instance_id" {
  value = aws_instance.k8s_node.id
}
