# Platform Lab — Phase 1

A small Go service, containerized, running on EKS, deployed by GitHub Actions.
Deliberately minimal: 16 files, no Helm, no modules, no monitoring yet.
Phase 2 refactors this into Terraform modules and a Helm chart.

Account `493116365821` · region `us-east-1` · cluster `platform-lab`

---

## Run order

Work through it in this order. Steps 1–2 are free and local. Step 3 starts
costing about **$4.40/day**.

### 1. Local — no cluster

```bash
make test          # unit tests
make run           # http://localhost:8080
make build         # container image, expect ~6MB
```

Check it:

```bash
curl localhost:8080          # {"message":"...","version":"dev","pod":"..."}
curl localhost:8080/healthz
```

### 2. Local Kubernetes with kind — still free

```bash
make kind-up       # ~30 seconds
make kind-deploy
kubectl get pods
kubectl port-forward svc/platform-lab 8080:80
```

Do most of your practice here. Delete and recreate freely.

### 3. AWS — this is where billing starts

```bash
make tf-init
make tf-plan       # read this before applying
make tf-apply      # ~12 minutes, mostly the control plane
make kubeconfig
kubectl get nodes  # expect 2 Ready nodes
```

### 4. Wire up CI/CD

Create the OIDC provider once per account:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Create a role GitHub can assume. Replace `YOUR_GH_USER/YOUR_REPO`:

```bash
cat > trust.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::493116365821:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR_GH_USER/YOUR_REPO:*"
      }
    }
  }]
}
EOF

aws iam create-role --role-name githubActionsRole \
  --assume-role-policy-document file://trust.json

aws iam attach-role-policy --role-name githubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

> `AdministratorAccess` is too broad for production. Narrowing it to the
> specific ECR and EKS actions is a good later exercise — and a good thing
> to volunteer in an interview.

Give that role cluster access:

```bash
aws eks create-access-entry --cluster-name platform-lab \
  --principal-arn arn:aws:iam::493116365821:role/githubActionsRole \
  --region us-east-1

aws eks associate-access-policy --cluster-name platform-lab \
  --principal-arn arn:aws:iam::493116365821:role/githubActionsRole \
  --access-scope type=cluster \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --region us-east-1
```

Then in GitHub: **Settings → Secrets and variables → Actions → New secret**
named `AWS_ROLE_ARN`, value `arn:aws:iam::493116365821:role/githubActionsRole`.

Push to `main` and watch the Actions tab.

### 5. Tear down when done

```bash
./teardown.sh
```

---

## What each piece is for

| Path | Purpose |
|---|---|
| `app/` | ~60-line Go service. Reports its own version and pod name. |
| `Dockerfile` | Multi-stage → `scratch`. No shell, no OS, non-root. |
| `k8s/deployment.yaml` | 2 replicas, requests/limits, liveness + readiness probes. |
| `k8s/service.yaml` | ClusterIP. The selector is a common 503 culprit. |
| `k8s/hpa.yaml` | Scales 2→5 on CPU. Needs metrics-server. |
| `terraform/main.tf` | VPC, EKS cluster, node group, add-ons. |
| `terraform/ecr.tf` | Image registry with lifecycle expiry. |
| `.github/workflows/deploy.yml` | Test → build → push → deploy, OIDC auth. |
| `teardown.sh` | Destroys everything, LoadBalancers first. |

---

## Cost

| Item | Per day |
|---|---|
| EKS control plane | $2.40 |
| 2 × t3.small | $2.00 |
| ECR, VPC, IGW | ~$0.05 |
| **Total** | **~$4.40** |

The control plane is ~55% of it and is fixed no matter what nodes you pick.
Cutting cost means running fewer days, not smaller nodes. Use kind for daily
work; bring EKS up for the AWS-specific exercises.

---

## Design choices worth defending

Each of these is a real tradeoff. Being able to say why is the point.

**Public subnets, no NAT Gateway.** Saves ~$32/month. Cost: worker nodes hold
public IPs. Production puts nodes in private subnets with a NAT Gateway per AZ.

**IAM roles looked up, not created.** You made `eksClusterRole` and
`eksNodeRole` with the CLI, so Terraform reads them with `data` blocks.
Importing them into state later is the `terraform import` exercise.

**Local state.** So you can open `terraform.tfstate` and see what it holds.
Phase 2 moves it to S3 with versioning plus a DynamoDB lock table.

**SHA tags, never `latest`.** Every deploy traces to one commit, and rollback
is redeploying a known tag. This is the question your last interviewer asked
four different ways.

**`scratch` base image.** ~6MB, no shell. Nothing to exploit, but also nothing
to debug with — no `kubectl exec` into a shell. `distroless` is the middle
ground. Know the tradeoff.

**2 nodes minimum.** One node cannot demonstrate node-failure recovery,
anti-affinity, or PodDisruptionBudgets.

---

## Phase 2 (not built yet)

- Split flat Terraform into `modules/{vpc,eks,ecr}` with `envs/dev` + `envs/prod`
- Convert `k8s/*.yaml` into a Helm chart you write yourself
- Move state to S3 + DynamoDB
- Pipeline calls `helm upgrade --set image.tag=$SHA`

## Phase 3 (not built yet)

Break-fix scenarios: ImagePullBackOff, CrashLoopBackOff, OOMKill, Terraform
drift and `import` recovery, broken Service selector causing 503s, corrupted
state file recovery.
