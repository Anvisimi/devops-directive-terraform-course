resource "aws_instance" "instance_1" {
  ami             = var.ami
  instance_type   = var.instance_type
  vpc_security_group_ids = [aws_security_group.instances.id]  # ← .id (correct VPC way)
  user_data       = <<-EOF
              #!/bin/bash
              echo "Hello, World 1" > index.html
              python3 -m http.server 8080 &
              EOF
}

resource "aws_instance" "instance_2" {
  ami             = var.ami
  instance_type   = var.instance_type
  vpc_security_group_ids = [aws_security_group.instances.id]  # ← .id (correct VPC way)
  user_data       = <<-EOF
              #!/bin/bash
              echo "Hello, World 2" > index.html
              python3 -m http.server 8080 &
              EOF
}

#will uncomment and run
# data "aws_ami" "ubuntu" {
#   most_recent = true
#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
#   }
#   owners = ["099720109477"]
# }
#
# resource "aws_instance" "app" {
#   count = 2    # creates 2 instances: app[0] and app[1]
#
#   ami                    = data.aws_ami.ubuntu.id
#   instance_type          = var.instance_type
#   vpc_security_group_ids = [aws_security_group.instances.id]  # fixed attribute name
#
#   user_data = <<-EOF
#     #!/bin/bash
#     echo "Hello, World ${count.index + 1}" > index.html
#     python3 -m http.server 8080 &
#   EOF
#
#   tags = {
#     Name        = "${var.app_name}-${var.environment_name}-instance-${count.index + 1}"
#     Environment = var.environment_name
#     ManagedBy   = "terraform"
#   }
# }


# make this change by replacing instance in networking.tf

# resource "aws_lb_target_group_attachment" "app" {
#   count            = 2
#   target_group_arn = aws_lb_target_group.instances.arn
#   target_id        = aws_instance.app[count.index].id
#   port             = 8080
# }