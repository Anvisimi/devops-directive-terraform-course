# ------------------------------------------------------------------------------
# Infrastructure: provider settings, data lookups, and AWS resources.
# This file defines what actually gets created in the cloud.
# ------------------------------------------------------------------------------

# Configures the AWS provider. All resources below use this region unless overridden.
provider "aws" {
  region = "ap-southeast-1" # Singapore
}

# At plan/apply time, asks AWS for an AMI matching the filters (does not create an AMI).
# Result is referenced as data.aws_ami.ubuntu — avoids hardcoded AMI IDs and works in any region.
data "aws_ami" "ubuntu" {
  most_recent = true # If multiple AMIs match, use the newest (latest Ubuntu 24.04 build).

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] # Ubuntu 24.04 Noble, HVM, gp3.
  }

  owners = ["099720109477"] # Canonical (official Ubuntu); avoids untrusted AMIs.
}

# Creates and manages one EC2 instance; address in this config: aws_instance.app_server.
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id # Use the AMI looked up above (region-aware, stays current).
  instance_type = "t2.micro"             # Small instance (often free tier).

  tags = {
    Name = "learn-terraform" # Name tag for easy identification in the AWS console.
  }
}
