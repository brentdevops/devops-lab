region            = "us-east-1"
name              = "netlab"
vpc_cidr          = "10.20.0.0/16"
instance_type     = "t3.micro"
app_port          = 8080
health_check_path = "/healthz"
