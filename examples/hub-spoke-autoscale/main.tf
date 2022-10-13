
locals {
  prefix             = var.prefix != null && var.prefix != "" ? "${var.prefix}-" : ""
  vmseries_image_url = "https://www.googleapis.com/compute/v1/projects/paloaltonetworksgcp-public/global/images/${var.vmseries_image_name}"
}

# --------------------------------------------------------------------------------------------------------------------------------------------
# Create MGMT, UNTRUST, and TRUST VPC networks.  

# The VM-Series network interfaces are attached to UNTRUST (NIC0), MGMT (NIC1), and TRUST (NIC2) 
# The interfaces should always be in this order when interface-swap is applied.

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
      ranges      = var.mgmt_allow_ips
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

# Create a Cloud NAT in untrust VPC network to provide outbound internet connectivity. 
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
# Create bootstrap bucket for VM-Series

# Generate random password
# resource "random_string" "password" {
#   count            = (var.create_vmseries_password ? 1 : 0)
#   length           = 8
#   min_lower        = 1
#   min_upper        = 1
#   min_numeric      = 1
#   min_special      = 1
#   override_special = "!@#$%&*=+"
# }

# # Generate a petname for the user account.
# resource "random_pet" "username" {
#   count     = (var.create_vmseries_password ? 1 : 0)
#   length    = 2
#   separator = ""
# }

# Create the password's phash.
# module "create_phash" {
#   source                 = "terraform-google-modules/gcloud/google"
#   version                = "~> 3.0.1"
#   count                  = (var.create_vmseries_password ? 1 : 0)
#   platform               = "linux"
#   create_cmd_entrypoint  = "echo"
#   create_cmd_body        = "${random_string.password[0].result} | mkpasswd -m MD5 -S acfwlwlo -s | tr -d '\n' > ${abspath("${path.module}/bootstrap_files/phash.txt")}"
#   destroy_cmd_entrypoint = "rm"
#   destroy_cmd_body       = abspath("${path.module}/bootstrap_files/phash.txt")
# }

# Retrieve phash so we can apply it to bootstrap.template. 
# data "local_file" "read_phash" {
#   count    = (var.create_vmseries_password ? 1 : 0)
#   filename = "${path.module}/bootstrap_files/phash.txt"
#   depends_on = [
#     module.create_phash
#   ]
# }

# Retrieve the hub subnet ID.
data "google_compute_subnetwork" "trust" {
  self_link = module.vpc_trust.subnets_self_links[0]
  region    = var.region
}

# Apply changes to the bootstrap.template to reflect the built environment. 
data "template_file" "bootstrap" {
  template = file("bootstrap_files/bootstrap.template")
  vars = {
    trust_gateway  = data.google_compute_subnetwork.trust.gateway_address
    spoke1_cidr    = var.cidr_spoke1
    spoke2_cidr    = var.cidr_spoke2
    spoke1_vm1_ip  = cidrhost(var.cidr_spoke1, 10)
    spoke2_vm1_ip  = cidrhost(var.cidr_spoke2, 10)
   # username       = var.create_vmseries_password ? random_pet.username[0].id : "tempuser"
   # username_phash = var.create_vmseries_password ? data.local_file.read_phash[0].content : "$1$acfwlwlo$DbyCDMgVl22kNnaONS.5o1" // Unknown password for security purposes.  Delete tempuser after deployment.
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
    "bootstrap_files/init-cfg.txt"                               = "config/init-cfg.txt"
    "${local_file.bootstrap.filename}"                           = "config/bootstrap.xml"
    "bootstrap_files/content/panupv2-all-contents-8622-7593"     = "content/panupv2-all-contents-8622-7593"
    "bootstrap_files/content/panup-all-antivirus-4222-4735"      = "content/panup-all-antivirus-4222-4735"
    "bootstrap_files/content/panupv3-all-wildfire-703414-706774" = "content/panupv3-all-wildfire-703414-706774"
  }
}




# --------------------------------------------------------------------------------------------------------------------------------------------
# Create VM-Series Regional Managed Instance Group for autoscaling

# Create an IAM service account to assign to the regional instance template.
module "iam_service_account" {
  source             = "PaloAltoNetworks/vmseries-modules/google//modules/iam_service_account"
  service_account_id = "${local.prefix}vmseries-mig-sa"
}

module "vmseries" {
  source = "github.com/PaloAltoNetworks/terraform-google-vmseries-modules//modules/autoscale?ref=autoscale_regional_migs-update"

  region                 = var.region
  name                   = "${local.prefix}vmseries"
  use_regional_mig       = true
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
    ssh-keys                             = "admin:${file(var.public_key_path)}" # fileexists(var.public_key_path) ? "admin:${file(var.public_key_path)}" : ""
    #ssh-keys                            = fileexists(var.public_key_path) ? "admin:${file(var.public_key_path)}" : ""
  }

depends_on = [ 
  module.bootstrap
]

}





# --------------------------------------------------------------------------------------------------------------------------------------------
# Create Internal & External Network Load Balancers


# The internal LB distributes all egress traffic from the spoke networks to the VM-Series trust interfaces for inspection.
module "lb_internal" {
  source = "PaloAltoNetworks/vmseries-modules/google//modules/lb_internal"

  name       = "${local.prefix}vmseries-internal-lb"
  network    = module.vpc_trust.network_id
  subnetwork = module.vpc_trust.subnets_self_links[0]
  all_ports  = true

  backends = {
    backend1 = module.vmseries.regional_instance_group_id
  }

  allow_global_access = true
}

# The external LB distributes all internet inbound traffic to the VM-Series untrust interfaces for inpsection.
module "lb_external" {
  source = "PaloAltoNetworks/vmseries-modules/google//modules/lb_external"

  name                           = "${local.prefix}vmseries-external-lb"
  health_check_http_port         = 80
  health_check_http_request_path = "/"

  rules = {
    "rule1" = { all_ports = true }
  }

}




# --------------------------------------------------------------------------------------------------------------------------------------------
# Custom Monitoring Dashboard for VM-Series utilization metrics.

# If 'create_monitoring_dashboard' is set to true, a custom dashboard will be created to display the VM-Series utilization metrics.
resource "google_monitoring_dashboard" "dashboard" {
  count          = (var.create_monitoring_dashboard ? 1 : 0)
  dashboard_json = templatefile("${path.root}/bootstrap_files/dashboard.json.tpl", { dashboard_name = "VM-Series Metrics" })
  lifecycle {
    ignore_changes = [
      dashboard_json
    ]
  }
}