.PHONY: help run test build kind-up kind-deploy kind-down tf-init tf-plan tf-apply kubeconfig deploy destroy

# Short SHA doubles as the image tag, matching what CI does.
TAG  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
NAME ?= platform-lab

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

## --- Local, no cloud, no cost -------------------------------------------

run: ## Run the app directly on your machine
	cd app && go run .

test: ## Run unit tests
	cd app && go test -v ./...

build: ## Build the container image locally
	docker build --build-arg VERSION=$(TAG) -t $(NAME):$(TAG) .
	@docker images $(NAME):$(TAG) --format 'image size: {{.Size}}'

kind-up: ## Create a local kind cluster (~30s, free)
	kind create cluster --name $(NAME)
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	# kind nodes have no valid TLS certs for metrics-server; allow insecure in dev only.
	kubectl patch deployment metrics-server -n kube-system --type=json \
	  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kind-deploy: build ## Load the image into kind and deploy (no registry needed)
	kind load docker-image $(NAME):$(TAG) --name $(NAME)
	sed 's|IMAGE_PLACEHOLDER|$(NAME):$(TAG)|g' k8s/deployment.yaml | kubectl apply -f -
	kubectl apply -f k8s/service.yaml
	kubectl apply -f k8s/hpa.yaml
	kubectl rollout status deployment/$(NAME) --timeout=120s

kind-down: ## Delete the local cluster
	kind delete cluster --name $(NAME)

## --- AWS, costs money ---------------------------------------------------

tf-init: ## Initialize Terraform
	cd terraform && terraform init

tf-plan: ## Preview infrastructure changes
	cd terraform && terraform plan

tf-apply: ## Create the EKS cluster (~12 minutes)
	cd terraform && terraform apply

kubeconfig: ## Point kubectl at the EKS cluster
	aws eks update-kubeconfig --region us-east-1 --name $(NAME)

deploy: ## Deploy to whichever cluster kubectl currently targets
	@echo "Deploying to: $$(kubectl config current-context)"
	sed 's|IMAGE_PLACEHOLDER|$(NAME):$(TAG)|g' k8s/deployment.yaml | kubectl apply -f -
	kubectl apply -f k8s/service.yaml
	kubectl apply -f k8s/hpa.yaml

destroy: ## Tear down all AWS resources
	./teardown.sh
