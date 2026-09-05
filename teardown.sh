#!/usr/bin/env bash
# Destroys every AWS resource this lab creates.
# The EKS control plane bills ~$0.10/hour whether or not anything is deployed,
# so run this whenever you're done for more than a day.
set -euo pipefail

cd "$(dirname "$0")/terraform"

echo "This will destroy the EKS cluster, node group, VPC and ECR repository."
read -rp "Type 'destroy' to confirm: " reply
if [ "$reply" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

# Kubernetes LoadBalancer Services create AWS load balancers that Terraform
# does not know about. Left behind, they keep billing AND block VPC deletion.
if kubectl config current-context >/dev/null 2>&1; then
  echo "Removing LoadBalancer services first..."
  kubectl delete svc --all-namespaces \
    --field-selector spec.type=LoadBalancer --ignore-not-found || true
  sleep 20
fi

terraform destroy

echo
echo "Done. Verify nothing survived:"
echo "  aws eks list-clusters --region us-east-1"
echo "  aws ec2 describe-instances --region us-east-1 \\"
echo "    --filters Name=instance-state-name,Values=running \\"
echo "    --query 'Reservations[].Instances[].InstanceId'"
