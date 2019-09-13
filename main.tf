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

////
// secrets
//

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

////
// ECR
//

resource "aws_ecr_repository" "grafana" {
  name = "grafana"
  tags = "${local.common_tags}"
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

////
// vpc
//

resource "aws_vpc" "grafana" {
  cidr_block = "172.25.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = "${local.common_tags}"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.grafana.id}"
  tags = "${local.common_tags}"
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
  tags = "${local.common_tags}"
}

resource "aws_subnet" "grafana_subnet1" {
  vpc_id            = "${aws_vpc.grafana.id}"
  availability_zone = "${var.aws_region}b"
  cidr_block        = "${cidrsubnet(aws_vpc.grafana.cidr_block, 8, 2)}"
  depends_on = [
    "aws_vpc.grafana"
  ]
  tags = "${local.common_tags}"
}

resource "aws_db_subnet_group" "grafana" {
  name       = "grapaha"
  subnet_ids = ["${aws_subnet.grafana_subnet0.id}", "${aws_subnet.grafana_subnet1.id}"]
  tags = "${local.common_tags}"
}

resource "aws_route_table" "private_route_table" {
  vpc_id = "${aws_vpc.grafana.id}"
  tags = "${local.common_tags}"
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

////
// ecs
//

resource "aws_ecs_cluster" "fargate" {
  name = "metrics"
  tags = "${local.common_tags}"
}

output "cluster_name" {
  value = "${aws_ecs_cluster.fargate.name}"
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
  tags = "${local.common_tags}"
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
  tags = "${local.common_tags}"
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
  tags = "${local.common_tags}"
}

resource "aws_lb" "grafana" {
  name = "grafana"
  subnets = ["${aws_subnet.grafana_subnet0.id}", "${aws_subnet.grafana_subnet1.id}"]
  security_groups = ["${aws_security_group.grafana.id}"]
  tags = "${local.common_tags}"
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
  tags = "${local.common_tags}"
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
  tags = "${local.common_tags}"
}

////
// app deployment
//

resource "aws_cloudwatch_log_group" "ecs" {
  name = "/aws/ecs/metrics"
  retention_in_days = 1827
  tags = "${local.common_tags}"
}


// task executor role
resource "aws_iam_role" "task_executor" {
  name = "metricsEcsTaskExecutionRole"
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

resource "aws_iam_role_policy_attachment" "task_executor_ecs" {
  role = "${aws_iam_role.task_executor.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_executor_ecr" {
  role = "${aws_iam_role.task_executor.name}"
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

// Elasticsearch proxy access permissions
resource "aws_iam_user" "grafana_elasticsearch_proxy" {
  name = "grafana-elasticsearch-proxy"
}

 resource "aws_iam_policy" "grafana_elasticsearch_proxy" {
  name        = "grafana-elasticsearch-proxy"
  description = "Credentials for grafana to access Logs ElasticSearch"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
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
                "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.elasticsearch_domain}"
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

resource "aws_iam_user_policy_attachment" "grafana_elasticsearch_proxy" {
  user       = "${aws_iam_user.grafana_elasticsearch_proxy.name}"
  policy_arn = "${aws_iam_policy.grafana_elasticsearch_proxy.arn}"
}

resource "aws_iam_access_key" "grafana_elasticsearch_proxy" {
  user = "${aws_iam_user.grafana_elasticsearch_proxy.name}"
}

////
// Task
//

data "external" "elasticsearch" {
  program = ["bash", "es_hostname.sh", "${var.elasticsearch_domain}"]
}

resource "aws_ecs_task_definition" "metrics" {
  family = "grafana"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = "512"
  memory = "3072"
  execution_role_arn = "${aws_iam_role.task_executor.arn}"

  container_definitions = <<EOF
[
  {
    "name": "es-proxy",
    "image": "abutaha/aws-es-proxy:0.9",
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.ecs.name}",
        "awslogs-region": "${var.aws_region}",
        "awslogs-stream-prefix": "es-proxy"
      }
    },
    "entryPoint": [
      "./aws-es-proxy",
      "-verbose",
      "-listen",
      "0.0.0.0:9200",
      "-endpoint",
      "http://${lookup(data.external.elasticsearch.result, "hostname")}"
    ],
    "portMappings": [
      {
        "hostPort": 9200,
        "protocol": "tcp",
        "containerPort": 9200
      }
    ],
    "environment": [
      {
        "name": "AWS_ACCESS_KEY_ID",
        "value": "${aws_iam_access_key.grafana_elasticsearch_proxy.id}"
      },
      {
        "name": "AWS_SECRET_ACCESS_KEY",
        "value": "${aws_iam_access_key.grafana_elasticsearch_proxy.secret}"
      }
    ],
    "memory": 256,
    "cpu": 256,
    "essential": true,
    "readonlyRootFilesystem": false,
    "privileged": false
  },
  {
    "name": "grafana",
    "image": "${aws_ecr_repository.grafana.repository_url}:${var.image_tag}",
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.ecs.name}",
        "awslogs-region": "${var.aws_region}",
        "awslogs-stream-prefix": "grafana"
      }
    },
    "entryPoint": [],
    "portMappings": [
      {
        "hostPort": 3000,
        "protocol": "tcp",
        "containerPort": 3000
      }
    ],
    "memory": 2048,
    "cpu": 256,
    "essential": true,
    "readonlyRootFilesystem": false,
    "privileged": false
  }
]
EOF
  tags = "${local.common_tags}"
}

resource "aws_ecs_service" "metrics" {
  name = "grafana"
  cluster = "${aws_ecs_cluster.fargate.id}"
  task_definition = "${aws_ecs_task_definition.metrics.arn}"
  desired_count = 1
  launch_type = "FARGATE"

  network_configuration {
    subnets = ["${aws_subnet.grafana_subnet0.id}", "${aws_subnet.grafana_subnet1.id}"]
    security_groups = ["${aws_security_group.grafana.id}"]
    assign_public_ip = true
  }

  load_balancer {
    container_name = "grafana"
    container_port = "3000"
    target_group_arn = "${aws_lb_target_group.grafana.arn}"
  }
  tags = "${local.common_tags}"
}

output "task_definition" {
  value = "${aws_ecs_task_definition.metrics.family}:${aws_ecs_task_definition.metrics.revision}"
}
