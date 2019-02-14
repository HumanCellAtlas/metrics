#!/usr/bin/env bash

tmp=$(aws es describe-elasticsearch-domain --domain-name "$1" | jq -r .DomainStatus.Endpoint)
jq -n --arg hn "$tmp" '{"hostname":$hn}'

