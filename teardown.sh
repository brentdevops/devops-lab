#!/usr/bin/env bash
# Destroys every AWS resource this lab creates.
set -euo pipefail

cd "$(dirname "$0")"

echo "This will destroy the EKS cluster, node group, VPC and ECR repository."
read -rp "Type 'destroy' to confirm: " reply
if [ "$reply" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

# Uninstall the Helm release first so any LoadBalancer Services it created are
# removed. Those AWS load balancers are invisible to Terraform: left behind,
# they keep billing and block VPC deletion.
if kubectl config current-context >/dev/null 2>&1; then
  echo "Uninstalling Helm release..."
  helm uninstall platform-lab || true
  kubectl delete svc --all-namespaces \
    --field-selector spec.type=LoadBalancer --ignore-not-found || true
  sleep 20
fi

cd terraform
terraform destroy -var-file=dev.tfvars

echo
echo "Done. Verify nothing survived:"
echo "  aws eks list-clusters --region us-east-1"
echo "  aws ec2 describe-instances --region us-east-1 \\"
echo "    --filters Name=instance-state-name,Values=running \\"
echo "    --query 'Reservations[].Instances[].InstanceId'"
