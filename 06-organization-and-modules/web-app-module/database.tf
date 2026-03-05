resource "aws_db_instance" "db_instance" {
  allocated_storage   = 20
  storage_type        = "gp3" #standard is legacy , gp2 older standard
  engine              = "postgres"
  engine_version      = "16"
  instance_class      = "db.t3.micro"
  db_name                = var.db_name
  username            = var.db_user
  password            = var.db_pass
  skip_final_snapshot = true #false for production
  vpc_security_group_ids = [aws_security_group.rds.id] # only EC2 can reach DB
  deletion_protection = true            # prevents accidental terraform destroy
  storage_encrypted   = true            # encrypt data at rest
  multi_az                = true
  backup_retention_period = 7

  tags = {
    Name        = "${var.app_name}-${var.environment_name}-db"
    Environment = var.environment_name
    ManagedBy   = "terraform"
  }
}

# "I'd add encryption at rest with storage_encrypted, prevent accidental deletion with deletion_protection, enable multi-AZ for high availability, set a 7-day backup retention period, restrict access with a dedicated security group, and tag everything for cost tracking and resource management."
# Note
# skip_final_snapshot     = false   # if protection ever removed, take backup first
# final_snapshot_identifier = "${var.app_name}-${var.environment_name}-final"