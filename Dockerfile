FROM grafana/grafana:master

COPY target/grafana.ini /etc/grafana/grafana.ini
COPY target/all.yaml /etc/grafana/provisioning/datasources/all.yaml

COPY target/grafana-google-stackdriver-datasource-master/dist/ /var/lib/grafana/plugins/grafana-google-stackdriver-datasource/

