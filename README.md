# Metrics

![](https://allspark.dev.data.humancellatlas.org/HumanCellAtlas/metrics/badges/master/build.svg)

In order to be able to present metrics from HCA's different metrics systems side by side, we use the [Grafana](https://grafana.com/) metrics presentation layer.

## Metrics Systems
The components in DCP generate metrics from heterogeneous metrics systems some of which are listed below.

* ElasticSearch Clusters
* AWS CloudWatch Metrics
* GCP Monitoring

## Deployments
Grafana deployments are divided by environment boundaries.

* https://metrics.dev.data.humancellatlas.org/ - consolidates metrics from our development accounts; spanning dev, integration, and staging environments
* https://metrics.data.humancellatlas.org/ - consolidates metrics from our production accounts and production environment
