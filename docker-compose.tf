data "external" "hca_logs" {
  program = ["./search_domain.sh", "hca-logs"]
}

output "docker-compose.yml" {
  value = <<EOF
version: '2'
services:
  grafana:
    image: ${aws_ecr_repository.grafana.repository_url}:latest
    ports:
      - "3000:3000"
    logging:
      driver: awslogs
      options:
        awslogs-group: ${aws_cloudwatch_log_group.ecs.name}
        awslogs-region: ${var.aws_region}
        awslogs-stream-prefix: grafana
  es-proxy:
    image: ${aws_ecr_repository.es_proxy.repository_url}:latest
    environment:
      - AWS_ACCESS_KEY_ID=${aws_iam_access_key.grafana_datasource.id}
      - AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.grafana_datasource.secret}
    entrypoint: ./aws-es-proxy -verbose -listen 0.0.0.0:9200 -endpoint https://${data.external.hca_logs.result["endpoint"]}
    ports:
      - "9200:9200"
    logging:
      driver: awslogs
      options:
        awslogs-group: ${aws_cloudwatch_log_group.ecs.name}
        awslogs-region: ${var.aws_region}
        awslogs-stream-prefix: es-proxy
EOF
}

output "ecs-params.yml" {
  value = <<EOF
version: '1'
task_definition:
  task_execution_role: ${aws_iam_role.task_executor.name}
  ecs_network_mode: awsvpc
  task_size:
    mem_limit: 2GB
    cpu_limit: 512
run_params:
  network_configuration:
    awsvpc_configuration:
      subnets:
        - "${aws_subnet.grafana_subnet0.id}"
        - "${aws_subnet.grafana_subnet1.id}"
      security_groups:
        - "${aws_security_group.grafana.id}"
      assign_public_ip: ENABLED
EOF
}
