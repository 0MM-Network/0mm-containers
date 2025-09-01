SHELL := /bin/bash

-include .env-gdc-local

CDIR = cd iac/awscdk
TDIR = cd tests

export APP_NAME?=ecslb
export ENFORCE_IAM?=0
export AWS_ENDPOINT_URL?=http://localhost:4566

usage:			## Show this help in table format
	@echo "| Target                 | Description                                                       |"
	@echo "|------------------------|-------------------------------------------------------------------|"
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/:.*##\s*/##/g' | awk -F'##' '{ printf "| %-22s | %-65s |\n", $$1, $$2 }'

check-env:      ## Check if all required environment variables are set
	@[ -n "$$AWS_ACCESS_KEY_ID" ] || { echo "AWS_ACCESS_KEY_ID is not set. Please set it and try again."; exit 1; }
	@[ -n "$$AWS_SECRET_ACCESS_KEY" ] || { echo "AWS_SECRET_ACCESS_KEY is not set. Please set it and try again."; exit 1; }
	@[ -n "$$AWS_DEFAULT_REGION" ] || { echo "AWS_DEFAULT_REGION is not set. Please set it and try again."; exit 1; }
	@[ -n "$$CDK_DEFAULT_REGION" ] || { echo "CDK_DEFAULT_REGION is not set. Please set it and try again."; exit 1; }
	@[ -n "$$CDK_DEFAULT_ACCOUNT" ] || { echo "CDK_DEFAULT_ACCOUNT is not set. Please set it and try again."; exit 1; }
	@[ -n "$$AWS_ENDPOINT_URL" ] || { echo "AWS_ENDPOINT_URL is not set. Please set it and try again."; exit 1; }
	@[ -n "$$AWS_PROFILE" ] || { echo "AWS_PROFILE is not set. Please set it and try again."; exit 1; }
	@echo "All required environment variables are set.";

check: check-env   ## Check if all required prerequisites are installed
	@command -v podman > /dev/null 2>&1 || { echo "Docker is not installed. Please install Docker and try again."; exit 1; }
	@command -v node > /dev/null 2>&1 || { echo "Node.js is not installed. Please install Node.js and try again."; exit 1; }
	@command -v aws > /dev/null 2>&1 || { echo "AWS CLI is not installed. Please install AWS CLI and try again."; exit 1; }
	@command -v localstack > /dev/null 2>&1 || { echo "LocalStack is not installed. Please install LocalStack and try again."; exit 1; }
	@command -v cdk > /dev/null 2>&1 || { echo "CDK is not installed. Please install CDK and try again."; exit 1; }
	@echo "All required prerequisites are available.";

install:		## Install NPM dependencies
	@${CDIR}; if [ ! -d "node_modules" ]; then \
		echo "Installing NPM dependencies..."; \
		npm install; \
		cdk acknowledge 34892; \
		cdk acknowledge 34635; \
	else \
		echo "NPM dependencies for CDK project already installed."; \
	fi
	@${TDIR}; if [ ! -d "node_modules" ]; then \
		echo "Installing NPM dependencies..."; \
		npm install; \
		cdk acknowledge 34892; \
		cdk acknowledge 34892; \
	else \
		echo "NPM dependencies for tests already installed."; \
	fi

# CDK's bootstrap logic doesn't fully redirect to the custom endpoint by
# default—it still requires valid authentication for resolution. LocalStack
# mocks these resources internally, making bootstrap unnecessary and prone
# to failure in this setup.
deploy:			## Bootstrap and deploy the CDK app on LocalStack
	${CDIR}; cdklocal deploy --outputs-file ./output.json --json --require-approval never

deploy-live:		## Bootstrap and deploy the CDK app on AWS
	${CDIR}; cdk bootstrap; cdk deploy --outputs-file ./output.json --json

destroy:		## Destroy the deployed CDK stack on LocalStack
	${CDIR}; cdklocal destroy

destroy-aws:	## Destroy the deployed CDK stack on AWS
	${CDIR}; cdk destroy

test:			## Run integration tests on LocalStack
	cd tests && LOCALSTACK=1 npm run test

test-aws:		## Run integration tests on AWS
	cd tests && npm run test

curl:			## Curl the LocalStack service load balancer
	curl $(shell cat iac/awscdk/output.json | jq '.RepoStack.localstackserviceslb')

curl-aws:		## Curl the AWS service load balancer
	curl $(shell cat iac/awscdk/output.json | jq '.RepoStack.serviceslb')

start:			## Start LocalStack
	@echo "Starting LocalStack..."
	@LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN) localstack start -d
	@echo "LocalStack started successfully."

stop:			## Stop LocalStack
	@echo "Stopping LocalStack..."
	@localstack stop
	@echo "LocalStack stopped successfully."

ready:			## Make sure the LocalStack container is up
		@echo Waiting on the LocalStack container...
		@localstack wait -t 30 && echo LocalStack is ready to use! || (echo Gave up waiting on LocalStack, exiting. && exit 1)

logs:			## Save the logs in a separate file
		@localstack logs > logs.txt

PKG_SUB_DIRS := $(dir $(shell find . -type d -name node_modules -prune -o -type d -name "venv*" -prune -o -type f -name package.json -print))

update-deps: $(PKG_SUB_DIRS)
	for i in $(PKG_SUB_DIRS); do \
        pushd $$i && ncu -u && npm install && popd; \
    done

.PHONY: usage install check start deploy curl test destroy logs deploy-aws curl-aws test-aws destroy-aws update-deps
