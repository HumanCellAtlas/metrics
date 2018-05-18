FROM grafana/grafana:5.0.4

COPY target/grafana.ini /etc/grafana/grafana.ini
COPY target/all.yaml /etc/grafana/provisioning/datasources/all.yaml

COPY target/grafana-google-stackdriver-datasource-master/dist/ /var/lib/grafana/plugins/grafana-google-stackdriver-datasource/

