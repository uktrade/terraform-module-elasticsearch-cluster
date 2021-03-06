data "aws_ami" "es-ami" {
  most_recent = true
  name_regex = "ubuntu-xenial-16.04-amd64-server"
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
}

data "template_file" "es-cloudinit" {
  template = "${file("${path.module}/cloudinit.yml")}"

  vars {
    aws_region = "${var.vpc_conf["region"]}"
    aws_availability_zones = "${var.vpc_conf["availability_zones"]}"
    dns_zone_id = "${var.vpc_conf["zone_id"]}"
    cluster_id = "${var.es_conf["id"]}.${var.aws_conf["domain"]}"
    domain = "${var.aws_conf["domain"]}"
    es_version = "${var.es_conf["version"]}"
    es_discovery_sg = "${aws_security_group.es.id}"
    http_port = "${var.es_conf["http_port"]}"
    transport_port = "${var.es_conf["transport_port"]}"
    tls_http_port = "${var.es_conf["tls.http_port"]}"
    tls_key = "${replace(file(var.es_conf["tls.private_key"]), "\n", "\\n")}"
    tls_cert = "${replace(file(var.es_conf["tls.certificate"]), "\n", "\\n")}"
    cerebro_version = "${var.es_conf["cerebro.version"]}"
    cerebro_port = "${var.es_conf["cerebro.port"]}"
    auth_user = "${var.es_conf["id"]}"
    auth_pass = "${var.es_conf["auth"]}"
  }
}

resource "aws_launch_configuration" "es" {
  name_prefix = "${var.aws_conf["domain"]}-${var.es_conf["id"]}-"
  image_id = "${data.aws_ami.es-ami.id}"
  instance_type = "${var.aws_conf["instance_type"]}"
  key_name = "${var.aws_conf["key_name"]}"
  iam_instance_profile = "${aws_iam_instance_profile.node-profile.id}"
  security_groups = [
    "${var.vpc_conf["security_group"]}",
    "${aws_security_group.es.id}"
  ]
  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    delete_on_termination = true
  }
  ebs_block_device {
    device_name = "/dev/sdd"
    volume_type = "gp2"
    volume_size = "${var.es_conf["storage"]}"
    encrypted = true
    delete_on_termination = true
  }
  user_data = "${data.template_file.es-cloudinit.rendered}"
  associate_public_ip_address = "${lookup(var.public_ip, var.es_conf["internal"])}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "es" {
  name = "${var.aws_conf["domain"]}-${var.es_conf["id"]}"
  launch_configuration = "${aws_launch_configuration.es.name}"
  vpc_zone_identifier = ["${split(",", var.vpc_conf[lookup(var.subnet-type, var.es_conf["internal"])])}"]
  min_size = "${var.es_conf["capacity"]}"
  max_size = "${var.es_conf["capacity"]}"
  desired_capacity = "${var.es_conf["capacity"]}"
  wait_for_capacity_timeout = 0
  load_balancers = ["${aws_elb.es.id}"]

  tag {
    key = "Name"
    value = "${var.aws_conf["domain"]}-${var.es_conf["id"]}"
    propagate_at_launch = true
  }
  tag {
    key = "Stack"
    value = "${var.aws_conf["domain"]}"
    propagate_at_launch = true
  }
  tag {
    key = "clusterid"
    value = "${var.aws_conf["domain"]}"
    propagate_at_launch = true
  }
  tag {
    key = "svc"
    value = "es"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "es" {
  name = "${var.aws_conf["domain"]}-${var.es_conf["id"]}"
  vpc_id = "${var.vpc_conf["id"]}"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }

  ingress {
    from_port = "${var.es_conf["http_port"]}"
    to_port = "${var.es_conf["http_port"]}"
    protocol = "tcp"
    security_groups = ["${aws_security_group.es-elb.id}"]
  }

  ingress {
    from_port = "${var.es_conf["transport_port"]}"
    to_port = "${var.es_conf["transport_port"]}"
    protocol = "tcp"
    security_groups = ["${aws_security_group.es-elb.id}"]
  }

  ingress {
    from_port = "${var.es_conf["tls.http_port"]}"
    to_port = "${var.es_conf["tls.http_port"]}"
    protocol = "tcp"
    security_groups = ["${var.vpc_conf["security_group"]}"]
  }

  ingress {
    from_port = "${var.es_conf["cerebro.port"]}"
    to_port = "${var.es_conf["cerebro.port"]}"
    protocol = "tcp"
    security_groups = ["${var.vpc_conf["security_group"]}"]
  }

  tags {
    Name = "${var.aws_conf["domain"]}-${var.es_conf["id"]}"
    Stack = "${var.aws_conf["domain"]}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "es-elb" {
  name = "${var.aws_conf["domain"]}-${var.es_conf["id"]}-elb"
  vpc_id = "${var.vpc_conf["id"]}"

  ingress {
    from_port = "${var.es_conf["http_port"]}"
    to_port = "${var.es_conf["http_port"]}"
    protocol = "tcp"
    security_groups = ["${var.vpc_conf["security_group"]}"]
  }

  ingress {
    from_port = "${var.es_conf["cerebro.port"]}"
    to_port = "${var.es_conf["cerebro.port"]}"
    protocol = "tcp"
    security_groups = ["${var.vpc_conf["security_group"]}"]
  }

  tags {
    Name = "${var.aws_conf["domain"]}-${var.es_conf["id"]}-elb"
    Stack = "${var.aws_conf["domain"]}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "es" {
  name = "${element(split(".", var.aws_conf["domain"]), 0)}-${var.es_conf["id"]}-elb"
  subnets = ["${split(",", var.vpc_conf[lookup(var.subnet-type, var.es_conf["internal"])])}"]

  security_groups = [
    "${var.vpc_conf["security_group"]}",
    "${aws_security_group.es-elb.id}"
  ]

  listener {
    lb_port = "${var.es_conf["http_port"]}"
    lb_protocol = "https"
    instance_port = "${var.es_conf["tls.http_port"]}"
    instance_protocol = "https"
    ssl_certificate_id = "${var.vpc_conf["acm_certificate"]}"
  }

  listener {
    lb_port = "${var.es_conf["cerebro.port"]}"
    lb_protocol = "https"
    instance_port = "${var.es_conf["cerebro.port"]}"
    instance_protocol = "http"
    ssl_certificate_id = "${var.vpc_conf["acm_certificate"]}"
  }

  health_check {
    healthy_threshold = 5
    unhealthy_threshold = 2
    timeout = 2
    target = "TCP:${var.es_conf["tls.http_port"]}"
    interval = 10
  }

  connection_draining = true
  cross_zone_load_balancing = true
  internal = true

  tags {
    Stack = "${var.aws_conf["domain"]}"
    Name = "${var.aws_conf["domain"]}-${var.es_conf["id"]}-elb"
  }
}

resource "aws_route53_record" "es" {
   zone_id = "${var.vpc_conf["zone_id"]}"
   name = "${var.es_conf["id"]}.${var.aws_conf["domain"]}"
   type = "A"
   alias {
     name = "${aws_elb.es.dns_name}"
     zone_id = "${aws_elb.es.zone_id}"
     evaluate_target_health = false
   }

   lifecycle {
     create_before_destroy = true
   }
}
