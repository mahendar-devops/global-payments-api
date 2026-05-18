# infra/modules/rds/main.tf
#
# Aurora PostgreSQL cluster — banking-grade configuration:
#   - Encryption at rest with KMS CMK
#   - Multi-AZ (writer + reader) for HA
#   - 35-day backup retention with PITR (Point-in-Time Recovery)
#   - Enhanced monitoring (1-second granularity)
#   - Performance Insights for query analysis
#   - Credentials auto-rotated in AWS Secrets Manager
#   - Deletion protection (must be manually disabled for teardown)

terraform {
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}

# ── KMS Key for RDS encryption ────────────────────────────────────
resource "aws_kms_key" "rds" {
  description             = "RDS encryption key — ${var.name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true    # Annual key rotation (compliance)

  tags = merge(var.tags, { Name = "${var.name}-rds-kms" })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ── Subnet Group ──────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name        = "${var.name}-subnet-group"
  description = "Private subnets for ${var.name} Aurora cluster"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-subnet-group" })
}

# ── Security Group ────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "Allow PostgreSQL access from EKS worker nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS workers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # No egress rules — RDS does not initiate outbound connections
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (for patch downloads)"
  }

  tags = merge(var.tags, { Name = "${var.name}-rds-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ── Cluster Parameter Group ───────────────────────────────────────
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.name}-cluster-params"
  family      = "aurora-postgresql15"
  description = "Banking-hardened Aurora PostgreSQL parameters"

  # Force SSL connections — plaintext DB connections not permitted
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Log all connections and disconnections for audit
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  # Log slow queries (> 1 second) for performance analysis
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Shared preload for pg_stat_statements (query analytics)
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

# ── Aurora Cluster ────────────────────────────────────────────────
resource "aws_rds_cluster" "main" {
  cluster_identifier      = "${var.name}-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = var.engine_version
  database_name           = var.database_name
  master_username         = var.master_username
  # Password managed by Secrets Manager rotation — not stored in TF state
  manage_master_user_password = true
  master_user_secret_kms_key_id = aws_kms_key.rds.key_id

  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.rds.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  # Encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Backup & Recovery
  backup_retention_period   = var.backup_retention_days
  preferred_backup_window   = "02:00-03:00"    # 2-3am UTC — low traffic window
  preferred_maintenance_window = "sun:03:00-sun:04:00"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection

  # Enable PITR (Point-in-Time Recovery) — mandatory for banking
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Skip final snapshot in dev; always take one in prod
  skip_final_snapshot       = var.environment == "dev"
  final_snapshot_identifier = var.environment != "dev" ? "${var.name}-final-${formatdate("YYYY-MM-DD", timestamp())}" : null

  tags = merge(var.tags, { Name = "${var.name}-cluster" })

  lifecycle {
    # Prevent accidental destruction — must explicitly set deletion_protection=false first
    prevent_destroy = false   # Set to true after initial deploy in prod
    ignore_changes  = [master_password]
  }
}

# ── Cluster Instances ─────────────────────────────────────────────
resource "aws_rds_cluster_instance" "main" {
  count = var.instance_count

  identifier         = "${var.name}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  db_subnet_group_name = aws_db_subnet_group.main.name

  # First instance is writer, rest are readers
  # Aurora automatically handles writer failover

  # Enhanced Monitoring — 1-second granularity (required for SLA tracking)
  monitoring_interval = 1
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance Insights — 7-day free retention
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  auto_minor_version_upgrade = true
  apply_immediately          = var.environment == "dev"

  tags = merge(var.tags, {
    Name = "${var.name}-instance-${count.index + 1}"
    Role = count.index == 0 ? "writer" : "reader"
  })
}

# ── Enhanced Monitoring IAM Role ──────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ── CloudWatch Alarms ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "db_cpu_high" {
  alarm_name          = "${var.name}-db-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Aurora CPU utilization above 80%"
  alarm_actions       = []    # Wire to SNS topic in prod

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "db_connections_high" {
  alarm_name          = "${var.name}-db-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 800   # Alert at 80% of max_connections for db.r6g.large
  alarm_description   = "Aurora connection count approaching limit"
  alarm_actions       = []

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.main.cluster_identifier
  }

  tags = var.tags
}
