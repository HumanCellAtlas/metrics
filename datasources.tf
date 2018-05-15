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
EOF
}
