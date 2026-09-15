# Phase 2 — Terraform modules + Helm

Refactor only. Same cluster, same app, better structure.

**Run the steps in order. Step 1 and 2 verify without changing anything.**

---

## Part A — Terraform modules

### What changed

Before: 14 resources in two flat files.
After: three reusable modules, called by a thin root, with per-environment tfvars.

```
terraform/
  main.tf              calls the modules
  moved.tf             state refactor declarations
  variables.tf         inputs
  outputs.tf           outputs
  dev.tfvars           this cluster
  prod.tfvars          the pattern, not applied
  modules/vpc/
  modules/eks/
  modules/ecr/
```

`ecr.tf` is gone — its contents moved into `modules/ecr/`.

### The risk, and how it is handled

Moving a resource into a module changes its address in state:
`aws_vpc.main` becomes `module.vpc.aws_vpc.main`.

Terraform reads that as *delete the old thing, create a new one*. On a live
cluster that is a 25-minute outage and a new cluster endpoint.

`moved.tf` prevents it. Each block tells Terraform the resource is the same
thing at a new address. State is updated, nothing is touched in AWS.

The old approach was `terraform state mv` — imperative, run by hand, invisible
in code review, easy to half-finish. `moved` blocks are declarative and live in
the repo. Good thing to know the difference between; interviewers ask.

### Step 1 — verify the refactor is a no-op

```bash
cd ~/Downloads/devops-lab/terraform
terraform init
terraform plan -var-file=dev.tfvars
```

**The only acceptable output is `No changes. Your infrastructure matches the
configuration.`**, preceded by 12 lines reading
`module.vpc.aws_vpc.main has moved to ...`.

If the plan proposes destroying anything, **stop**. An address in `moved.tf`
does not match a resource in the modules. Nothing has changed yet — plan is
read-only.

### Step 2 — apply

```bash
terraform apply -var-file=dev.tfvars
```

Applies the state moves. No AWS API calls to create or destroy anything.

### Step 3 — see the environment pattern

```bash
terraform plan -var-file=prod.tfvars
```

This proposes a **whole second cluster** — different name, CIDR, instance type,
node count, and IMMUTABLE ECR tags. Do not apply it; it is another $73/month.
The point is that one set of modules produced two environments from two input
files.

That is the answer to "how would you deploy this to multiple accounts and
regions?" — parameterized modules, thin roots, separate state per environment,
`-var-file` to select inputs.

---

## Part B — Helm chart

### What changed

Three static YAML files with a placeholder string became a chart with values
files per environment.

```
chart/
  Chart.yaml
  values.yaml            defaults
  values-dev.yaml        dev overrides
  values-prod.yaml       prod overrides
  templates/_helpers.tpl naming and labels
  templates/deployment.yaml
  templates/service.yaml
  templates/hpa.yaml
```

Three things worth noticing in the templates:

**`image.tag` has no default and the template calls `fail` if it is empty.**
You cannot accidentally deploy `latest`. Every deploy names an exact image.

**Selector labels come from one helper**, used by both the pod template and the
Service selector. They cannot drift apart. Hand-written YAML drifting here is
the classic cause of a Service with zero endpoints returning 503s.

**Version is in the metadata labels but not the selector labels.** Deployment
selectors are immutable — a version in the selector would break every upgrade.

### Step 4 — render locally, change nothing

```bash
cd ~/Downloads/devops-lab
helm lint ./chart --set image.tag=test
helm template platform-lab ./chart -f chart/values-dev.yaml --set image.tag=test
```

Read the output. It is exactly what would be sent to the cluster. Then:

```bash
helm template platform-lab ./chart -f chart/values-prod.yaml --set image.tag=test
```

Same chart, 3 replicas, bigger resources, an HPA, and anti-affinity rules.

Confirm the safety net works:

```bash
helm template platform-lab ./chart
```

That should fail with *image.tag is required*.

### Step 5 — hand the running app over to Helm

Your Deployment and Service were created with `kubectl apply`, so Helm does not
own them. Installing over the top fails with an ownership error.

Delete them and let Helm recreate them. A few seconds of downtime, fine here:

```bash
kubectl delete deployment platform-lab
kubectl delete service platform-lab
```

Install, pinning the image already running:

```bash
helm upgrade --install platform-lab ./chart \
  -f chart/values-dev.yaml \
  --set image.tag=e0f5f9c \
  --wait --atomic --timeout 3m
```

Check:

```bash
helm list
kubectl get pods
kubectl get endpoints platform-lab
```

`endpoints` must list two pod IPs. Empty means the Service selector does not
match the pods.

> In production you would adopt rather than delete, by patching the existing
> objects with the `meta.helm.sh/release-name` annotation and the
> `app.kubernetes.io/managed-by: Helm` label. Worth knowing that adoption is
> possible — deleting production to install a chart is not an option.

### Step 6 — rollback, which Helm gives you free

```bash
helm history platform-lab
helm rollback platform-lab 1
```

Helm keeps every release revision. Rollback is one command, no rebuild.

---

## What the pipeline does now

The deploy step is one `helm upgrade --install` instead of `sed` piped into
three `kubectl apply` calls. Two additions worth calling out:

- `--atomic` automatically rolls back if the release does not become healthy,
  so a bad deploy self-heals instead of leaving crashlooping pods
- a `lint-chart` job renders both environments on every PR, so template errors
  fail in review rather than mid-rollout

---

## Talking points this earns you

**"How do you structure Terraform across environments?"**
Modules with parameterized inputs, thin root configs, one state per
environment, `terraform apply -var-file=prod.tfvars`. Terragrunt if the backend
config repetition gets painful.

**"How do you refactor Terraform without downtime?"**
`moved` blocks. Declarative, reviewable in a PR, and the plan proves it is a
no-op before you apply. `terraform state mv` is the older imperative way.

**"Why Helm instead of raw manifests?"**
Templating for multi-environment, a release history so rollback is one command,
atomic deploys, and one place that guarantees selector labels match. Raw YAML
plus `sed` works until you have two environments.

**"How does the pipeline pick the image?"**
`--set image.tag=$GITHUB_SHA`. The chart refuses to render without a tag, so
`latest` cannot happen. Rollback re-runs the workflow with an older SHA.

---

## Still open

- State is local. S3 with versioning plus a DynamoDB lock table is ~20 minutes
  and answers "how do you secure and back up state."
- CI role still has `AdministratorAccess`. Should be scoped to ECR and EKS.
- No monitoring. metrics-server is required before the HPA does anything.
- Public subnets, no NAT — a cost decision, not a production one.
