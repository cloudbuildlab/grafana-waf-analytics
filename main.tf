############################################
# Random Suffix for Resource Names
############################################

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

############################################
# Data sources
############################################

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_s3_bucket" "waf_logs" {
  bucket = var.waf_logs_bucket_name
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

############################################
# VPC Configuration
############################################

module "vpc" {
  source = "cloudbuildlab/vpc/aws"

  vpc_name           = local.base_name
  vpc_cidr           = local.vpc_cidr
  availability_zones = local.azs

  public_subnet_cidrs  = local.public_subnets
  private_subnet_cidrs = local.private_subnets

  # Enable Internet Gateway & NAT Gateway
  create_igw       = true
  nat_gateway_type = "single"

  tags = local.tags
}

resource "aws_security_group" "ec2" {
  name_prefix = "${local.base_name}-ec2-"
  vpc_id      = module.vpc.vpc_id

  # No inbound rules - SSM only access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.base_name}-ec2-sg"
  })
}

############################################
# S3 bucket for Grafana configuration files
############################################

module "s3_bucket" {
  source = "tfstack/s3/aws"

  # General Configuration
  bucket_name   = "${local.name}-configs"
  bucket_suffix = local.suffix
  force_destroy = true
  tags          = local.tags

  # Ownership and Access Controls
  allowed_principals = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  # Security & Encryption
  sse_algorithm = "AES256"

  # Versioning
  enable_versioning = true
}

# Upload regular configuration files
resource "aws_s3_object" "config_files" {
  for_each = local.config_files

  bucket = module.s3_bucket.bucket_id
  key    = each.key
  source = each.value
  etag   = filemd5(each.value)
}

# Upload template-based configuration files
resource "aws_s3_object" "config_sync_service" {
  bucket = module.s3_bucket.bucket_id
  key    = "config-sync/config-sync.service"
  content = templatefile("${path.module}/grafana-configs/config-sync/config-sync.service", {
    config_bucket = module.s3_bucket.bucket_name
    region        = data.aws_region.current.region
  })
  etag = md5(templatefile("${path.module}/grafana-configs/config-sync/config-sync.service", {
    config_bucket = module.s3_bucket.bucket_name
    region        = data.aws_region.current.region
  }))
}

resource "aws_s3_object" "sync_waf_logs_script" {
  bucket = module.s3_bucket.bucket_id
  key    = "waf-sync/sync-waf-logs.sh"
  content = templatefile("${path.module}/grafana-configs/waf-sync/sync-waf-logs.sh", {
    config_bucket = data.aws_s3_bucket.waf_logs.bucket
    region        = data.aws_region.current.region
  })
  etag = md5(templatefile("${path.module}/grafana-configs/waf-sync/sync-waf-logs.sh", {
    config_bucket = data.aws_s3_bucket.waf_logs.bucket
    region        = data.aws_region.current.region
  }))
}

############################################
# IAM Configuration
############################################

resource "aws_iam_role" "ec2_role" {
  name = "${local.base_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.base_name}-ec2-role"
  })
}

resource "aws_iam_policy" "s3_access" {
  name        = "${local.base_name}-s3-access"
  description = "Policy for accessing WAF logs and Grafana configs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3AccessPolicy"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          data.aws_s3_bucket.waf_logs.arn,
          "${data.aws_s3_bucket.waf_logs.arn}/*",
          module.s3_bucket.bucket_arn,
          "${module.s3_bucket.bucket_arn}/*"
        ]
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.base_name}-s3-access"
  })
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.base_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = merge(local.tags, {
    Name = "${local.base_name}-ec2-profile"
  })
}

# Separate EBS volume for data persistence
resource "aws_ebs_volume" "grafana_data" {
  availability_zone = local.azs[0]
  size              = 100
  type              = "gp3"
  encrypted         = true

  tags = merge(local.tags, {
    Name = "${local.base_name}-grafana-data"
  })
}

# EC2 Instance
resource "aws_instance" "grafana" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "m5.large"
  subnet_id                   = module.vpc.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  user_data_replace_on_change = true
  user_data_base64 = base64encode(templatefile("${path.module}/user_data.sh", {
    config_bucket  = module.s3_bucket.bucket_name
    region         = data.aws_region.current.region
    data_volume_id = aws_ebs_volume.grafana_data.id
  }))

  tags = merge(local.tags, {
    Name = "${local.base_name}-grafana"
  })

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_s3_object.config_files,
    aws_ebs_volume.grafana_data
  ]
}

# Attach the data volume to the instance
resource "aws_volume_attachment" "grafana_data_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.grafana_data.id
  instance_id = aws_instance.grafana.id

  # Force detachment before attachment
  force_detach = true
}
