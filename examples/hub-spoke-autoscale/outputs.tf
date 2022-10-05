output "EXTERNAL_LB_IP" {
  description = "External load balancer's forwarding rule address."
  value       = module.lb_external.ip_addresses["rule1"]
}

output "VMSERIES_UN" {
  value = var.create_vmseries_password ? random_pet.username[0].id : null
}

output "VMSERIES_PW" {
  value = var.create_vmseries_password ? random_string.password[0].result : null
}



# --------------------------------------------------------------------------------------------------------------------------------------------
/* 
 The module below runs a gcloud command to retrieve the public IP and outputs it 
 to the user's terminal window.  This makes it easy for the user to find the VM-Series mgmt IP.
 Retrieving the public IP from a managed instance group created with Terraform is complicated 
 because the compute instance is initiated outside of Terraform.  This workaround is easier.
*/ 
module "retrieve_public_ip" {
  source                 = "terraform-google-modules/gcloud/google"
  version                = "~> 3.0.1"
  platform               = "linux"
  create_cmd_entrypoint  = ""
  create_cmd_body        = "sleep 15 && gcloud compute instances list --format='value(EXTERNAL_IP)' | tr -d '\n' > ${abspath("${path.module}/bootstrap_files/public_ip.txt")}"
  destroy_cmd_entrypoint = "rm"
  destroy_cmd_body       = abspath("${path.module}/bootstrap_files/public_ip.txt")

  module_depends_on = [
    module.lb_internal  // Wait for internal LB because it is the last resource that is created.
  ]
}

# resource "null_resource" "retrieve_public_ip" {
#   provisioner "local-exec" {
#     command = "sleep 15 && gcloud compute instances list --format='value(EXTERNAL_IP)' | tr -d '\n' > ${abspath("${path.module}/bootstrap_files/public_ip.txt")}"
#   }

#   provisioner "local-exec" {
#     when = destroy
#     command = "rm ${abspath("${path.module}/bootstrap_files/public_ip.txt")}"
#   }
#   depends_on = [
#     module.lb_internal
#   ]
# }

# Retrieve public IPs so we output it to the terminal window.
data "local_file" "read_public_ip" {
  filename = "${path.module}/bootstrap_files/public_ip.txt"
  depends_on = [
    module.retrieve_public_ip
    #null_resource.retrieve_public_ip
  ]
}

# Output public IP.
output "VMSERIES_URL" {
  value = "https://${data.local_file.read_public_ip.content}"
}