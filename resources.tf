
## create volume ##
resource "aws_ebs_volume" "codegenitor_IAC" {
  availability_zone = var.availability_zone
  size              = var.volume_size
  tags = {
    Name = "k8s_volume"
  }
}

## create security group ##
resource "aws_security_group" "codegenitor_IAC" {
  name        = "codegenitor_web_security"
  description = "Allow inbound traffic on port 80, 443, 22"
  vpc_id      = var.VPC_ID


  tags = {
    Name = "web_security"
  }

  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow NodePort from anywhere"
    from_port   = 31438
    to_port     = 31438
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


## Create the ec2 web server and install k8s on it ##
resource "aws_instance" "codegenitor_web_server" {
  depends_on                  = [aws_security_group.codegenitor_IAC]
  ami                         = var.AMI
  instance_type               = var.instance_type
  key_name                    = var.codegenitor_keypair
  vpc_security_group_ids      = [aws_security_group.codegenitor_IAC.id]
  user_data                   = file("user_data.sh")
  associate_public_ip_address = true
  tags = {
    Name = "codegenito_web_server"
  }
}

## Attach the volume to the ec2 instance ##
resource "aws_volume_attachment" "codegenitor_IAC" {
  depends_on   = [aws_instance.codegenitor_web_server]
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.codegenitor_IAC.id
  instance_id  = aws_instance.codegenitor_web_server.id
  force_detach = true
}