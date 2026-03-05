output "cluster_name" {
  description = "EKS cluster name — used in aws eks update-kubeconfig"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API endpoint — where kubectl sends commands"
  value       = aws_eks_cluster.main.endpoint
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer - use this to access the app"
  value       = aws_lb.load_balancer.dns_name
}

# same as before
output "db_instance_addr" {
  description = "RDS endpoint"
  value       = aws_db_instance.db_instance.address
}

