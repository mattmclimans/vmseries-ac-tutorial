# output "TEST_THREAT" {
#   description = "A simple curl command to demonstrate threat prevention."
#   value       = "curl http://${module.lb_external.ip_addresses["rule1"]}:80/cgi-bin/../../../..//bin/cat%20/etc/passwd"
# }


output "EXTERNAL_LB_URL" {
  description = "External load balancer's frontend URL that resolves to spoke1 web servers after VM-Series inspection."
  value       = "http://${module.lb_external.ip_addresses["rule1"]}"
}

# output "JENKINS_URL" {
#   description = "External load balancer's frontend URL that resolves to spoke1 Jenkins server after VM-Series inspection."
#   value       = "http://${module.lb_external.ip_addresses["rule1"]}:8080"
# }

# output "SSH_TO_JUMP_VM" {
#   description = "External load balancer's frontend address that opens SSH session to spoke2-vm1 after VM-Series inspection."
#   value       = "ssh ${var.spoke_vm_user}@${module.lb_external.ip_addresses["rule1"]} -i ${trim(var.public_key_path, ".pub")}"
# }

# output "TEST_THREAT" {
#   description = "A harmless threat to launch from the Jump VM in spoke2 to the web application in spoke1."
#   value = "curl http://${cidrhost(var.cidr_spoke1, 10)}:80/cgi-bin/../../../..//bin/cat%20/etc/passwd"
# }



output "VMSERIES_MGT" {
  description = "VM-Series management interface address."
  value       = "https://${data.local_file.read_public_ip.content}"
}

output "VMSERIES_PW" {
  description = "VM-Series password."
  value       = var.create_vmseries_password ? random_string.password[0].result : null
}

output "VMSERIES_UN" {
  description = "VM-Series username."
  value       = var.create_vmseries_password ? random_pet.username[0].id : null
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
  create_cmd_body        = "sleep 30 && gcloud compute instances list --format='value(EXTERNAL_IP)' | tr -d '\n' > ${abspath("${path.module}/bootstrap_files/public_ip.txt")}"
  destroy_cmd_entrypoint = "rm"
  destroy_cmd_body       = abspath("${path.module}/bootstrap_files/public_ip.txt")

  module_depends_on = [
    module.lb_internal // Wait for internal LB because it is the last resource that is created.
  ]
}

# Retrieve public IPs so we output it to the terminal window.
data "local_file" "read_public_ip" {
  filename = "${path.module}/bootstrap_files/public_ip.txt"
  depends_on = [
    module.retrieve_public_ip
    #null_resource.retrieve_public_ip
  ]
}

