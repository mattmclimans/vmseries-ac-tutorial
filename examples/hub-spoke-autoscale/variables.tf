variable "project_id" {
  description = "GCP Project ID"
  default     = null
  type        = string
}

variable "region" {
  description = "GCP Region"
  default     = "us-east1"
  type        = string
}

variable "public_key_path" {
  description = "Local path to public SSH key. To generate the key pair use `ssh-keygen -t rsa -C admin -N '' -f id_rsa`  If you do not have a public key, run `ssh-keygen -f ~/.ssh/demo-key -t rsa -C admin`"
  default     = "~/.ssh/gcp-demo.pub"
}

variable "vmseries_image_name" {
  description = "Name of the VM-Series image within the paloaltonetworksgcp-public project.  To list available images, run: `gcloud compute images list --project paloaltonetworksgcp-public --no-standard-images`. If you are using a custom image in a different project, please update `local.vmseries_iamge_url` in `main.tf`."
  default     = "vmseries-flex-byol-1014"
  type        = string
}

variable "vmseries_replica_minimum" {
  description = "The max number of firewalls to run in each region."
  default     = 2
  type        = number
}

variable "vmseries_replica_maximum" {
  description = "The minimum number of firewalls to run in each region."
  default     = 1
  type        = number
}

variable "prefix" {
  description = "Prefix to GCP resource names, an arbitrary string"
  default     = null
  type        = string
}

variable "autoscaler_metrics" {
  description = <<-EOF
  The map with the keys being metrics identifiers (e.g. custom.googleapis.com/VMSeries/panSessionUtilization).
  Each of the contained objects has attribute `target` which is a numerical threshold for a scale-out or a scale-in.
  Each zonal group grows until it satisfies all the targets.  Additional optional attribute `type` defines the 
  metric as either `GAUGE` (the default), `DELTA_PER_SECOND`, or `DELTA_PER_MINUTE`. For full specification, see 
  the `metric` inside the [provider doc](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_autoscaler).
  EOF
  default = {
    "custom.googleapis.com/VMSeries/panSessionActive" = {
      target = 100
    }
  }
}


variable "allowed_sources" {
  description = "A list of IP addresses to be added to the management network's ingress firewall rule. The IP addresses will be able to access to the VM-Series management interface."
  type        = list(string)
  default     = null
}

variable "cidr_mgmt" {
  description = "The CIDR range of the management subnetwork."
  type        = string
  default     = null
}

variable "cidr_untrust" {
  description = "The CIDR range of the untrust subnetwork."
  type        = string
  default     = null
}

variable "cidr_trust" {
  description = "The CIDR range of the trust subnetwork."
  type        = string
  default     = null
}

variable "create_monitoring_dashboard" {
  description = "Set to 'true' to create a custom Google Cloud Monitoring dashboard for VM-Series metrics."
  type        = bool
  default     = true
}

variable "create_spoke_networks" {
  description = <<-EOF
  Set to 'true' to create two spoke networks.  The spoke networks will be connected to the hub network via VPC
  Peering and each network will have a single Ubuntu instance for testing inspection flows. 
  Set to 'false' to skip spoke network creation. 
  EOF
  type        = bool
  default     = false
}


variable "cidr_spoke1" {
  description = "The CIDR range of the management subnetwork."
  type        = string
  default     = null
}

variable "cidr_spoke2" {
  description = "The CIDR range of the spoke1 subnetwork."
  type        = string
  default     = null
}

variable "spoke_vm_type" {
  description = "The GCP machine type for the compute instances in the spoke networks."
  type        = string
  default     = "f1-micro"
}

variable "spoke_vm_image" {
  description = "The image path for the compute instances deployed in the spoke networks."
  type        = string
  default     = "https://www.googleapis.com/compute/v1/projects/panw-gcp-team-testing/global/images/ubuntu-2004-lts-apache"
}

variable "spoke_vm_user" {
  description = "The username for the compute instance in the spoke networks."
  type        = string
  default     = "paloalto"
}

variable "spoke_vm_scopes" {
  description = "A list of service scopes. Both OAuth2 URLs and gcloud short names are supported. To allow full access to all Cloud APIs, use the cloud-platform"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring.write"
  ]
}
