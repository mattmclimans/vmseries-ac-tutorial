# --------------------------------------------------------------------------------------------------------------------------------------------
# Create Spoke VPC networks

module "vpc_spoke1" {
  source                                 = "terraform-google-modules/network/google"
  count                                  = (var.create_spoke_networks ? 1 : 0)
  version                                = "~> 4.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}spoke1-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-spoke1"
      subnet_ip     = var.cidr_spoke1
      subnet_region = var.region
    }
  ]

  routes = [
    {
      name              = "${local.prefix}spoke1-to-ilbnh"
      description       = "Default route to VM-Series NGFW"
      destination_range = "0.0.0.0/0"
      next_hop_ilb      = module.lb_internal.address
      #tags             = "egress-inet"
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}allow-all-spoke1"
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

module "vpc_spoke2" {
  source                                 = "terraform-google-modules/network/google"
  count                                  = (var.create_spoke_networks ? 1 : 0)
  version                                = "~> 4.0"
  project_id                             = var.project_id
  network_name                           = "${local.prefix}spoke2-vpc"
  routing_mode                           = "GLOBAL"
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = "${local.prefix}${var.region}-spoke2"
      subnet_ip     = var.cidr_spoke2
      subnet_region = var.region
    }
  ]

  routes = [
    {
      name              = "${local.prefix}spoke2-to-ilbnh"
      description       = "Default route to VM-Series NGFW"
      destination_range = "0.0.0.0/0"
      next_hop_ilb      = module.lb_internal.address
      #next_hop_internet = "true"
      #tags             = "egress-inet"
    }
  ]

  firewall_rules = [
    {
      name      = "${local.prefix}allow-all-spoke2"
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




# --------------------------------------------------------------------------------------------------------------------------------------------
# Create VPC peering connections between spoke networks and the trust network

resource "google_compute_network_peering" "spoke1_to_trust" {
  count        = (var.create_spoke_networks ? 1 : 0)
  name         = "${local.prefix}spoke1-to-trust"
  network      = module.vpc_spoke1[0].network_id
  peer_network = module.vpc_trust.network_id
}

resource "google_compute_network_peering" "trust_to_spoke1" {
  count        = (var.create_spoke_networks ? 1 : 0)
  name         = "${local.prefix}trust-to-spoke1"
  network      = module.vpc_trust.network_id
  peer_network = module.vpc_spoke1[0].network_id
}


resource "google_compute_network_peering" "spoke2_to_trust" {
  count        = (var.create_spoke_networks ? 1 : 0)
  name         = "${local.prefix}spoke2-to-trust"
  network      = module.vpc_spoke2[0].network_id
  peer_network = module.vpc_trust.network_id
}

resource "google_compute_network_peering" "trust_to_spoke2" {
  count        = (var.create_spoke_networks ? 1 : 0)
  name         = "${local.prefix}trust-to-spoke2"
  network      = module.vpc_trust.network_id
  peer_network = module.vpc_spoke2[0].network_id
}




# --------------------------------------------------------------------------------------------------------------------------------------------
# Create Spoke VM Ubuntu instances for testing inspection flows

resource "google_compute_instance" "spoke1_vm" {
  count                     = (var.create_spoke_networks ? 1 : 0)
  name                      = "${local.prefix}spoke1-vm${count.index + 1}"
  machine_type              = "n2-standard-2"
  zone                      = data.google_compute_zones.main.names[0]
  can_ip_forward            = false
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = fileexists(var.public_key_path) ? "${var.spoke_vm_user}:${file(var.public_key_path)}" : ""
  }

  network_interface {
    subnetwork = module.vpc_spoke1[0].subnets_self_links[0]
    network_ip = cidrhost(var.cidr_spoke1, 10)
  }

  boot_disk {
    initialize_params {
      image = "https://www.googleapis.com/compute/v1/projects/panw-gcp-team-testing/global/images/ubuntu-2004-lts-jenkins-key"
    }
  }

  service_account {
    scopes = var.spoke_vm_scopes
  }
}

resource "google_compute_instance" "spoke2_vm1" {
  count                     = (var.create_spoke_networks ? 1 : 0)
  name                      = "${local.prefix}spoke2-vm1"
  machine_type              = "f1-micro"
  zone                      = data.google_compute_zones.main.names[0]
  can_ip_forward            = false
  allow_stopping_for_update = true

  metadata = {
    serial-port-enable = true
    ssh-keys           = fileexists(var.public_key_path) ? "${var.spoke_vm_user}:${file(var.public_key_path)}" : ""
  }

  network_interface {
    subnetwork = module.vpc_spoke2[0].subnets_self_links[0]
    network_ip = cidrhost(var.cidr_spoke2, 10)
  }

  boot_disk {
    initialize_params {
      image = "https://www.googleapis.com/compute/v1/projects/panw-gcp-team-testing/global/images/ubuntu-2004-lts-apache-key"
      #image = var.spoke_vm_image
    }
  }

  service_account {
    scopes = var.spoke_vm_scopes
  }
}