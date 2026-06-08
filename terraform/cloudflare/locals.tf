locals {
  tunnel_roles = {
    control = {
      name = "tgb-vn-news-control-ui"
    }
    data = {
      name = "tgb-vn-news-data-ui"
    }
  }

  ui_services = {
    airflow = {
      role   = "control"
      origin = "http://127.0.0.1:8090"
    }
    app = {
      role   = "control"
      origin = "http://127.0.0.1:3000"
    }
    api = {
      role   = "control"
      origin = "http://127.0.0.1:8000"
    }
    redpanda = {
      role   = "data"
      origin = "http://127.0.0.1:8083"
    }
    seaweed = {
      role   = "data"
      origin = "http://127.0.0.1:8888"
    }
  }

  services_by_role = {
    for role in keys(local.tunnel_roles) :
    role => {
      for name, service in local.ui_services :
      name => service if service.role == role
    }
  }

  ui_hostnames = {
    for name in keys(local.ui_services) : name => "${name}.${var.domain}"
  }
}
