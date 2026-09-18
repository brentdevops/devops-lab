# Networking Lab — ALB, NAT, public/private subnets

Real AWS. Real money, but small. Tear it down the same day.

## What this builds

```
              Internet
                 │
              [ IGW ]
                 │
   ┌─────────────┴─────────────┐
   │  public  10.20.0.0/24 (az-a)   public 10.20.1.0/24 (az-b)
   │     ALB lives in BOTH (2 AZs required)
   │     NAT gateway lives in az-a only
   └─────────────┬─────────────┘
                 │  0.0.0.0/0 → NAT
   ┌─────────────┴─────────────┐
   │  private 10.20.10.0/24 (az-a)  private 10.20.11.0/24 (az-b)
   │     EC2 t3.micro, no public IP, port 8080
   └───────────────────────────┘
```

Request path: **browser → ALB (:80) → target group → instance (:8080)**

Outbound path: **instance → NAT → IGW → internet**

## The one thing to remember

A subnet is not "public" or "private". Those are just tags in the Name field.
The **route table** is the difference:

| Subnet  | 0.0.0.0/0 route goes to |
| ------- | ----------------------- |
| public  | internet gateway        |
| private | NAT gateway             |

That's it. Same VPC, same kind of subnet, different route.

## Cost

| Resource       | Rate                        |
| -------------- | --------------------------- |
| ALB            | ~$0.023/hr + traffic        |
| NAT gateway    | ~$0.045/hr + $0.045/GB      |
| Elastic IP     | free while attached to NAT  |
| EC2 t3.micro   | free tier (750 hrs/month)   |

**~$0.07/hr, about $1.70 if you leave it up a full day.** Destroy when done.

---

## Run it

```bash
cd terraform/networking-lab
terraform init
terraform plan  -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

Apply takes ~4 minutes. Most of it is the NAT gateway.

Then:

```bash
terraform output alb_dns_name
curl http://$(terraform output -raw alb_dns_name)
```

First curl may 503 for ~30s while health checks pass. That is normal, and it's
also the exact thing you'll be asked about on the job.

Check target health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)
```

`"state": "healthy"` is what you want.

Get a shell on the private instance (no SSH key, no bastion):

```bash
aws ssm start-session --target $(terraform output -raw instance_id)
```

---

## Drill 1 — Health check fails

Break the security group. In `alb.tf`, change the app ingress rule port:

```hcl
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  from_port = 9999
  to_port   = 9999
```

```bash
terraform apply -var-file=dev.tfvars
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
```

Target goes `unhealthy`, reason `Health checks failed`. Curl the ALB → **503**.

**Diagnosis order, every time:**

1. Is the target registered at all? (empty target group = 503)
2. Is it `unhealthy` or `unused`?
3. `unhealthy` → can the ALB reach the port? SG.
4. SG is right → is the app actually listening? SSM in, `curl localhost:8080/healthz`.

**The tell:** 503 with an empty target group is a wiring problem. 503 with an
unhealthy target is a reachability or app problem.

Put the port back and apply.

---

## Drill 2 — NAT is broken

Delete the private route:

```bash
aws ec2 delete-route \
  --route-table-id $(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=netlab-private" \
    --query 'RouteTables[0].RouteTableId' --output text) \
  --destination-cidr-block 0.0.0.0/0
```

Now:

```bash
aws ssm start-session --target $(terraform output -raw instance_id)
```

Hangs, then fails. The SSM agent reaches AWS by dialling **out**. No route out,
no session.

But `curl http://$(terraform output -raw alb_dns_name)` still works — inbound
through the ALB never touches the NAT.

**The tell:** inbound works, outbound doesn't → NAT or private route table.
Inbound broken, outbound fine → ALB, target group, or security group.

Fix it — and note this is also a drift exercise:

```bash
terraform plan -var-file=dev.tfvars   # plan wants to re-add the route
terraform apply -var-file=dev.tfvars
```

---

## Drill 3 — ALB needs two AZs

In `alb.tf`, pin the ALB to one subnet:

```hcl
subnets = [aws_subnet.public[local.azs[0]].id]
```

```bash
terraform apply -var-file=dev.tfvars
```

```
ValidationError: At least two subnets in two different Availability Zones must be specified
```

**The tell:** this is a hard AWS constraint, not a quota you can raise. An ALB
is a set of nodes, one per AZ. One AZ means no redundancy, so AWS refuses.

Revert.

---

## Drill 4 — Empty target group

```bash
terraform state rm aws_lb_target_group_attachment.app

aws elbv2 deregister-targets \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --targets Id=$(terraform output -raw instance_id)
```

```bash
curl -i http://$(terraform output -raw alb_dns_name)
```

**503 Service Temporarily Unavailable.** The ALB exists, the listener exists,
there is simply nothing to forward to.

```bash
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
# TargetHealthDescriptions: []
```

Recover:

```bash
terraform apply -var-file=dev.tfvars
```

**Real-world version:** an autoscaling group was never attached to the target
group. The ALB is fine, the instances are fine, nothing connects them.

---

## Teardown

```bash
terraform destroy -var-file=dev.tfvars
```

Confirm nothing is left running:

```bash
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayId'
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
```

Both should come back empty. **NAT gateways bill whether or not you use them** —
this is the single most common surprise bill in AWS.

---

## Interview answers this gives you

**"What makes a subnet private?"**
Nothing about the subnet. Its route table sends 0.0.0.0/0 to a NAT gateway
instead of an internet gateway.

**"Walk me through a request to an app in a private subnet."**
DNS resolves the ALB name to ALB node IPs in the public subnets. The ALB
listener on 80 forwards to a target group. The target group holds the instance
on 8080 in a private subnet. The app's SG allows 8080 from the ALB's SG. The
reply goes back the same way. The instance never has a public IP.

**"Why does an ALB need two subnets?"**
It places a node in each AZ you give it. Two AZs is a hard minimum for
redundancy; AWS rejects one.

**"ALB returns 503. Where do you look?"**
Target health first. Empty target group means nothing is registered — a wiring
problem. Unhealthy targets mean the health check is failing — check the SG
allows the ALB on the app port, then check the app is actually listening on
that port and path.

**"Instance can't reach the internet."**
Public IP, or a NAT gateway plus a private route table with 0.0.0.0/0 pointing
at it. Check the route table before anything else. Also check the NAT is in a
public subnet — a NAT in a private subnet has no path out either.

**"Security group vs NACL?"**
SG is stateful, attached to the instance/ENI, allow rules only, and can
reference another SG. NACL is stateless, attached to the subnet, has allow and
deny, and is evaluated by rule number. If return traffic is being dropped, it's
a NACL, because an SG would have allowed it automatically.

**"How do you get a shell on a private instance?"**
SSM Session Manager. The agent dials out through the NAT, so no inbound port
and no bastion. Needs the instance profile with AmazonSSMManagedInstanceCore.

**"Why one NAT and not one per AZ?"**
Cost. One NAT is a single point of failure and cross-AZ data charges; one per
AZ is the production answer. For a lab, one.
