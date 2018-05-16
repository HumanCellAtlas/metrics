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
EOF
}
