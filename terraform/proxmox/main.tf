# Infraestrutura do laboratório home-lab no Proxmox VE.
# Cria três VMs via clone de template cloud-init para compor o cluster K3s.
#
# VMs criadas:
#   - k3s-server      (VM ID 200): nó control-plane do K3s
#   - k3s-worker-cicd (VM ID 201): nó worker dedicado a CI/CD
#   - ci-runner       (VM ID 202): nó worker para execução de pipelines
#
# Pré-requisito: template Ubuntu 22.04 cloud-init criado no Proxmox com ID 9000.
# Referência: https://registry.terraform.io/providers/bpg/proxmox/latest/docs

# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"

  # Aceitar certificado auto-assinado do Proxmox em ambiente de laboratório.
  # Em produção, substitua por um certificado válido e remova esta opção.
  insecure = true

  ssh {
    agent    = true
    username = "root"
  }
}

# Provider NetBox — lê e registra IPs/VMs no IPAM antes de provisionar no Proxmox.
# Os recursos do NetBox são declarados em netbox.tf; os IPs alocados lá são
# referenciados aqui para eliminar valores hardcoded no cloud-init das VMs.
provider "netbox" {
  server_url           = var.netbox_url
  api_token            = var.netbox_token
  allow_insecure_https = true
}

# ---------------------------------------------------------------------------
# Locals — tags e configurações compartilhadas
# ---------------------------------------------------------------------------

locals {
  # Tags obrigatórias aplicadas a todas as VMs do laboratório
  common_tags = ["lab", "k3s", "home-lab"]

  # Configuração de cloud-init compartilhada entre as VMs
  cloud_init_user = "labadmin"

  # DNS em formato de string para o cloud-init
  dns_servers = join(" ", var.dns_servers)
}

# ---------------------------------------------------------------------------
# VM: k3s-server — control-plane do cluster K3s
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "k3s_server" {
  name        = "k3s-server"
  description = "Nó control-plane do cluster K3s. Gerenciado pelo Terraform."
  node_name   = var.proxmox_node
  vm_id       = 200

  # Clonar a partir do template Ubuntu 22.04 cloud-init
  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # Recursos de computação
  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  # Disco principal — sistema operacional
  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  # Interface de rede na bridge principal do laboratório
  network_device {
    bridge  = var.vm_bridge
    model   = "virtio"
    enabled = true
  }

  # Agente QEMU para melhor integração com o Proxmox (shutdown gracioso, IPs, etc.)
  agent {
    enabled = true
    trim    = true
  }

  # Configuração cloud-init: usuário, SSH, hostname e IP alocado via NetBox IPAM.
  # O IP é lido do objeto netbox_ip_address.k3s_server criado em netbox.tf,
  # eliminando o valor hardcoded "192.168.1.30/24".
  initialization {
    hostname = "k3s-server"

    user_account {
      username = local.cloud_init_user
      keys     = [var.ssh_public_key]
      password = null # Autenticação exclusivamente por chave SSH
    }

    ip_config {
      ipv4 {
        address = netbox_ip_address.k3s_server.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = "lab.local"
    }
  }

  # Configurações de boot e hardware
  boot_order    = ["scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  machine       = "q35"
  bios          = "seabios"

  # Tags para identificação no painel do Proxmox
  tags = local.common_tags

  # Ignorar mudanças no MAC address para evitar recriação desnecessária da VM
  lifecycle {
    ignore_changes = [
      network_device[0].mac_address,
      clone[0].vm_id,
    ]
  }
}

# ---------------------------------------------------------------------------
# VM: k3s-worker-cicd — worker dedicado a workloads de CI/CD
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "k3s_worker_cicd" {
  name        = "k3s-worker-cicd"
  description = "Nó worker K3s dedicado a pipelines CI/CD. Gerenciado pelo Terraform."
  node_name   = var.proxmox_node
  vm_id       = 201

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 6144
  }

  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = 60
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge  = var.vm_bridge
    model   = "virtio"
    enabled = true
  }

  agent {
    enabled = true
    trim    = true
  }

  # IP lido do objeto netbox_ip_address.k3s_worker_cicd criado em netbox.tf.
  initialization {
    hostname = "k3s-worker-cicd"

    user_account {
      username = local.cloud_init_user
      keys     = [var.ssh_public_key]
      password = null
    }

    ip_config {
      ipv4 {
        address = netbox_ip_address.k3s_worker_cicd.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = "lab.local"
    }
  }

  boot_order    = ["scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  machine       = "q35"
  bios          = "seabios"

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      network_device[0].mac_address,
      clone[0].vm_id,
    ]
  }
}

# ---------------------------------------------------------------------------
# VM: ci-runner — executor de pipelines (GitLab Runner / GitHub Actions)
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "ci_runner" {
  name        = "ci-runner"
  description = "Nó executor de pipelines CI. Gerenciado pelo Terraform."
  node_name   = var.proxmox_node
  vm_id       = 202

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge  = var.vm_bridge
    model   = "virtio"
    enabled = true
  }

  agent {
    enabled = true
    trim    = true
  }

  # IP lido do objeto netbox_ip_address.ci_runner criado em netbox.tf.
  initialization {
    hostname = "ci-runner"

    user_account {
      username = local.cloud_init_user
      keys     = [var.ssh_public_key]
      password = null
    }

    ip_config {
      ipv4 {
        address = netbox_ip_address.ci_runner.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = "lab.local"
    }
  }

  boot_order    = ["scsi0"]
  scsi_hardware = "virtio-scsi-pci"
  machine       = "q35"
  bios          = "seabios"

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      network_device[0].mac_address,
      clone[0].vm_id,
    ]
  }
}
