#!/bin/bash

PORT=$1
ATTEMPTS=1
MAX_ATTEMPTS=10

while ! nc -z localhost "$PORT"; do
  sleep 1.0 # wait before checking again
  echo "Waiting for active scan on port $PORT..."
  ATTEMPTS=$(( $ATTEMPTS + 1 ))
  if [ $ATTEMPTS -gt $MAX_ATTEMPTS ]; then
    exit 1
  fi
done

echo "Scan of port $PORT active."
