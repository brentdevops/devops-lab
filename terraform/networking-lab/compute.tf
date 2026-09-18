# ---------------------------------------------------------------------------
# AMI
#
# Looked up at plan time instead of hardcoded, so the config is not pinned to
# one region and does not go stale.
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------------------
# Instance role — SSM Session Manager
#
# There is no SSH key and no bastion here. You get a shell on the private
# instance through Session Manager, which works by the instance dialling OUT
# to AWS over the NAT gateway. No inbound port is opened at all.
#
# That also makes it a live NAT test: break the NAT route and SSM stops
# connecting.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# An instance cannot be handed a role directly. It is handed an instance
# profile, which wraps the role. This exists for historical reasons and is a
# common "why does my instance have no permissions" cause.
resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app"
  role = aws_iam_role.app.name
}

# ---------------------------------------------------------------------------
# The app instance
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami           = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  # Private subnet. No public IP. The only way in is through the ALB.
  subnet_id                   = aws_subnet.private[local.azs[0]].id
  associate_public_ip_address = false

  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  # IMDSv2 only.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  # python3 ships with AL2023, so this needs no package install and therefore
  # no working NAT to boot. Keeps the NAT drill honest: the app comes up either
  # way, and only SSM and outbound traffic break.
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    mkdir -p /opt/site
    echo "ok" > /opt/site${var.health_check_path}
    echo "hello from $(hostname -f)" > /opt/site/index.html

    cat >/etc/systemd/system/labapp.service <<'UNIT'
    [Unit]
    Description=lab app
    After=network-online.target

    [Service]
    ExecStart=/usr/bin/python3 -m http.server ${var.app_port} --directory /opt/site
    Restart=always

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now labapp
  EOF

  # Changing user_data on an existing instance does nothing — user_data only
  # runs on first boot. This forces a replacement so the change actually lands.
  user_data_replace_on_change = true

  tags = { Name = "${var.name}-app" }
}
