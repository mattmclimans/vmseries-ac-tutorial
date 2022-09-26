output "external_lb_http" {
  description = "External load balancer's frontend URL that resolves to spoke1 web servers after VM-Series inspection."
  value       = "http://${module.lb_external.ip_addresses["rule1"]}"
}

output "external_lb_ssh" {
  description = "External load balancer's frontend address that opens SSH session to spoke2-vm1 after VM-Series inspection."
  value       = "ssh ${var.spoke_vm_user}@${module.lb_external.ip_addresses["rule2"]}"
}
