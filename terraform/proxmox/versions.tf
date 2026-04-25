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
    # >= 5.0.0 obrigatório: v5.x corrige bug de TextConsumer (issues/263) e
    # renomeia disk_size_gb → disk_size_mb; vcpus passou a ser String ("2.00")
    netbox = {
      source  = "e-breuninger/netbox"
      version = ">= 5.0.0"
    }
  }
}
