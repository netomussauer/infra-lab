# infra-lab

Laboratório completo de infraestrutura home-lab com cluster Kubernetes K3s multi-nó, pipeline CI/CD, monitoramento centralizado e IPAM via NetBox.

## Inventário da rede

| IP | Host / Serviço | OS / Plataforma | Papel |
| --- | --- | --- | --- |
| `192.168.1.20` | notebook-i7 | Proxmox VE 8.x | Hypervisor — VMs K3s |
| `192.168.1.30` | k3s-server *(VM)* | Ubuntu 22.04 | K3s control-plane |
| `192.168.1.31` | k3s-worker-cicd *(VM)* | Ubuntu 22.04 | K3s worker — CI/CD |
| `192.168.1.32` | ci-runner *(VM)* | Ubuntu 22.04 | Tekton runner |
| `192.168.1.65` | notebook-i5 — hostname: `ubuntu-neto` | Ubuntu 24.04 | K3s worker — monitoring |
| `192.168.1.72` | netbox-vm *(VM)* | — | NetBox IPAM |
| `192.168.1.110` | raspberry-pi — hostname: `raspneto` | Raspbian 12 | K3s worker — edge (ARMv7) |
| `192.168.1.112` | nas | NAS OS (Seagate Black Armor) | NFS storage NFSv3 |
| `192.168.1.200–220` | MetalLB pool | — | LoadBalancer Services K3s |
| `192.168.1.201` | Gitea | — | Git + CI webhook |
| `192.168.1.202` | Harbor | — | Container registry |
| `192.168.1.203` | ArgoCD | — | GitOps controller |
| `192.168.1.204` | Tekton EventListener | — | Webhook receptor |
| `192.168.1.210` | Grafana | — | Dashboards de monitoramento |
| `192.168.1.254` | gateway | — | Roteador doméstico |

## Stack

| Camada | Componentes |
| --- | --- |
| Kubernetes | K3s v1.29.3, MetalLB v0.14.3, Traefik v2, Flannel VXLAN |
| CI/CD | Gitea 1.25.5, Tekton Pipelines + Triggers, Harbor 2.14.3, ArgoCD v3.3.8 |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana + AlertManager), Loki Stack |
| IaC | Terraform (Proxmox + NetBox), Ansible |
| IPAM | NetBox |
| Storage | `local-path` provisioner (K3s built-in) · `nfs-storage` (NFSv3, disponível) |

## Documentação

| Documento | Conteúdo |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Topologia, inventário de hardware, diagrama do cluster, componentes por namespace |
| [docs/adr.md](docs/adr.md) | 9 Architecture Decision Records — por que cada tecnologia foi escolhida |
| [docs/runbook.md](docs/runbook.md) | Procedimentos de instalação, operações day-2 e P1–P19 de troubleshooting |

## Estrutura do repositório

```
infra-lab/
├── docs/
│   ├── architecture.md          # Topologia, hardware, cluster — leia primeiro
│   ├── adr.md                   # Decisões de design (K3s, Harbor, Tekton, etc.)
│   └── runbook.md               # Instalação, day-2 ops, troubleshooting P1-P19
│
├── terraform/proxmox/
│   ├── main.tf                  # VMs no Proxmox (IPs via NetBox)
│   ├── netbox.tf                # Registros IPAM: prefixos, IPs, VMs
│   ├── variables.tf
│   ├── versions.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example # Copiar para terraform.tfvars e preencher
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml            # Inventário estático
│   │   ├── netbox.yml           # Inventário dinâmico via NetBox
│   │   └── group_vars/
│   │       ├── all.yml          # Variáveis globais (SSH, NFS, K3s version)
│   │       ├── k3s_server.yml
│   │       └── k3s_agents.yml
│   ├── playbooks/
│   │   ├── 00-baremetal-init.yml   # Provisionamento inicial de hosts bare metal
│   │   ├── 00-netbox-register.yml  # Registra hosts físicos no NetBox
│   │   ├── 01-base-setup.yml       # OS, pacotes, sysctl, swap
│   │   ├── 02-nfs-mounts.yml       # Monta NFS shares do NAS
│   │   ├── 03-k3s-server.yml       # Instala K3s control-plane
│   │   ├── 04-k3s-agents.yml       # Junta workers ao cluster
│   │   └── 05-post-setup.yml       # Labels, taints, verificação final
│   └── requirements.yml
│
├── kubernetes/
│   ├── bootstrap/
│   │   ├── namespaces.yaml         # Namespaces: cicd, registry, monitoring
│   │   ├── metallb/
│   │   │   ├── metallb-install.yaml
│   │   │   └── ipaddresspool.yaml  # Pool 192.168.1.200-220
│   │   └── storage/
│   │       ├── nfs-csi-values.yaml
│   │       └── nfs-storageclass.yaml
│   ├── cicd/
│   │   ├── gitea/
│   │   │   └── helm-values.yaml    # Gitea 1.25.5 + PostgreSQL bundled
│   │   ├── harbor/
│   │   │   └── helm-values.yaml    # Harbor 2.14.3 (namespace: registry)
│   │   ├── argocd/
│   │   │   ├── helm-values.yaml    # ArgoCD v3.3.8
│   │   │   └── app-of-apps.yaml
│   │   └── tekton/
│   │       ├── pipeline-build-push.yaml  # Pipeline Kaniko build + Harbor push
│   │       └── trigger-gitea.yaml        # EventListener + TriggerTemplate
│   ├── monitoring/
│   │   ├── kube-prometheus-stack/
│   │   │   └── helm-values.yaml    # Prometheus + Grafana (192.168.1.210) + AlertManager
│   │   ├── loki-stack/
│   │   │   └── helm-values.yaml    # Loki + Promtail DaemonSet
│   │   └── dashboards/
│   │       └── k8s-cluster-dashboard.yaml  # ConfigMap Grafana
│   └── apps/
│       └── hello-lab/
│           ├── deployment.yaml
│           └── service.yaml
│
└── scripts/
    ├── bootstrap.sh             # Orquestra Terraform + Ansible (VMs)
    ├── init-baremetal.sh        # Provisionamento inicial de hosts bare metal
    ├── k8s-bootstrap.sh         # Instala stack K8s completa via Helm
    ├── get-kubeconfig.sh        # Copia kubeconfig do k3s-server (Linux/macOS)
    └── get-kubeconfig.ps1       # Copia kubeconfig do k3s-server (Windows/PowerShell)
```

## Início rápido

### 1. Pré-requisitos

```bash
# Ferramentas na máquina de controle (Windows 11 + WSL Ubuntu)
terraform >= 1.6
ansible >= 2.15   # instalado em ~/.local/bin no WSL
helm >= 3.14
kubectl

# Collections Ansible
ansible-galaxy collection install -r ansible/requirements.yml
pip install pynetbox
```

### 2. Configurar credenciais

```bash
cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
# Preencher: proxmox_api_token_id, proxmox_api_token_secret, ssh_public_key
#            netbox_url, netbox_token

export NETBOX_URL=http://192.168.1.72:8000
export NETBOX_TOKEN=<token em NetBox > User > API Tokens>
```

### 3. Provisionar VMs e configurar hosts

```bash
# Provisiona VMs no Proxmox + registra no NetBox + instala K3s
./scripts/bootstrap.sh

# Para hosts bare metal (notebook-i5, raspberry-pi):
./scripts/init-baremetal.sh
```

> **Nota WSL:** `ansible-playbook` está em `~/.local/bin`. Usar sempre heredoc para evitar
> problemas com o `$PATH` do Windows (parênteses em `Program Files (x86)` quebram `bash -c`):
>
> ```bash
> wsl -d Ubuntu -- bash << 'EOF'
> export PATH=/home/<user>/.local/bin:/usr/local/bin:/usr/bin:/bin
> cd /mnt/c/.../infra-lab/ansible
> ansible-playbook -i inventory/hosts.yml playbooks/04-k3s-agents.yml \
>   --limit 'k3s_server,raspberry-pi'
> EOF
> ```

### 4. Obter kubeconfig

```bash
# Linux / macOS / WSL
./scripts/get-kubeconfig.sh
export KUBECONFIG=~/.kube/infra-lab.yaml

# Windows PowerShell
.\scripts\get-kubeconfig.ps1
$env:KUBECONFIG = "$env:USERPROFILE\.kube\infra-lab.yaml"

kubectl get nodes -o wide
```

### 5. Instalar stack Kubernetes

```bash
export KUBECONFIG=~/.kube/infra-lab.yaml
./scripts/k8s-bootstrap.sh
```

### 6. Acessos após o bootstrap

| Serviço | Endereço | Credenciais padrão |
| --- | --- | --- |
| Gitea | `http://192.168.1.201` | admin / (definido na instalação) |
| Harbor | `http://192.168.1.202` | admin / Harbor12345 |
| ArgoCD | `http://192.168.1.203` | admin / secret `argocd-initial-admin-secret` |
| Tekton Dashboard | `http://192.168.1.204` | — |
| Grafana | `http://192.168.1.210` | admin / lab@admin |
| NetBox | `http://192.168.1.72:8000` | admin / (definido na instalação) |

> Credenciais completas e procedimentos de rotação em [docs/runbook.md — Seção 6](docs/runbook.md#6-acessos-e-credenciais).

## Nós do cluster (estado atual)

```text
NAME              STATUS   ROLES           VERSION        INTERNAL-IP     OS
k3s-server        Ready    control-plane   v1.29.3+k3s1   192.168.1.30    Ubuntu 22.04
k3s-worker-cicd   Ready    <none>          v1.29.3+k3s1   192.168.1.31    Ubuntu 22.04
ci-runner         Ready    <none>          v1.29.3+k3s1   192.168.1.32    Ubuntu 22.04
ubuntu-neto       Ready    <none>          v1.29.3+k3s1   192.168.1.65    Ubuntu 24.04
raspneto          Ready    <none>          v1.29.3+k3s1   192.168.1.110   Raspbian 12
```

## Inventário dinâmico Ansible via NetBox

```bash
ansible-inventory -i ansible/inventory/netbox.yml --graph
ansible-playbook -i ansible/inventory/netbox.yml ansible/playbooks/01-base-setup.yml
```
