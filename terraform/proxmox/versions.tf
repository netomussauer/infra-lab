# Declaração de versões obrigatórias do Terraform e dos providers utilizados.
# Fixar versões garante reprodutibilidade e evita quebras por atualizações automáticas.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }

    # Provider NetBox — integração com IPAM para eliminar IPs hardcoded
    # Documentação: https://registry.terraform.io/providers/e-breuninger/netbox/latest/docs
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 3.3"
    }
  }
}
