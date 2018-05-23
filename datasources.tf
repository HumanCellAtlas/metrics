output "all.yaml" {
  value = <<EOF
apiVersion: 1

datasources:
-  name: 'Cloudwatch'
   type: 'cloudwatch'
   jsonData:
     authType: keys
   secureJsonData:
     defaultRegion: ${var.aws_region}
     accessKey: ${aws_iam_access_key.grafana_datasource.id}
     secretKey: ${aws_iam_access_key.grafana_datasource.secret}
- name: hca-logs
  type: elasticsearch
  access: proxy
  database: "[cwl-]YYYY-MM-DD"
  url: http://0.0.0.0:9200
  jsonData:
    interval: Daily
    timeField: "@timestamp"
- name: upload-dev-db
  type: postgres
  url:  ${data.external.dev_secrets_processing.result.host}
  database: ${data.external.dev_secrets_processing.result.db_name}
  user: ${data.external.dev_secrets_processing.result.username}
  secureJsonData:
    password: ${data.external.dev_secrets_processing.result.password}
  jsonData:
    sslmode: "disable"
- name: upload-integration-db
  type: postgres
  url:  ${data.external.integration_secrets_processing.result.host}
  database: ${data.external.integration_secrets_processing.result.db_name}
  user: ${data.external.integration_secrets_processing.result.username}
  secureJsonData:
    password: ${data.external.integration_secrets_processing.result.password}
  jsonData:
    sslmode: "disable"
- name: upload-staging-db
  type: postgres
  url:  ${data.external.staging_secrets_processing.result.host}
  database: ${data.external.staging_secrets_processing.result.db_name}
  user: ${data.external.staging_secrets_processing.result.username}
  secureJsonData:
    password: ${data.external.staging_secrets_processing.result.password}
  jsonData:
    sslmode: "disable"
EOF
  depends_on = ["data.external.dev_secrets_processing", "data.external.integration_secrets_processing", "data.external.staging_secrets_processing"]
}
