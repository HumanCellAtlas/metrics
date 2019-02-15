FROM grafana/grafana:6.0.0-beta2

COPY target/grafana.ini /etc/grafana/grafana.ini
