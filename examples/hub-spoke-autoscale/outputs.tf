# output "TEST-INBOUND-THREAT" {
#   description = "A simple curl command to demonstrate threat prevention."
#   value       = "curl http://${module.lb_external.ip_addresses["rule1"]}:80/cgi-bin/../../../..//bin/cat%20/etc/passwd"
# }

# output "SSH-TO-SPOKE2-VM" {
#   description = "External load balancer's frontend address that opens SSH session to spoke2-vm1 after VM-Series inspection."
#   value       = "ssh ${var.spoke_vm_user}@${module.lb_external.ip_addresses["rule1"]} -i ${trim(var.public_key_path, ".pub")}"
# }

# output "JENKINS-URL" {
#   description = "External load balancer's frontend URL that resolves to spoke1 web servers after VM-Series inspection."
#   value   = "http://${module.lb_external.ip_addresses["rule1"]}:8080"
# }

output "EXTERNAL_LB_IP" {
  description = "External load balancer's forwarding rule address."
  value       = module.lb_external.ip_address["rule1"]
}