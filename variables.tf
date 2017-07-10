variable "aws_conf" {
  type = "map"
  default = {}
}

variable "vpc_conf" {
  type = "map"
  default = {}
}

variable "es_conf" {
  type = "map"
  default = {
    id = "es"
    version = "5.4.3"
    capacity = "3"
    internal = "true"
    http_port = "9200"
    transport_port = "9300"
    tls.http_port = "19200"
    tls.transport_port = "19300"
    tls.private_key = ".stunnel.key"
    tls.certificate = ".stunnel.pem"
  }
}

variable "subnet-type" {
  default = {
    "true" = "subnets_private"
    "false" = "subnets_public"
  }
}

variable "public_ip" {
  default = {
    "true" = "false"
    "false" = "true"
  }
}