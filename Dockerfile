FROM grafana/grafana:5.2.3

ENV GOOGLE_APPLICATION_CREDENTIALS ${HOME}/gcp-credentials.json
COPY target/gcp-credentials.json ${GOOGLE_APPLICATION_CREDENTIALS}

COPY target/grafana.ini /etc/grafana/grafana.ini

COPY target/grafana-google-stackdriver-datasource-master/dist/ /var/lib/grafana/plugins/grafana-google-stackdriver-datasource/
