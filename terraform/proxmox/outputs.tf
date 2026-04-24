# Outputs das VMs criadas no Proxmox.
# Úteis para integração com o inventário Ansible e para referência rápida pós-apply.

output "k3s_server_ip" {
  description = "Endereço IP do nó control-plane do cluster K3s (via NetBox IPAM)"
  value       = netbox_ip_address.k3s_server.ip_address
}

output "k3s_server_vm_id" {
  description = "ID da VM do nó control-plane no Proxmox"
  value       = proxmox_virtual_environment_vm.k3s_server.vm_id
}

output "k3s_worker_cicd_ip" {
  description = "Endereço IP do nó worker dedicado a CI/CD (via NetBox IPAM)"
  value       = netbox_ip_address.k3s_worker_cicd.ip_address
}

output "k3s_worker_cicd_vm_id" {
  description = "ID da VM do nó worker CI/CD no Proxmox"
  value       = proxmox_virtual_environment_vm.k3s_worker_cicd.vm_id
}

output "ci_runner_ip" {
  description = "Endereço IP do nó executor de pipelines CI (via NetBox IPAM)"
  value       = netbox_ip_address.ci_runner.ip_address
}

output "ci_runner_vm_id" {
  description = "ID da VM do nó ci-runner no Proxmox"
  value       = proxmox_virtual_environment_vm.ci_runner.vm_id
}

output "all_vm_ips" {
  description = "Mapa com nome e IP de todas as VMs criadas pelo Terraform (via NetBox IPAM)"
  value = {
    k3s-server      = netbox_ip_address.k3s_server.ip_address
    k3s-worker-cicd = netbox_ip_address.k3s_worker_cicd.ip_address
    ci-runner       = netbox_ip_address.ci_runner.ip_address
  }
}

output "cluster_summary" {
  description = "Resumo do cluster K3s: control-plane e agentes"
  value = {
    control_plane = "k3s-server @ ${netbox_ip_address.k3s_server.ip_address}"
    agents = [
      "k3s-worker-cicd @ ${netbox_ip_address.k3s_worker_cicd.ip_address}",
      "ci-runner        @ ${netbox_ip_address.ci_runner.ip_address}",
      "notebook-i5      @ 192.168.1.65 (bare metal — não gerenciado pelo Terraform)",
      "raspberry-pi     @ 192.168.1.110 (bare metal — não gerenciado pelo Terraform)",
    ]
  }
}

# ---------------------------------------------------------------------------
# Outputs NetBox IPAM
# ---------------------------------------------------------------------------

output "netbox_vm_ids" {
  description = "IDs dos objetos VirtualMachine criados no NetBox"
  value = {
    k3s_server      = netbox_virtual_machine.k3s_server.id
    k3s_worker_cicd = netbox_virtual_machine.k3s_worker_cicd.id
    ci_runner       = netbox_virtual_machine.ci_runner.id
  }
}

output "netbox_allocated_ips" {
  description = "IPs alocados via NetBox IPAM para os nós do cluster"
  value = {
    k3s_server      = netbox_ip_address.k3s_server.ip_address
    k3s_worker_cicd = netbox_ip_address.k3s_worker_cicd.ip_address
    ci_runner       = netbox_ip_address.ci_runner.ip_address
  }
}
