FROM grafana/grafana:6.2.5

COPY target/grafana.ini /etc/grafana/grafana.ini
