locals {
  azs                  = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
  enable_dns_hostnames = true
  enable_https         = false

  name            = "waf-analytics"
  base_name       = local.suffix != "" ? "${local.name}-${local.suffix}" : local.name
  suffix          = random_string.suffix.result
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  region          = "ap-southeast-2"
  vpc_cidr        = "10.0.0.0/16"

  tags = {
    Environment = "dev"
    Project     = "waf-analytics"
  }

  config_files = {
    "grafana/grafana.ini"                                        = "./grafana-configs/grafana/grafana.ini"
    "grafana/grafana.service"                                    = "./grafana-configs/grafana/grafana.service"
    "grafana/provisioning/datasources/datasources.yml"           = "./grafana-configs/grafana/provisioning/datasources/datasources.yml"
    "grafana/provisioning/dashboards/dashboard.yml"              = "./grafana-configs/grafana/provisioning/dashboards/dashboard.yml"
    "grafana/provisioning/dashboards/waf-logs.json"              = "./grafana-configs/grafana/provisioning/dashboards/waf-logs.json"
    "grafana/provisioning/dashboards/geomap-dashboard.json"      = "./grafana-configs/grafana/provisioning/dashboards/geomap-dashboard.json"
    "grafana/provisioning/dashboards/connection-monitoring.json" = "./grafana-configs/grafana/provisioning/dashboards/connection-monitoring.json"
    "grafana/provisioning/dashboards/waf-stats-dashboard.json"   = "./grafana-configs/grafana/provisioning/dashboards/waf-stats-dashboard.json"
    "grafana/provisioning/dashboards/waf-loki-dashboard.json"    = "./grafana-configs/grafana/provisioning/dashboards/waf-loki-dashboard.json"
    "promtail/config.yml"                                        = "./grafana-configs/promtail/config.yml"
    "loki/loki.yml"                                              = "./grafana-configs/loki/loki.yml"
    "data/country-coords.json"                                   = "./grafana-configs/data/country-coords.json"
    "waf-sync/waf-sync.service"                                  = "./grafana-configs/waf-sync/waf-sync.service"
    "waf-sync/waf-sync.timer"                                    = "./grafana-configs/waf-sync/waf-sync.timer"
    "config-sync/config-sync.timer"                              = "./grafana-configs/config-sync/config-sync.timer"
    "config-sync/config-sync.sh"                                 = "./grafana-configs/config-sync/config-sync.sh"
  }
}
