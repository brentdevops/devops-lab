# Terraform Drills — LocalStack

Fake AWS in Docker. Real Terraform. Zero cost.

## Start

```bash
cd local/localstack
docker compose up -d
terraform init
terraform apply -var-file=dev.tfvars
```

Creates 3 S3 buckets, a DynamoDB table, 2 SQS queues, an IAM role and policy.

Check it worked:

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
```

---

## Drill 1 — Drift

Change something outside Terraform:

```bash
aws --endpoint-url=http://localhost:4566 s3api put-bucket-tagging \
  --bucket lab-dev-logs \
  --tagging 'TagSet=[{Key=Owner,Value=someone-else}]'
```

```bash
terraform plan -var-file=dev.tfvars
```

Plan wants to remove the tag.

**Two choices.** The manual change was wrong → `apply` reverts it. The manual change was right → add the tag to your code, then apply so state agrees.

**The tell:** plan wants to CHANGE something you didn't edit → drift.

---

## Drill 2 — Import

Create something outside Terraform:

```bash
aws --endpoint-url=http://localhost:4566 s3 mb s3://lab-dev-manual
```

```bash
terraform plan -var-file=dev.tfvars
```

No change — Terraform doesn't know it exists.

Now declare it:

```bash
cat > manual.tf <<'EOF'
resource "aws_s3_bucket" "manual" {
  bucket = "lab-dev-manual"
}
EOF
```

```bash
terraform plan -var-file=dev.tfvars
```

Now it says "1 to add". Applying would fail — the bucket exists.

```bash
terraform import -var-file=dev.tfvars aws_s3_bucket.manual lab-dev-manual
terraform plan -var-file=dev.tfvars
```

Clean.

**Import writes to state only.** You write the code yourself.

**The tell:** plan wants to CREATE something that already exists → import.

---

## Drill 3 — state rm

Tell Terraform to forget a resource without deleting it:

```bash
terraform state list
terraform state rm 'aws_s3_bucket.manual'
terraform plan -var-file=dev.tfvars
```

Plan wants to create it again. The bucket still exists in AWS — only state forgot.

Recover:

```bash
terraform import -var-file=dev.tfvars aws_s3_bucket.manual lab-dev-manual
```

**When you'd use `state rm` for real:** a resource was deleted outside Terraform and every plan now errors trying to read it. Remove it from state so Terraform stops looking.

---

## Drill 4 — state mv

Rename a resource in code without destroying it.

Edit `manual.tf`, change `"manual"` to `"adopted"`:

```bash
terraform plan -var-file=dev.tfvars
```

Plan says destroy + create. Terraform sees the old address gone and a new one wanted.

Two ways to fix it.

**Old way — imperative:**

```bash
terraform state mv 'aws_s3_bucket.manual' 'aws_s3_bucket.adopted'
```

**Modern way — declarative.** Add to your code instead:

```hcl
moved {
  from = aws_s3_bucket.manual
  to   = aws_s3_bucket.adopted
}
```

Either way `plan` comes back clean.

**Why `moved` is better:** it lives in the repo, shows up in code review, and runs the same for everyone. `state mv` is a command one person ran on their laptop that nobody else can see.

---

## Drill 5 — for_each vs count

Remove `"artifacts"` from `bucket_names` in `dev.tfvars`:

```bash
terraform plan -var-file=dev.tfvars
```

Exactly one bucket is destroyed. `logs` and `backups` are untouched.

**With `count` it would be different.** Buckets are addressed by index — `[0]`, `[1]`, `[2]`. Removing the middle one shifts `backups` from index 2 to index 1, so Terraform destroys and recreates it.

**The tell:** if the list can change in the middle, use `for_each`. `count` is for "N identical copies" only.

Put it back when done.

---

## Drill 6 — Broken state recovery

Back it up, then break it:

```bash
cp terraform.tfstate terraform.tfstate.bak
echo "corrupted" >> terraform.tfstate
terraform plan -var-file=dev.tfvars
```

Fails to parse.

Recover:

```bash
cp terraform.tfstate.bak terraform.tfstate
terraform plan -var-file=dev.tfvars
```

**In production you wouldn't have a local backup.** State lives in S3 with versioning on, so you restore the previous object version. That's the reason versioning is non-negotiable.

---

## Drill 7 — Locking

Terraform locks state during an apply so two people can't write at once.

With local state the lock is a file. With S3 the lock is a row in DynamoDB — the table this config creates.

Simulate a stuck lock:

```bash
terraform plan -lock-timeout=5s -var-file=dev.tfvars
```

**In production:** someone's apply crashed and left a lock behind. You confirm nobody is actually running, then:

```bash
terraform force-unlock <LOCK_ID>
```

**Never run that without checking first.** If someone really is mid-apply, breaking the lock corrupts state.

---

## Teardown

```bash
terraform destroy -var-file=dev.tfvars
docker compose down
```

---

## Interview answers these drills give you

**"How do you fix drift?"**
plan to see it → decide which side is right → update code and apply, or apply to revert.

**"A resource exists but Terraform wants to create it."**
Write the resource block, `terraform import`, plan until clean, then apply. Import only touches state.

**"How do you rename a resource without destroying it?"**
`moved` blocks. `state mv` is the older imperative way.

**"count vs for_each?"**
count addresses by index, so removing a middle element renumbers and recreates everything after it. for_each addresses by key, so unrelated resources are untouched.

**"How do you secure and back up state?"**
S3 with versioning and encryption, DynamoDB for locking, restricted IAM. Never in git — it holds plaintext values.

**"State file is corrupted."**
Restore the previous version from S3. That's what versioning is for. `state pull` and `state push` as a last resort.
