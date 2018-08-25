FROM grafana/grafana:master

ENV GOOGLE_APPLICATION_CREDENTIALS ${HOME}/gcp-credentials.json
COPY target/gcp-credentials.json ${GOOGLE_APPLICATION_CREDENTIALS}

COPY target/grafana.ini /etc/grafana/grafana.ini
