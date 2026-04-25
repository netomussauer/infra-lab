# Variáveis de entrada do módulo Proxmox.
# Todas as variáveis sensíveis (token, chave SSH) devem ser fornecidas via
# arquivo terraform.tfvars (nunca comitado) ou variáveis de ambiente TF_VAR_*.

variable "proxmox_api_url" {
  description = "URL completa da API do Proxmox VE (incluindo /api2/json)"
  type        = string
  default     = "https://192.168.1.20:8006/api2/json"
}

variable "proxmox_api_token_id" {
  description = "ID do token de API do Proxmox no formato 'usuario@realm!nome-do-token'"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Segredo (UUID) do token de API do Proxmox"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Chave pública SSH que será injetada via cloud-init no usuário labadmin de todas as VMs"
  type        = string
  sensitive   = true
}

variable "vm_template_id" {
  description = "ID do template Ubuntu 22.04 cloud-init no Proxmox (criado previamente com virt-customize)"
  type        = number
  default     = 9000
}

variable "lab_network" {
  description = "Rede CIDR do laboratório home-lab"
  type        = string
  default     = "192.168.1.0/24"
}

variable "proxmox_node" {
  description = "Nome do nó Proxmox onde as VMs serão criadas"
  type        = string
  default     = "notebook-i7"
}

variable "vm_storage" {
  description = "Storage do Proxmox onde os discos das VMs serão alocados"
  type        = string
  default     = "local-lvm"
}

variable "vm_bridge" {
  description = "Bridge de rede do Proxmox para as interfaces das VMs"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Gateway padrão da rede do laboratório"
  type        = string
  default     = "192.168.1.254"
}

variable "dns_servers" {
  description = "Lista de servidores DNS para as VMs"
  type        = list(string)
  default     = ["192.168.1.254", "8.8.8.8"]
}

# ---------------------------------------------------------------------------
# NetBox IPAM
# ---------------------------------------------------------------------------

variable "netbox_url" {
  description = "URL base da API do NetBox — usar https:// pois o serviço expõe TLS na porta 443 com certificado autoassinado"
  type        = string
  default     = "https://192.168.1.72"
}

variable "netbox_token" {
  description = "Token de autenticação da API do NetBox"
  type        = string
  sensitive   = true
}
