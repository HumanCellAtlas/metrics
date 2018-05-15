output "task.json" {
  value = <<EOF
{
  "family": "grafana-new",
  "containerDefinitions": [
      {
          "name": "grafana-new",
          "image": "${aws_ecr_repository.grafana.repository_url}",
          "cpu": 0,
          "memoryReservation": 1024,
          "portMappings": [
              {
                  "containerPort": 3000,
                  "hostPort": 3000,
                  "protocol": "tcp"
              }
          ],
          "essential": true,
          "environment": [],
          "mountPoints": [],
          "volumesFrom": [],
          "logConfiguration": {
              "logDriver": "awslogs",
              "options": {
                  "awslogs-group": "${aws_cloudwatch_log_group.ecs.name}",
                  "awslogs-region": "${var.aws_region}",
                  "awslogs-stream-prefix": "ecs"
              }
          }
      }
  ],
  "taskRoleArn": "${aws_iam_role.grafana.arn}",
  "executionRoleArn": "${aws_iam_role.task_executor.arn}",
  "networkMode": "awsvpc",
  "volumes": [],
  "placementConstraints": [],
  "requiresCompatibilities": [
      "FARGATE"
  ],
  "cpu": "512",
  "memory": "2048"
}
EOF
}
