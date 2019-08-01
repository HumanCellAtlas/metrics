variable "aws_profile" {}

variable "aws_region" {}

variable "image_tag" {}

variable "elasticsearch_domain" {}

locals {
  common_tags = {
    "managedBy" = "terraform",
    "Name" = "metrics-${var.aws_profile}-grafana",
    "project" = "metrics",
    "service" = "grafana",
    "owner" = "operations-team@data.humancellatlas.org"
  }
}
