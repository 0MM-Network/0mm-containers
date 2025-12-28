.PHONY: test run deploy destroy build_docker run_docker

.EXPORT_ALL_VARIABLES:
AWS_PROFILE = default
AWS_REGION = us-east-1

run:
	cd cmd && go run main.go

build_docker:
	docker build -t ddb-local-fargate .

run_docker: build_docker
	docker run -it -e PARAM1=test1 -p 5050:5050 -e AWS_PROFILE=${AWS_PROFILE} -v ${HOME}/.aws:/root/.aws ddb-local-fargate

test:
	docker-compose up --detach;
	pushd pkg/service && go test;
	popd;
	docker-compose down;

deploy:
	cd cdk;\
	cdklocal bootstrap && cdklocal deploy '*'

destroy:
	cd cdk;\
	cdklocal destroy \*
