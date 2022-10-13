project_id                  = "host-4502127"
public_key_path             = "~/.ssh/vmseries-tutorial.pub"
mgmt_allow_ips              = ["0.0.0.0/0"]
region                      = "us-central1"
create_spoke_networks       = true
create_vmseries_password    = true   # Should only be set to 'true' for non-production environments. 
vmseries_image_name         = "vmseries-flex-bundle2-1022h2"

# Optional for VM-Series tutorial.
cidr_mgmt                   = "10.0.0.0/28"
cidr_untrust                = "10.0.1.0/28"
cidr_trust                  = "10.0.2.0/28"
cidr_spoke1                 = "10.1.0.0/28"
cidr_spoke2                 = "10.2.0.0/28"

