resource "aws_security_group" "nodejs-app-sg" {
  name        = "nodejs-app-sg"
  description = "Allow TLS inbound traffic and all outbound traffic"


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Node.js App"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}


resource "aws_instance" "nodejs-deployment" {
  ami           = "ami-0c7632fb77f35db43"
  instance_type = "t2.micro"
  key_name = "devops-key"
  vpc_security_group_ids = [aws_security_group.nodejs-app-sg.id]


  tags = {
    Name = "nodejs-app-deploy"
  }

provisioner "local-exec" {
    command = <<EOT
      # Wait a few seconds for SSH daemon to start
      echo "Waiting for EC2 instance to launch............"
      sleep 30

      # Automatically generate/update the inventory file 
      echo "[webservers]" > inventory.ini
      echo "${self.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=devops-key.pem" >> inventory.ini

      # Run the playbook
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini playbook.yml
    EOT
  }
}
