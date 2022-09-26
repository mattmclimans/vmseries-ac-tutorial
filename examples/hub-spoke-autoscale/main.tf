
locals {
  prefix             = var.prefix != null && var.prefix != "" ? "${var.prefix}-" : ""
  vmseries_image_url = "https://www.googleapis.com/compute/v1/projects/paloaltonetworksgcp-public/global/images/${var.vmseries_image_name}"
}

data "google_compute_zones" "main" {}


# --------------------------------------------------------------------------------------------------------------------------------------------
# Create MGMT, UNTRUST, and TRUST VPC networks.  
# --------------------------------------------------------------------------------------------------------------------------------------------
# The VM-Series network interfaces are attached to UNTRUST (NIC0), MGMT (NIC1), and TRUST (NIC2) 
# VPC networks.  The interfaces should always be in this order when interface-swap is applied.

module "vpc_mgmt" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 4.0"
  project_id   = var.project_id
  network_name = "${local.prefix}mgmt-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-mgmt"
      subnet_ip     = var.cidr_mgmt
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name        = "${local.prefix}vmseries-mgmt"
      direction   = "INGRESS"
      priority    = "100"
      description = "Allow ingress access to VM-Series management interface"
      ranges      = var.allowed_sources
      allow = [
        {
          protocol = "tcp"
          ports    = ["22", "443", "3978"]
        }
      ]
    }
  ]
}

module "vpc_untrust" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 4.0"
  project_id   = var.project_id
  network_name = "${local.prefix}untrust-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-untrust"
      subnet_ip     = var.cidr_untrust
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}ingress-all-untrust"
      direction = "INGRESS"
      priority  = "100"
      ranges    = ["0.0.0.0/0"]
      allow = [
        {
          protocol = "all"
          ports    = []
        }
      ]
    }
  ]
}

module "vpc_trust" {
  source                                 = "terraform-google-modules/network/google"
  version                                = "~> 4.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}trust-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-trust"
      subnet_ip     = var.cidr_trust
      subnet_region = var.region
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}ingress-all-trust"
      direction = "INGRESS"
      priority  = "100"
      ranges    = ["0.0.0.0/0"]
      allow = [
        {
          protocol = "all"
          ports    = []
        }
      ]
    }
  ]
}

#  Create a Cloud NAT in untrust VPC network to provide outbound internet connectivity. 
module "cloud_nat_untrust" {
  source        = "terraform-google-modules/cloud-nat/google"
  version       = "=1.2"
  name          = "${local.prefix}untrust-nat"
  router        = "${local.prefix}untrust-router"
  project_id    = var.project_id
  region        = var.region
  create_router = true
  network       = module.vpc_untrust.network_id
}



# --------------------------------------------------------------------------------------------------------------------------------------------
# Create VM-Series Regional Managed Instance Group for autoscaling
# --------------------------------------------------------------------------------------------------------------------------------------------

# Create an IAM service account to assign to the regional instance template.
module "iam_service_account" {
  source             = "PaloAltoNetworks/vmseries-modules/google//modules/iam_service_account"
  service_account_id = "${local.prefix}vmseries-mig-sa"
}

# Retrieve the hub subnet ID.
data "google_compute_subnetwork" "trust" {
  self_link = module.vpc_trust.subnets_self_links[0]
  region    = var.region
}

# Apply changes to the bootstrap.template to reflect the built environment. 
data "template_file" "bootstrap" {
  template = file("bootstrap_files/bootstrap.template")
  vars = {
    trust_gateway = data.google_compute_subnetwork.trust.gateway_address
    spoke1_cidr   = var.cidr_spoke1
    spoke2_cidr   = var.cidr_spoke2
    spoke1_vm1_ip = cidrhost(var.cidr_spoke1, 10)
    spoke2_vm1_ip = cidrhost(var.cidr_spoke2, 10)
  }
}

# Create the bootstrap.xml file.
resource "local_file" "bootstrap" {
  filename = "bootstrap_files/bootstrap.xml"
  content  = data.template_file.bootstrap.rendered
}

# Create a GCP storage bucket and upload the init-cfg.txt and bootstrap.xml to it.
module "bootstrap" {
  source          = "PaloAltoNetworks/vmseries-modules/google//modules/bootstrap"
  service_account = module.iam_service_account.email
  files = {
    "bootstrap_files/init-cfg.txt"  = "config/init-cfg.txt"
    "bootstrap_files/bootstrap.xml" = "config/bootstrap.xml"
  }

  depends_on = [
    local_file.bootstrap
  ]
}

module "autoscale" {
  source = "github.com/PaloAltoNetworks/terraform-google-vmseries-modules//modules/autoscale?ref=autoscale_regional_migs"
  # source = "/Users/mmclimans/Desktop/vmseries-tutorial/modules/autoscale"

  zones = {
    zone1 = data.google_compute_zones.main.names[0]
    zone2 = data.google_compute_zones.main.names[1]
  }
  region                 = var.region
  name                   = "${local.prefix}vmseries"
  use_regional_mig       = false
  min_vmseries_replicas  = var.vmseries_replica_minimum // min firewalls per zone.
  max_vmseries_replicas  = var.vmseries_replica_maximum // max firewalls per zone.
  image                  = local.vmseries_image_url
  create_pubsub_topic    = true
  target_pool_self_links = [module.lb_external.target_pool]
  scopes                 = ["https://www.googleapis.com/auth/cloud-platform"]
  service_account_email  = module.iam_service_account.email
  autoscaler_metrics     = var.autoscaler_metrics

  network_interfaces = [
    {
      subnetwork       = module.vpc_untrust.subnets_self_links[0]
      create_public_ip = false
    },
    {
      subnetwork       = module.vpc_mgmt.subnets_self_links[0]
      create_public_ip = true
    },
    {
      subnetwork       = module.vpc_trust.subnets_self_links[0]
      create_public_ip = false
    }
  ]

  metadata = {
    mgmt-interface-swap                  = "enable"
    vmseries-bootstrap-gce-storagebucket = module.bootstrap.bucket_name
    serial-port-enable                   = true
    ssh-keys                             = fileexists(var.public_key_path) ? "admin:${file(var.public_key_path)}" : ""
  }

  # metadata = {
  #   type                        = "dhcp-client"
  #   op-command-modes            = "mgmt-interface-swap"
  #   vm-auth-key                 = "878627735112242"
  #   panorama-server             = "20.124.7.65"
  #   dgname                      = "gcp-hub"
  #   tplname                     = "gcp-hub_stack"
  #   dhcp-send-hostname          = "yes"
  #   dhcp-send-client-id         = "yes"
  #   dhcp-accept-server-hostname = "yes"
  #   dhcp-accept-server-domain   = "yes"
  #   dns-primary                 = "169.254.169.254"
  #   dns-secondary               = "8.8.8.8"
  # }

  # named_ports = [
  #   {
  #     name = "http"
  #     port = "80"
  #   }
  # ]
}


# --------------------------------------------------------------------------------------------------------------------------------------------
# Create Internal & External Network Load Balancers
# --------------------------------------------------------------------------------------------------------------------------------------------

# The internal LB distributes all egress traffic from the spoke networks to the VM-Series trust interfaces for inspection.
module "lb_internal" {
  source = "PaloAltoNetworks/vmseries-modules/google//modules/lb_internal"

  name       = "${local.prefix}vmseries-internal-lb"
  network    = module.vpc_trust.network_id
  subnetwork = module.vpc_trust.subnets_self_links[0]
  all_ports  = true
  # backends = {
  #   backend1 = module.autoscale.regional_instance_group_id
  # }
  backends = {
    backend1 = module.autoscale.zone_instance_group_id["zone1"]
    backend2 = module.autoscale.zone_instance_group_id["zone2"]
  }
  allow_global_access = true
}

# The external LB distributes all internet inbound traffic to the VM-Series untrust interfaces for inpsection.
module "lb_external" {
  source = "PaloAltoNetworks/vmseries-modules/google//modules/lb_external"

  name = "${local.prefix}vmseries-external-lb"
  rules = {
    "rule1" = { port_range = 80 },
    "rule2" = { port_range = 22 }
  }

  health_check_http_port         = 80
  health_check_http_request_path = "/"
}

# --------------------------------------------------------------------------------------------------------------------------------------------
# Custom Monitoring Dashboard for VM-Series utilization metrics.
# --------------------------------------------------------------------------------------------------------------------------------------------

# If 'create_monitoring_dashboard' is set to true, a custom dashboard will be created to display the VM-Series utilization metrics.
resource "google_monitoring_dashboard" "dashboard" {
  count          = (var.create_monitoring_dashboard ? 1 : 0)
  dashboard_json = templatefile("${path.root}/bootstrap_files/dashboard.json.tpl", { dashboard_name = "VM-Series Metrics" })
}



# output instance_group_id_regional {
#   value = module.autoscale_regional.regional_instance_group_id
# }




# output instance_group_id_zonal {
#   value = module.autoscale.zone_instance_group_id
# }



# output pubsub_topic_id {
#   value = module.autoscale.pubsub_topic_id
# }

# output  pubsub_subscription_id {
#   value = module.autoscale.pubsub_subscription_id
# }

# output pubsub_subscription_iam_member_etag {
#   value = module.autoscale.pubsub_subscription_iam_member_etag
# }