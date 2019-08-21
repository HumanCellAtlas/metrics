FROM grafana/grafana:6.3.3

COPY target/grafana.ini /etc/grafana/grafana.ini
