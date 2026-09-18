# ---------------------------------------------------------------------------
# Security groups
#
# Rules are separate resources on purpose. If you put the rules inline, the ALB
# SG references the app SG and the app SG references the ALB SG, and Terraform
# errors with "Cycle:". Splitting the rules out breaks the cycle.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public entry point"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "App instances"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.name}-app" }
}

# Anyone on the internet can hit the ALB on 80.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP from internet"
}

# The ALB may talk out to the app, on the app port only.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "To app targets"
}

# The app accepts traffic ONLY from the ALB's security group.
# Not from a CIDR. This is the pattern interviewers look for: no IP ranges,
# no 0.0.0.0/0 on the app tier, the SG itself is the identity.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  description                  = "App port from ALB"
}

# Outbound anywhere — this is what the NAT gateway serves.
# Needed for SSM Session Manager and package installs.
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound via NAT"
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]

  # An ALB requires at least two subnets in two different AZs. This is a hard
  # AWS rule, not a best practice. Pass one subnet and creation fails.
  subnets = [for s in aws_subnet.public : s.id]

  # An internet-facing ALB needs the VPC to already have an internet gateway.
  # Terraform can't see that relationship from the arguments, so on a fresh
  # apply it sometimes races and fails. Stating it explicitly fixes that.
  depends_on = [aws_internet_gateway.main]
}

resource "aws_lb_target_group" "app" {
  name        = "${var.name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # Give the instance a moment to drain instead of cutting connections.
  deregistration_delay = 10
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Registering the instance is a SEPARATE step from creating the target group.
# Forgetting this is the classic "ALB returns 503, target group is empty" bug.
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}
