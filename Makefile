SHELL=/bin/bash
APP_NAME=grafana
CLUSTER=FarGate-cluster-$(APP_NAME)
AWS_DEFAULT_REGION=$(shell aws configure get region)
ACCOUNT_ID=$(shell aws sts get-caller-identity | jq -r .Account)
TARGET_GROUP_ARN=$(shell aws elbv2 describe-target-groups | jq -r '.TargetGroups[] | select(.TargetGroupName == "$(APP_NAME)") | .TargetGroupArn')
GRAFANA_IMAGE_NAME=$(shell terraform output grafana_ecr_uri)
ES_PROXY_IMAGE_NAME=$(shell terraform output es_proxy_ecr_uri)
SUBNETS=$(shell terraform output subnets | tr '\n' ' ')
SEC_GROUP=$(shell terraform output security_group)
TARGET_GROUP_ARN=$(shell terraform output target_group_arn)


.PHONY: target
target:
	mkdir -p target

.PHONY: init
init:
	ecs-cli configure \
		--cluster $(CLUSTER) \
		--region $(AWS_DEFAULT_REGION) \
		--default-launch-type FARGATE \
		--config-name $(APP_NAME)
	@ecs-cli configure profile \
		--profile-name $(AWS_PROFILE) \
		--access-key $(shell python3 -c 'from boto3 import Session ; print(Session().get_credentials().get_frozen_credentials().access_key)') \
		--secret-key $(shell python3 -c 'from boto3 import Session ; print(Session().get_credentials().get_frozen_credentials().secret_key)')
	terraform init \
		-backend-config region=$(AWS_DEFAULT_REGION) \
		-backend-config bucket=org-humancellatlas-${ACCOUNT_ID}-terraform \
		-backend-config profile=$(AWS_PROFILE)

terraform-%:
	terraform $(*) \
		-var cluster=$(CLUSTER) \
		-var aws_region=$(AWS_DEFAULT_REGION) \
		-var aws_profile=$(AWS_PROFILE) \
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
	terraform output grafana.ini > target/grafana.ini

.PHONY: all.yaml
all.yaml: target
	terraform output all.yaml > target/all.yaml

.PHONY: docker-compose.yml
docker-compose.yml:
	terraform output docker-compose.yml > docker-compose.yml

.PHONY: ecs-params.yml
ecs-params.yml:
	terraform output ecs-params.yml > ecs-params.yml

.PHONY: gcp-credentials.json
gcp-credentials.json:
	terraform output gcp_logs_datasource_credentials > target/gcp-credentials.json

.PHONY: plugin
plugin:
	rm -rf target/master.zip
	rm -rf target/grafana-google-stackdriver-datasource-master
	cd target && wget https://github.com/mtanda/grafana-google-stackdriver-datasource/archive/master.zip
	cd target && unzip master.zip

.PHONY: image
image: all.yaml grafana.ini gcp-credentials.json
	docker build -t $(APP_NAME) .
	docker pull abutaha/aws-es-proxy:0.8

.PHONY: publish
publish:
	docker tag $(APP_NAME):latest $(GRAFANA_IMAGE_NAME)
	docker push $(GRAFANA_IMAGE_NAME)
	docker tag abutaha/aws-es-proxy:0.8 $(ES_PROXY_IMAGE_NAME)
	docker push $(ES_PROXY_IMAGE_NAME)

.PHONY: deploy-app
deploy-app:
	ecs-cli compose \
		--project-name grafana \
		service up \
		--create-log-groups \
		--cluster-config $(APP_NAME) \
		--container-name $(APP_NAME) \
		--container-port 3000 \
		--target-group-arn $(TARGET_GROUP_ARN) \
		--timeout 10.0 \
		--force-deployment

.PHONY: deploy
deploy:
ifeq ($(AWS_PROFILE),)
	@echo "You must set AWS_PROFILE" && False
endif
ifneq ($(shell cat .terraform/terraform.tfstate | jq -r '.backend.config.profile'),$(AWS_PROFILE))
	$(MAKE) clean target init
endif
	make target
	TERRAFORM_OPTIONS=-auto-approve make apply
	make plugin image publish
	make docker-compose.yml ecs-params.yml deploy-app
