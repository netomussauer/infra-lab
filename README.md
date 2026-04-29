# infra-lab

Laboratório completo de infraestrutura home-lab com cluster Kubernetes K3s multi-nó, pipeline CI/CD, monitoramento centralizado e IPAM via NetBox.

## Inventário da rede

| IP | Host / Serviço | OS / Plataforma | Papel |
| --- | --- | --- | --- |
| `192.168.1.20` | notebook-i7 | Proxmox VE | Hypervisor — VMs K3s + serviços |
| `192.168.1.30` | k3s-server *(VM)* | Ubuntu 22.04 | K3s control-plane |
| `192.168.1.31` | k3s-worker-cicd *(VM)* | Ubuntu 22.04 | K3s worker — CI/CD |
| `192.168.1.32` | ci-runner *(VM)* | Ubuntu 22.04 | Tekton runner |
| `192.168.1.65` | notebook-i5 | Ubuntu 22.04 | K3s worker — monitoring |
| `192.168.1.72` | netbox-vm *(VM)* | — | NetBox IPAM |
| `192.168.1.76` | bookstack *(VM)* | — | Wiki / documentação |
| `192.168.1.107` | homeassistant *(VM)* | — | Automação residencial |
| `192.168.1.110` | raspberry-pi | Raspbian 12 | K3s worker — edge (ARMv7) |
| `192.168.1.112` | nas | NAS OS | NFS storage (3 TB) |
| `192.168.1.200–220` | MetalLB pool | — | LoadBalancer Services K3s |
| `192.168.1.254` | gateway | — | Roteador doméstico |

## Stack

| Camada | Tecnologias |
|--------|-------------|
| Kubernetes | K3s, MetalLB, Traefik, cert-manager |
| CI/CD | Gitea, Tekton Pipelines, Harbor, ArgoCD |
| Monitoring | Prometheus, Grafana, Loki, Promtail, AlertManager |
| IaC | Terraform (Proxmox + NetBox), Ansible |
| IPAM | NetBox |

## Documentação

- [Arquitetura completa](docs/architecture.md) — topologia, diagramas, decisões de design, ordem de instalação

## Estrutura do repositório

```
infra-lab/
├── docs/
│   └── architecture.md          # Referência central — leia antes de qualquer outra coisa
│
├── terraform/proxmox/
│   ├── main.tf                  # VMs no Proxmox (IPs via NetBox)
│   ├── netbox.tf                # Registros IPAM: prefixos, IPs, VMs
│   ├── variables.tf
│   ├── versions.tf
│   └── terraform.tfvars.example # Copiar para terraform.tfvars e preencher
│
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml            # Inventário estático (fallback)
│   │   ├── netbox.yml           # Inventário dinâmico via NetBox
│   │   └── group_vars/
│   ├── playbooks/
│   │   ├── 00-netbox-register.yml  # Registra hosts físicos no NetBox
│   │   ├── 01-base-setup.yml       # OS, pacotes, sysctl, swap
│   │   ├── 02-nfs-mounts.yml       # Monta NFS shares do NAS
│   │   ├── 03-k3s-server.yml       # Instala K3s control-plane
│   │   ├── 04-k3s-agents.yml       # Junta workers ao cluster
│   │   └── 05-post-setup.yml       # Labels, taints, verificação
│   └── requirements.yml
│
├── kubernetes/
│   ├── bootstrap/
│   │   ├── namespaces.yaml
│   │   ├── metallb/             # IPAddressPool 192.168.1.200-220
│   │   └── storage/             # StorageClass nfs-storage (default)
│   ├── cicd/
│   │   ├── gitea/               # Helm values
│   │   ├── harbor/              # Helm values
│   │   ├── argocd/              # Helm values + app-of-apps
│   │   └── tekton/              # Pipeline build/push + Gitea triggers
│   ├── monitoring/
│   │   ├── kube-prometheus-stack/  # Helm values
│   │   ├── loki-stack/             # Helm values
│   │   └── dashboards/             # ConfigMaps Grafana
│   └── apps/
│       └── hello-lab/           # App de exemplo (nginx)
│
└── scripts/
    ├── bootstrap.sh             # Orquestra Terraform + Ansible
    ├── k8s-bootstrap.sh         # Instala stack K8s via Helm
    ├── get-kubeconfig.sh        # Copia kubeconfig do k3s-server (Linux/macOS)
    └── get-kubeconfig.ps1       # Copia kubeconfig do k3s-server (Windows/PowerShell)
```

## Início rápido

### 1. Pré-requisitos

```bash
# Ferramentas necessárias na máquina de controle
terraform >= 1.6
ansible >= 2.15
helm >= 3.14
kubectl

# Collections Ansible
ansible-galaxy collection install netbox.netbox
pip install pynetbox
```

### 2. Configurar credenciais

```bash
cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
# Editar terraform.tfvars com:
#   proxmox_api_token_id, proxmox_api_token_secret, ssh_public_key
#   netbox_url, netbox_token

export NETBOX_URL=http://192.168.1.72:8000
export NETBOX_TOKEN=<token gerado em /user/api-tokens/>
```

### 3. Provisionar infraestrutura

```bash
# Provisiona VMs no Proxmox + registra tudo no NetBox
./scripts/bootstrap.sh
```

### 4. Obter o kubeconfig do K3s

O arquivo `~/.kube/infra-lab.yaml` não existe no repositório — ele é gerado copiando
`/etc/rancher/k3s/k3s.yaml` do servidor K3s e substituindo o endereço loopback pelo IP real.
Execute este script **após** o `bootstrap.sh` do passo 3 (que instala o K3s via Ansible) e
**antes** do `k8s-bootstrap.sh` do passo 5:

**Linux / macOS:**

```bash
# Requer: chave SSH em ~/.ssh/lab_id_rsa autorizada no host labadmin@192.168.1.30
./scripts/get-kubeconfig.sh

# Exportar para a sessão atual (ou adicionar ao ~/.bashrc / ~/.zshrc para persistir)
export KUBECONFIG=~/.kube/infra-lab.yaml

# Verificar nós do cluster
kubectl get nodes -o wide
```

**Windows (PowerShell):**

```powershell
# Requer: chave SSH em ~\.ssh\lab_id_rsa autorizada no host labadmin@192.168.1.30
.\scripts\get-kubeconfig.ps1

# Exportar para a sessão atual (ou adicionar ao $PROFILE para persistir)
$env:KUBECONFIG = "$env:USERPROFILE\.kube\infra-lab.yaml"

# Verificar nós do cluster
kubectl get nodes -o wide
```

### 5. Instalar stack Kubernetes completa

```bash
export KUBECONFIG=~/.kube/infra-lab.yaml
./scripts/k8s-bootstrap.sh
```

### 6. Acessos após o bootstrap

| Serviço | Endereço |
|---------|----------|
| Gitea | `http://192.168.1.200` |
| Harbor | `https://192.168.1.201` |
| ArgoCD | `http://192.168.1.202` |
| Grafana | `http://192.168.1.210` |
| NetBox | `http://192.168.1.72:8000` |

## Inventário dinâmico Ansible via NetBox

```bash
# Verificar hosts detectados
ansible-inventory -i ansible/inventory/netbox.yml --graph

# Executar playbook com inventário dinâmico
ansible-playbook -i ansible/inventory/netbox.yml ansible/playbooks/01-base-setup.yml
```
