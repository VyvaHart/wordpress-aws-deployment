# IAM Role for EC2
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2-ssm-role-wordpress"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "wordpress-ec2-ssm-role"
  }
}

# attach the AWS Managed Policy
resource "aws_iam_role_policy_attachment" "ssm_managed_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# attach the role to the EC2 instance
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ssm-profile-wordpress"
  role = aws_iam_role.ec2_ssm_role.name
}

# Networking

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "wordpress_vpc"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "wordpress_igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = var.public_subnet_azs[count.index]
  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(["${var.aws_region}b", "${var.aws_region}c"], count.index)
  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
  }
}

# For all Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "wordpress-public-rt"
  }
}

# Public Route Table Associations
resource "aws_route_table_association" "public_assoc" {
  count          = length(var.public_subnet_cidrs) # Associate each public subnet
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway & Private Routes
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "wordpress-nat-eip" }
}

resource "aws_nat_gateway" "gw_nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "wordpress-nat-gw" }
  depends_on    = [aws_internet_gateway.gw]
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gw_nat.id
  }
  tags = { Name = "wordpress-private-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --- Security Groups ---

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "wordpress_alb_sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80 # HTTP
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wordpress-alb-sg" }
}

# Security Group for EC2
resource "aws_security_group" "ec2_sg" {
  name        = "wordpress_ec2_sg"
  description = "Allow HTTP from ALB and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH from anywhere (unsecure!)"
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
    description     = "Allow HTTP only from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all outbound traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-ec2-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Allow MySQL access only from EC2 SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id] # Allow traffic only from EC@ in ec2_sg
    description     = "Allow MySQL traffic from EC2 instance"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-rds-sg"
  }
}

resource "aws_security_group" "redis_sg" {
  name        = "wordpress-redis-sg"
  description = "Allow Redis access only from EC2 SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description     = "Allow Redis traffic from EC2 instance"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress-redis-sg"
  }
}

# --- ALB Resources ---
resource "aws_lb" "main" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  # associate ALB with public subnets in different AZs
  subnets = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = { Name = "wordpress-alb" }
}

resource "aws_lb_target_group" "wordpress_http" {
  name        = "wordpress-http-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = { Name = "wordpress-http-tg" }
}

# Listener for HTTP traffic on port 80
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_http.arn
  }
}

# Register the EC2 instance to the Target Group
resource "aws_lb_target_group_attachment" "web_server" {
  target_group_arn = aws_lb_target_group.wordpress_http.arn
  target_id        = aws_instance.web-server.id
  port             = 80
}

# RDS (MySQL)

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name = "Wordpress RDS Subnet Group"
  }
}

resource "aws_db_instance" "mysql_rds" {
  allocated_storage      = 15
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  storage_type           = "gp2"

  tags = {
    Name = "wordpress-mysql-rds"
  }
}

# ElastiCache (Redis)

resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "wordpress-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name = "WordPress Redis Subnet Group"
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "wordpress-redis-cluster"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.redis_sg.id]

  tags = {
    Name = "wordpress-redis-cache"
  }
}


# EC2 instance

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web-server" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.ec2_instance_type
  key_name                    = var.ec2_key_name
  subnet_id                   = aws_subnet.private[0].id # deploy in private subnet
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  # Basic dependencies installation
  user_data = <<-EOF
            #!/bin/bash
            yum update -y
            # Install SSM Agent (should be installed, but just in case..)
            yum install -y https://s3.${var.aws_region}.amazonaws.com/amazon-ssm-${var.aws_region}/latest/linux_amd64/amazon-ssm-agent.rpm
            systemctl enable amazon-ssm-agent
            systemctl start amazon-ssm-agent
            amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
            yum install -y httpd php-mysqlnd php-redis
            systemctl start httpd
            systemctl enable httpd
            # install WP-CLI prerequisites
            yum install -y wget
            # install WP-CLI
            wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
            chmod +x wp-cli.phar
            mv wp-cli.phar /usr/local/bin/wp
            # create web root
            mkdir -p /var/www/html
            chown -R apache:apache /var/www/html
            EOF

  tags = {
    Name = "wordpress-web-server"
  }
  depends_on = [aws_nat_gateway.gw_nat, aws_iam_instance_profile.ec2_profile]
}