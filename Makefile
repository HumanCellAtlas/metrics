APP_NAME=grafana-new
CLUSTER=FarGate-cluster-$(APP_NAME)
AWS_DEFAULT_REGION=$(shell aws configure get region)
ACCOUNT_ID=$(shell aws sts get-caller-identity | jq -r .Account)
TARGET_GROUP_ARN=$(shell aws elbv2 describe-target-groups | jq -r '.TargetGroups[] | select(.TargetGroupName == "$(APP_NAME)") | .TargetGroupArn')
IMAGE_NAME=$(shell terraform output ecr_uri)
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

.PHONY: task.json
task.json: target
	terraform output task.json > target/task.json

.PHONY: all.yaml
all.yaml: target
	terraform output all.yaml > target/all.yaml

.PHONY: image
image: grafana.ini all.yaml
	docker build -t $(APP_NAME) .

.PHONY: publish
publish:
	docker tag $(APP_NAME):latest $(IMAGE_NAME)
	docker push $(IMAGE_NAME)

.PHONY: service
service: task.json
	aws ecs register-task-definition \
		--cli-input-json file://$(PWD)/target/task.json
	aws ecs create-service \
		--service-name $(APP_NAME) \
		--desired-count 0 \
		--cluster $(CLUSTER) \
		--task-definition $(APP_NAME) \
		--network-configuration "awsvpcConfiguration={subnets=[$(SUBNETS)],securityGroups=[$(SEC_GROUP)],assignPublicIp=ENABLED}" \
		--load-balancers targetGroupArn=$(TARGET_GROUP_ARN),containerName=$(APP_NAME),containerPort=3000 \
		--launch-type FARGATE

.PHONY: deploy-service
deploy-service:
	aws ecs update-service \
		--cluster $(CLUSTER) \
		--service $(APP_NAME) \
		--task-definition $(APP_NAME) \
		--desired-count 1 \
		--force-new-deployment

.PHONY: scale-down-service
scale-down-service:
	aws ecs list-services \
		--cluster $(CLUSTER) | \
		jq -r .serviceArns[] | \
		xargs aws ecs update-service --cluster $(CLUSTER) --desired-count 0 --service
	aws ecs list-tasks \
		--cluster $(CLUSTER) \
		--family $(APP_NAME) | \
		jq -r .taskArns[] | \
		xargs aws ecs stop-task --cluster $(CLUSTER) --task

.PHONY: delete-service
delete-service: scale-down-service
	aws ecs list-services \
		--cluster $(CLUSTER) | \
		jq -r .serviceArns[] | \
		xargs aws ecs delete-service --cluster $(CLUSTER) --service

.PHONY: deploy
deploy:
ifeq ($(AWS_PROFILE),)
	@echo "You must set AWS_PROFILE" && False
endif
ifneq ($(shell cat .terraform/terraform.tfstate | jq -r '.backend.config.profile'),$(AWS_PROFILE))
	rm -r .terraform
	$(MAKE) init
endif
	make apply image publish scale-down-service deploy-service
