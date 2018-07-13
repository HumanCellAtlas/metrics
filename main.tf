data "aws_caller_identity" "current" {}

provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

terraform {
  backend "s3" {
    key = "metrics/app.tfstate"
  }
}

data "aws_secretsmanager_secret" "domain_name" {
  name = "metrics/_/domain_name"
}

data "aws_secretsmanager_secret_version" "domain_name" {
  secret_id = "${data.aws_secretsmanager_secret.domain_name.id}"
  version_stage = "AWSCURRENT"
}

data "aws_secretsmanager_secret" "grafana_fqdn" {
  name = "metrics/_/grafana_fqdn"
}

data "aws_secretsmanager_secret_version" "grafana_fqdn" {
  secret_id = "${data.aws_secretsmanager_secret.grafana_fqdn.id}"
  version_stage = "AWSCURRENT"
}

// ECR
resource "aws_ecr_repository" "grafana" {
  name = "grafana"
}

resource "aws_ecr_repository_policy" "grafana" {
  repository = "${aws_ecr_repository.grafana.name}"
  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeRepositories",
                "ecr:GetRepositoryPolicy",
                "ecr:ListImages",
                "ecr:DeleteRepository",
                "ecr:BatchDeleteImage",
                "ecr:SetRepositoryPolicy",
                "ecr:DeleteRepositoryPolicy"
            ]
        }
    ]
}
EOF
}

output "grafana_ecr_uri" {
  value = "${aws_ecr_repository.grafana.repository_url}"
}

resource "aws_ecr_repository" "es_proxy" {
  name = "es-proxy"
}

resource "aws_ecr_repository_policy" "es_proxy" {
  repository = "${aws_ecr_repository.es_proxy.name}"
  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeRepositories",
                "ecr:GetRepositoryPolicy",
                "ecr:ListImages",
                "ecr:DeleteRepository",
                "ecr:BatchDeleteImage",
                "ecr:SetRepositoryPolicy",
                "ecr:DeleteRepositoryPolicy"
            ]
        }
    ]
}
EOF
}

output "es_proxy_ecr_uri" {
  value = "${aws_ecr_repository.es_proxy.repository_url}"
}

////
// cluster
//

resource "aws_vpc" "grafana" {
  cidr_block = "172.25.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.grafana.id}"

  tags {
    Name = "grafana"
  }
}

resource "aws_route" "internet_access" {
  route_table_id = "${aws_vpc.grafana.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.gw.id}"
}

resource "aws_subnet" "grafana_subnet0" {
  vpc_id            = "${aws_vpc.grafana.id}"
  availability_zone = "${var.aws_region}a"
  cidr_block        = "${cidrsubnet(aws_vpc.grafana.cidr_block, 8, 1)}"
  depends_on = [
    "aws_vpc.grafana"
  ]
}

resource "aws_subnet" "grafana_subnet1" {
  vpc_id            = "${aws_vpc.grafana.id}"
  availability_zone = "${var.aws_region}b"
  cidr_block        = "${cidrsubnet(aws_vpc.grafana.cidr_block, 8, 2)}"
  depends_on = [
    "aws_vpc.grafana"
  ]
}

resource "aws_db_subnet_group" "grafana" {
  name       = "grapaha"
  subnet_ids = ["${aws_subnet.grafana_subnet0.id}", "${aws_subnet.grafana_subnet1.id}"]

  tags {
    Name = "My DB subnet group"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = "${aws_vpc.grafana.id}"
  tags {
      Name = "Private route table"
  }
}

resource "aws_route" "private_route" {
  route_table_id  = "${aws_route_table.private_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = "${aws_internet_gateway.gw.id}"
}

resource "aws_route_table_association" "subnet0" {
  subnet_id = "${aws_subnet.grafana_subnet0.id}"
  route_table_id = "${aws_route_table.private_route_table.id}"
}

resource "aws_route_table_association" "subnet1" {
  subnet_id = "${aws_subnet.grafana_subnet1.id}"
  route_table_id = "${aws_route_table.private_route_table.id}"
}

data "aws_subnet_ids" "default" {
  vpc_id = "${aws_vpc.grafana.id}"
  depends_on = [
    "aws_subnet.grafana_subnet0",
    "aws_subnet.grafana_subnet1"
  ]
}

output "subnets" {
  value = ["${data.aws_subnet_ids.default.ids}"]
}

////
// ecs
//

resource "aws_ecs_cluster" "fargate" {
  name = "${var.cluster}"
}

////
// DNS
//

resource "aws_route53_record" "grafana" {
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  name = "${data.aws_secretsmanager_secret_version.grafana_fqdn.secret_string}"
  type = "A"
  alias {
    evaluate_target_health = true
    name = "${aws_lb.grafana.dns_name}"
    zone_id = "${aws_lb.grafana.zone_id}"
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name = "${aws_route53_record.grafana.name}"
  validation_method = "DNS"
}

data "aws_route53_zone" "primary" {
  name         = "${data.aws_secretsmanager_secret_version.domain_name.secret_string}."
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  name = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_name}"
  type = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.primary.id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.0.resource_record_value}"]
  ttl = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn = "${aws_acm_certificate.cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.fqdn}"]
}

////
// load balancer
//

resource "aws_security_group" "grafana" {
  name = "grafana"
  vpc_id = "${aws_vpc.grafana.id}"

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mysql" {
  name = "grafana-mysql"
  vpc_id = "${aws_vpc.grafana.id}"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "grafana" {
  name = "grafana"
  subnets = ["${data.aws_subnet_ids.default.ids}"]
  security_groups = ["${aws_security_group.grafana.id}"]
}

resource "aws_lb_target_group" "grafana" {
  name = "grafana"
  protocol = "HTTP"
  port = 3000
  vpc_id = "${aws_vpc.grafana.id}"
  target_type = "ip"
  health_check {
    protocol = "HTTP"
    port = 3000
    path = "/api/health"
    matcher = "200"
  }
}

output "target_group_arn" {
  value = "${aws_lb_target_group.grafana.arn}"
}

resource "aws_lb_listener" "grafana_https" {
  load_balancer_arn = "${aws_lb.grafana.arn}"
  protocol = "HTTPS"
  port = 443
  certificate_arn = "${aws_acm_certificate_validation.cert.certificate_arn}"
  default_action {
    target_group_arn = "${aws_lb_target_group.grafana.arn}"
    type = "forward"
  }
}

output "security_group" {
  value = "${aws_security_group.grafana.id}"
}

output "lb_name" {
  value = "${aws_lb.grafana.name}"
}


////
// database
//

data "aws_secretsmanager_secret" "grafana_database_user" {
  name = "metrics/_/grafana_database_user"
}

data "aws_secretsmanager_secret" "grafana_database_password" {
  name = "metrics/_/grafana_database_password"
}

data "aws_secretsmanager_secret_version" "grafana_database_user" {
  secret_id = "${data.aws_secretsmanager_secret.grafana_database_user.id}"
  version_stage = "AWSCURRENT"
}

data "aws_secretsmanager_secret_version" "grafana_database_password" {
  secret_id = "${data.aws_secretsmanager_secret.grafana_database_password.id}"
  version_stage = "AWSCURRENT"
}

resource "aws_db_instance" "grafana" {
  allocated_storage    = 5
  storage_type         = "standard"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "grafana"
  username             = "${data.aws_secretsmanager_secret_version.grafana_database_user.secret_string}"
  password             = "${data.aws_secretsmanager_secret_version.grafana_database_password.secret_string}"
  vpc_security_group_ids = ["${aws_security_group.mysql.id}"]
  db_subnet_group_name = "${aws_db_subnet_group.grafana.name}"
  parameter_group_name = "default.mysql5.7"
  apply_immediately = true
  publicly_accessible = false
}

output "mysql_endpoint" {
  value = "${aws_db_instance.grafana.endpoint}"
}

////
// app deployment
//

resource "aws_cloudwatch_log_group" "ecs" {
  name = "/aws/ecs/metrics"
  retention_in_days = 90
}


// task executor role
resource "aws_iam_role" "task_executor" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs.amazonaws.com",
          "ecs-tasks.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "task_executor_ecs" {
  name = "grafana-ecs"
  roles = ["${aws_iam_role.task_executor.name}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy_attachment" "task_executor_ecr" {
  name = "grafana-ecr"
  roles = ["${aws_iam_role.task_executor.name}"]
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

// task role
resource "aws_iam_role" "grafana" {
  name = "grafana"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "ecs-tasks.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy" "grafana" {
  name = "grafana"
  role = "${aws_iam_role.grafana.id}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "sts:AssumeRole"
            ],
            "Resource": [
                "${aws_cloudwatch_log_group.ecs.arn}",
                "arn:aws:logs:*:*:log-group:*:*:*",
                "${aws_iam_role.grafana.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_user" "grafana_datasource" {
  name = "grafana-datasource"
}

resource "aws_iam_policy" "grafana_datasource" {
  name        = "grafana-datasource"
  description = "Credentials for grafana to access CloudWatch Metrics and Logs ElasticSearch"
  policy      =  <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowReadingMetricsFromCloudWatch",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:ListMetrics",
                "cloudwatch:GetMetricStatistics"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "es:DescribeElasticsearchDomain",
                "es:DescribeElasticsearchDomainConfig",
                "es:DescribeElasticsearchDomains",
                "es:ESHttpGet",
                "es:ESHttpHead",
                "es:ListTags"
            ],
            "Resource": [
                "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/hca-logs"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "es:ListDomainNames",
                "es:ListElasticsearchInstanceTypes",
                "es:DescribeElasticsearchInstanceTypeLimits",
                "es:ListElasticsearchVersions"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AllowReadingTagsFromEC2",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeTags",
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_policy_attachment" "grafana_datasource" {
  name       = "grafana-datasource"
  users      = ["${aws_iam_user.grafana_datasource.name}"]
  policy_arn = "${aws_iam_policy.grafana_datasource.arn}"
}

resource "aws_iam_access_key" "grafana_datasource" {
  user = "${aws_iam_user.grafana_datasource.name}"
}

<<<<<<< HEAD
// Upload database secrets

data "aws_secretsmanager_secret" "dev_db_creds" {
  name = "dcp/upload/dev/database"
}

data "aws_secretsmanager_secret_version" "dev_db_creds" {
  secret_id = "${data.aws_secretsmanager_secret.dev_db_creds.id}"
}

data "external" "dev_secrets_processing" {
  program = ["python", "${path.root}/process_db_secrets.py"]

  query = {
    # arbitrary map from strings to strings, passed
    # to the external program as the data query.
    secret_string = "${data.aws_secretsmanager_secret_version.dev_db_creds.secret_string}"
 }
}

data "aws_secretsmanager_secret" "integration_db_creds" {
  name = "dcp/upload/integration/database"
}

data "aws_secretsmanager_secret_version" "integration_db_creds" {
  secret_id = "${data.aws_secretsmanager_secret.integration_db_creds.id}"
}

data "external" "integration_secrets_processing" {
  program = ["python", "${path.root}/process_db_secrets.py"]

  query = {
    # arbitrary map from strings to strings, passed
    # to the external program as the data query.
    secret_string = "${data.aws_secretsmanager_secret_version.integration_db_creds.secret_string}"
 }
}

data "aws_secretsmanager_secret" "staging_db_creds" {
  name = "dcp/upload/staging/database"
}

data "aws_secretsmanager_secret_version" "staging_db_creds" {
  secret_id = "${data.aws_secretsmanager_secret.staging_db_creds.id}"
}

data "external" "staging_secrets_processing" {
  program = ["python", "${path.root}/process_db_secrets.py"]

  query = {
    # arbitrary map from strings to strings, passed
    # to the external program as the data query.
    secret_string = "${data.aws_secretsmanager_secret_version.staging_db_creds.secret_string}"
 }
}

data "aws_secretsmanager_secret" "gcp_logs_datasource_credentials" {
  name = "metrics/_/gcp_logs_datasource_credentials"
}

data "aws_secretsmanager_secret_version" "gcp_logs_datasource_credentials" {
  secret_id = "${data.aws_secretsmanager_secret.gcp_logs_datasource_credentials.id}"
  version_stage = "AWSCURRENT"
}

output "gcp_logs_datasource_credentials" {
  value = "${data.aws_secretsmanager_secret_version.gcp_logs_datasource_credentials.secret_string}"
}
