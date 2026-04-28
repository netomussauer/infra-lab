# Integração com NetBox IPAM — source of truth para todos os IPs do laboratório.
#
# Este arquivo declara no NetBox:
#   - Organização: site, tenant, tag
#   - Cluster Proxmox como virtual cluster
#   - Prefixos de rede (LAN gerenciamento, MetalLB pool, K3s pod/service CIDR)
#   - Endereços IP de todas as VMs e hosts físicos do lab
#   - Objetos VirtualMachine para as VMs gerenciadas pelo Terraform
#
# Referência do provider: https://registry.terraform.io/providers/e-breuninger/netbox/latest/docs
#
# Ordem de dependência:
#   site/tenant/tag → cluster → prefixos → ip_addresses → virtual_machines

# ---------------------------------------------------------------------------
# Organização — tag, site e tenant do laboratório
# ---------------------------------------------------------------------------

# Tag aplicada a todos os recursos do laboratório no NetBox
resource "netbox_tag" "lab" {
  name = "lab"
}

# Site representa a localização física do laboratório (home lab)
resource "netbox_site" "lab_home" {
  name   = "lab-home"
  status = "active"
}

# Tenant agrupa todos os recursos do lab sob uma unidade administrativa
resource "netbox_tenant" "lab" {
  name = "lab"
}

# ---------------------------------------------------------------------------
# Cluster Proxmox — representa o hypervisor onde as VMs são criadas
# ---------------------------------------------------------------------------

# Tipo de cluster: Proxmox VE (utilizado para categorizar o cluster no NetBox)
resource "netbox_cluster_type" "proxmox" {
  name = "Proxmox VE"
}

# Cluster físico do laboratório — associado ao site e ao tenant
resource "netbox_cluster" "proxmox_lab" {
  name            = "proxmox-lab"
  cluster_type_id = netbox_cluster_type.proxmox.id
  site_id         = netbox_site.lab_home.id
  tenant_id       = netbox_tenant.lab.id
}

# ---------------------------------------------------------------------------
# Prefixos de rede — documentam todos os blocos de endereçamento do lab
# ---------------------------------------------------------------------------

# Rede principal do laboratório — toda a comunicação dos hosts físicos e VMs
resource "netbox_prefix" "management" {
  prefix      = "192.168.1.0/24"
  status      = "active"
  site_id     = netbox_site.lab_home.id
  description = "LAN gerenciamento lab"
}

# Pool de IPs reservado para serviços MetalLB LoadBalancer no cluster K3s
# /27 cobre 192.168.1.192–223, acomodando os IPs .200–.210 alocados aos serviços
resource "netbox_prefix" "metallb_pool" {
  prefix      = "192.168.1.192/27"
  status      = "active"
  site_id     = netbox_site.lab_home.id
  description = "MetalLB LoadBalancer pool"

  depends_on = [netbox_prefix.management]
}

# CIDR interno dos Pods do K3s (Flannel VXLAN) — roteamento apenas dentro do cluster
resource "netbox_prefix" "k3s_pods" {
  prefix      = "10.42.0.0/16"
  status      = "active"
  description = "K3s Pod CIDR (Flannel VXLAN)"
}

# CIDR interno dos Services do K3s — ClusterIPs alocados nesta faixa
resource "netbox_prefix" "k3s_services" {
  prefix      = "10.43.0.0/16"
  status      = "active"
  description = "K3s Service CIDR"
}

# ---------------------------------------------------------------------------
# Endereços IP — nós do cluster K3s (VMs Proxmox)
# ---------------------------------------------------------------------------
# Os IPs abaixo são registrados no NetBox e referenciados pelo main.tf,
# eliminando valores hardcoded na configuração do cloud-init das VMs.

# IP do nó control-plane do K3s
resource "netbox_ip_address" "k3s_server" {
  ip_address  = "192.168.1.30/24"
  status      = "active"
  description = "k3s-server (control-plane)"

  depends_on = [netbox_prefix.management]
}

# IP do nó worker dedicado a pipelines CI/CD
resource "netbox_ip_address" "k3s_worker_cicd" {
  ip_address  = "192.168.1.31/24"
  status      = "active"
  description = "k3s-worker-cicd"

  depends_on = [netbox_prefix.management]
}

# IP do nó executor de pipelines CI (GitLab Runner / GitHub Actions)
resource "netbox_ip_address" "ci_runner" {
  ip_address  = "192.168.1.32/24"
  status      = "active"
  description = "ci-runner"

  depends_on = [netbox_prefix.management]
}

# ---------------------------------------------------------------------------
# Endereços IP — hosts físicos (bare metal, não gerenciados pelo Terraform)
# ---------------------------------------------------------------------------
# Documentação dos IPs fixos dos equipamentos físicos do laboratório.
# Estes hosts são registrados no NetBox para visibilidade completa do IPAM.

# Host Proxmox — notebook i7 que hospeda o hypervisor e as VMs
resource "netbox_ip_address" "proxmox_host" {
  ip_address  = "192.168.1.20/24"
  status      = "active"
  description = "notebook-i7 (Proxmox host)"

  depends_on = [netbox_prefix.management]
}

# Notebook i5 — nó worker bare metal para workloads de monitoring
resource "netbox_ip_address" "notebook_i5" {
  ip_address  = "192.168.1.65/24"
  status      = "active"
  description = "notebook-i5 (k3s monitoring worker)"

  depends_on = [netbox_prefix.management]
}

# Raspberry Pi — nó worker bare metal ARMv7 para workloads de edge
resource "netbox_ip_address" "raspberry_pi" {
  ip_address  = "192.168.1.110/24"
  status      = "active"
  description = "raspberry-pi (k3s edge worker, ARMv7)"

  depends_on = [netbox_prefix.management]
}

# NAS — servidor de armazenamento compartilhado via NFS
resource "netbox_ip_address" "nas" {
  ip_address  = "192.168.1.112/24"
  status      = "active"
  description = "NAS Storage"

  depends_on = [netbox_prefix.management]
}

# VM do NetBox IPAM — o próprio serviço que estamos configurando
resource "netbox_ip_address" "netbox_vm" {
  ip_address  = "192.168.1.72/24"
  status      = "active"
  description = "NetBox IPAM VM"

  depends_on = [netbox_prefix.management]
}

# BookStack — wiki / documentação interna do laboratório
resource "netbox_ip_address" "bookstack" {
  ip_address  = "192.168.1.76/24"
  status      = "active"
  description = "BookStack (wiki interna do lab)"

  depends_on = [netbox_prefix.management]
}

# HomeAssistant — automação residencial
resource "netbox_ip_address" "homeassistant" {
  ip_address  = "192.168.1.107/24"
  status      = "active"
  description = "HomeAssistant (automação residencial)"

  depends_on = [netbox_prefix.management]
}

# ---------------------------------------------------------------------------
# Endereços IP — serviços MetalLB LoadBalancer
# ---------------------------------------------------------------------------
# IPs estáticos atribuídos pelo MetalLB a cada serviço Kubernetes exposto.
# Devem estar fora do pool DHCP do roteador doméstico.

# IP do serviço LoadBalancer do Gitea (Git server auto-hospedado)
resource "netbox_ip_address" "lb_gitea" {
  ip_address  = "192.168.1.200/27"
  status      = "active"
  description = "MetalLB — Gitea"

  depends_on = [netbox_prefix.metallb_pool]
}

# IP do serviço LoadBalancer do Harbor (registry de imagens OCI)
resource "netbox_ip_address" "lb_harbor" {
  ip_address  = "192.168.1.201/27"
  status      = "active"
  description = "MetalLB — Harbor"

  depends_on = [netbox_prefix.metallb_pool]
}

# IP do serviço LoadBalancer do ArgoCD (GitOps / CD)
resource "netbox_ip_address" "lb_argocd" {
  ip_address  = "192.168.1.202/27"
  status      = "active"
  description = "MetalLB — ArgoCD"

  depends_on = [netbox_prefix.metallb_pool]
}

# IP do serviço LoadBalancer do Tekton EventListener (gatilhos de pipeline)
resource "netbox_ip_address" "lb_tekton" {
  ip_address  = "192.168.1.203/27"
  status      = "active"
  description = "MetalLB — Tekton EventListener"

  depends_on = [netbox_prefix.metallb_pool]
}

# IP do serviço LoadBalancer do Grafana (observabilidade / dashboards)
resource "netbox_ip_address" "lb_grafana" {
  ip_address  = "192.168.1.210/27"
  status      = "active"
  description = "MetalLB — Grafana"

  depends_on = [netbox_prefix.metallb_pool]
}

# ---------------------------------------------------------------------------
# VirtualMachines no NetBox — espelham as VMs criadas pelo Terraform no Proxmox
# ---------------------------------------------------------------------------
# Cada VM registrada aqui representa um objeto virtual_machine no NetBox,
# associado ao cluster Proxmox e com IP primário vinculado.
# As VMs dependem dos ip_address acima para garantir ordem de criação correta.

# VM control-plane do K3s
resource "netbox_virtual_machine" "k3s_server" {
  name         = "k3s-server"
  cluster_id   = netbox_cluster.proxmox_lab.id
  tenant_id    = netbox_tenant.lab.id
  vcpus        = "2.00"
  memory_mb    = 4096
  disk_size_mb = 40960
  status       = "active"
  tags         = [netbox_tag.lab.name]
  comments     = "K3s control-plane. IP: 192.168.1.30. Gerenciado pelo Terraform."
}

# VM worker K3s dedicada a pipelines CI/CD
resource "netbox_virtual_machine" "k3s_worker_cicd" {
  name         = "k3s-worker-cicd"
  cluster_id   = netbox_cluster.proxmox_lab.id
  tenant_id    = netbox_tenant.lab.id
  vcpus        = "4.00"
  memory_mb    = 6144
  disk_size_mb = 61440
  status       = "active"
  tags         = [netbox_tag.lab.name]
  comments     = "K3s worker CI/CD. IP: 192.168.1.31. Gerenciado pelo Terraform."
}

# VM executor de pipelines CI
resource "netbox_virtual_machine" "ci_runner" {
  name         = "ci-runner"
  cluster_id   = netbox_cluster.proxmox_lab.id
  tenant_id    = netbox_tenant.lab.id
  vcpus        = "2.00"
  memory_mb    = 4096
  disk_size_mb = 40960
  status       = "active"
  tags         = [netbox_tag.lab.name]
  comments     = "Executor de pipelines CI (Tekton runner). IP: 192.168.1.32. Gerenciado pelo Terraform."
}
