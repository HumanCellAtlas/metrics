APP_NAME=grafana-new
CLUSTER=FarGate-cluster-$(APP_NAME)
AWS_DEFAULT_REGION=$(shell aws configure get region)
ACCOUNT_ID=$(shell aws sts get-caller-identity | jq -r .Account)
TARGET_GROUP_ARN=$(shell aws elbv2 describe-target-groups | jq -r '.TargetGroups[] | select(.TargetGroupName == "$(APP_NAME)") | .TargetGroupArn')
GRAFANA_IMAGE_NAME=$(shell terraform output grafana_ecr_uri)
ES_PROXY_IMAGE_NAME=$(shell terraform output es_proxy_ecr_uri)
SUBNETS=$(shell terraform output subnets | tr '\n' ' ')
SEC_GROUP=$(shell terraform output security_group)


.PHONY: target
target:
	mkdir -p target

.PHONY: init
init:
	terraform init \
		-backend-config region=$(AWS_DEFAULT_REGION) \
		-backend-config bucket=org-humancellatlas-${ACCOUNT_ID}-terraform \
		-backend-config profile=$(AWS_PROFILE)

terraform-%:
	terraform $(*) \
		-var cluster=$(CLUSTER) \
		-var aws_region=$(AWS_DEFAULT_REGION) \
		-var aws_profile=$(AWS_PROFILE)

.PHONY: plan
plan: terraform-plan

.PHONY: apply
apply: terraform-apply

.PHONY: clean
clean:
	rm -rf target
	rm -rf .terraform

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

.PHONY: image
image:
	docker build -t $(APP_NAME) .
	docker pull gorillastack/aws-es-proxy:latest

.PHONY: publish
publish:
	docker tag $(APP_NAME):latest $(GRAFANA_IMAGE_NAME)
	docker push $(GRAFANA_IMAGE_NAME)
	docker tag abutaha/aws-es-proxy:0.8 $(ES_PROXY_IMAGE_NAME)
	docker push $(ES_PROXY_IMAGE_NAME)

.PHONY: deploy
deploy:
ifeq ($(AWS_PROFILE),)
	@echo "You must set AWS_PROFILE" && False
endif
ifneq ($(shell cat .terraform/terraform.tfstate | jq -r '.backend.config.profile'),$(AWS_PROFILE))
	rm -r .terraform
	$(MAKE) init
endif
	make apply image publish
	make all.yaml docker-compose.yml ecs-params.yml
	ecs-cli compose \
		--project-name grafana-new \
		service up \
		--create-log-groups \
		--cluster-config $(APP_NAME) \
		--force-deployment
