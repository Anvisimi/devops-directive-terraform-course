output "instance_1_ip_addr" {
  value = aws_instance.instance_1.public_ip
}

output "instance_2_ip_addr" {
  value = aws_instance.instance_2.public_ip
}

output "db_instance_addr" {
  value = aws_db_instance.db_instance.address
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer - use this to access the app"
  value       = aws_lb.load_balancer.dns_name
}

# if we add data for Ec2 resources
# output "instance_ip_addrs" {
#   description = "Public IPs of all EC2 instances"
#   value       = aws_instance.app[*].public_ip
# }
#
# output "db_instance_addr" {
#   description = "Hostname of the RDS database instance"
#   value       = aws_db_instance.db_instance.address
# }
#

