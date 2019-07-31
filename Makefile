SHELL=/bin/bash

APP_NAME=grafana
AWS_DEFAULT_REGION=us-east-1
ACCOUNT_ID=$(shell aws sts get-caller-identity | jq -r .Account)
CICD_ROLE=arn:aws:iam::$(ACCOUNT_ID):role/allspark-eks-node
ifeq ($(IMAGE_TAG),)
IMAGE_TAG := latest
endif

GRAFANA_IMAGE_NAME=$(shell terraform output grafana_ecr_uri)


.PHONY: target
target:
	mkdir -p target

.PHONY: init
init:
	terraform init \
		-backend-config region=$(AWS_DEFAULT_REGION) \
		-backend-config bucket=org-humancellatlas-${ACCOUNT_ID}-terraform \
		-backend-config $(shell [ -z $${AWS_PROFILE+x} ] && echo role_arn=$(CICD_ROLE) || echo profile=$(AWS_PROFILE))

terraform-%:
	terraform $(*) \
		-var aws_profile=$(AWS_PROFILE) \
		-var aws_region=$(AWS_DEFAULT_REGION) \
		-var image_tag=$(IMAGE_TAG) \
		-var elasticsearch_domain=$(ELASTICSEARCH_DOMAIN) \
		$(TERRAFORM_OPTIONS)

.PHONY: plan
plan: terraform-plan

.PHONY: apply
apply: terraform-apply

.PHONY: clean
clean:
	rm -rf target
	rm -rf .terraform
	rm -f docker-compose.yml
	rm -f ecs-params.yml

.PHONY: grafana.ini
grafana.ini: target
	terraform output grafana_ini > target/grafana.ini

.PHONY: container_definitions.json
container_definitions.json: target
	terraform output container_definitions.json > target/container_definitions.json

.PHONY: image
image: grafana.ini
	docker build -t $(APP_NAME):$(IMAGE_TAG) .

.PHONY: publish
publish:
	docker tag $(APP_NAME):$(IMAGE_TAG) $(GRAFANA_IMAGE_NAME):$(IMAGE_TAG)
	docker push $(GRAFANA_IMAGE_NAME):$(IMAGE_TAG)

.PHONY: deploy
deploy:
	TERRAFORM_OPTIONS=-auto-approve $(MAKE) terraform-apply

.PHONY: scale-down
scale-down:
	aws ecs update-service \
		--cluster `terraform output cluster_name` \
		--service grafana \
		--desired-count 0
