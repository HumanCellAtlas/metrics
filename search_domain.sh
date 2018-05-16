#!/bin/bash
domain="$1"
endpoint=$(aws es describe-elasticsearch-domain --domain-name $domain | jq -r .DomainStatus.Endpoint)
echo "{\"endpoint\": \"$endpoint\"}"
