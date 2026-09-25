# Runbook Operacional — infra-lab

> **Versão:** 1.0.0
> **Atualizado em:** 2026-04-29
> **Responsável:** jose.mussauer@stone.com.br

Este documento cobre todos os procedimentos técnicos do laboratório: pré-requisitos, provisionamento, bootstrap do cluster, operações day-2 e troubleshooting de problemas conhecidos.

Para entender _o que_ está instalado e _por que_, consulte:
- [architecture.md](./architecture.md) — visão geral da arquitetura
- [adr.md](./adr.md) — decisões de design e trade-offs

---

## Sumário

1. [Ambiente de controle](#1-ambiente-de-controle)
2. [Provisionamento de VMs (Terraform + Proxmox)](#2-provisionamento-de-vms-terraform--proxmox)
3. [Provisionamento bare metal (Ansible)](#3-provisionamento-bare-metal-ansible)
4. [Bootstrap do cluster K8s](#4-bootstrap-do-cluster-k8s)
5. [Operações day-2](#5-operações-day-2)
6. [Acessos e credenciais](#6-acessos-e-credenciais)
7. [Troubleshooting — problemas conhecidos](#7-troubleshooting--problemas-conhecidos)

---

## 1. Ambiente de controle

Todo gerenciamento do cluster é feito a partir do Windows 11 via **WSL Ubuntu** (`wsl -d Ubuntu`).

### 1.1 Ferramentas necessárias (WSL)

| Ferramenta | Versão mínima | Localização |
|---|---|---|
| kubectl | v1.29.x | `/home/netomussauer/.local/bin/kubectl` |
| helm | v3.x | `~/.local/bin/helm` |
| ansible | 2.x | `~/.local/bin/ansible` |
| terraform | 1.x | em PATH |
| git | qualquer | sistema |

### 1.2 KUBECONFIG

O arquivo de kubeconfig fica em `~/.kube/infra-lab.yaml` dentro do WSL.

```bash
# Definir em cada sessão (ou adicionar ao ~/.bashrc):
export KUBECONFIG=~/.kube/infra-lab.yaml

# Copiar kubeconfig do control-plane (executar uma vez após instalar K3s):
./scripts/get-kubeconfig.sh
```

O script `get-kubeconfig.sh` faz SSH para `k3s-server` (192.168.1.30), copia `/etc/rancher/k3s/k3s.yaml` e ajusta o endpoint para o IP correto.

### 1.3 Executar scripts via WSL

```bash
# Todos os comandos devem ser executados no contexto WSL:
wsl -d Ubuntu -e bash -c "
  export PATH=/home/netomussauer/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export KUBECONFIG=/home/netomussauer/.kube/infra-lab.yaml
  <comando>
"
```

Ou, após uma sessão WSL interativa (`wsl -d Ubuntu`):

```bash
export PATH=/home/netomussauer/.local/bin:$PATH
export KUBECONFIG=~/.kube/infra-lab.yaml
```

### 1.4 Chave SSH do lab

A chave SSH utilizada pelo Ansible para acessar todos os nós é `~/.ssh/lab_id_rsa`.

```bash
# Verificar acesso a um nó:
ssh -i ~/.ssh/lab_id_rsa labadmin@192.168.1.30
```

---

## 2. Provisionamento de VMs (Terraform + Proxmox)

### 2.1 Pré-requisitos

- Proxmox VE instalado no `notebook-i7` (192.168.1.20)
- NetBox configurado (192.168.1.72) com token de API
- Template de VM Ubuntu 22.04 no Proxmox (cloud-init)

### 2.2 Configurar credenciais

```bash
cd terraform/proxmox

# Copiar e preencher o arquivo de variáveis:
cp terraform.tfvars.example terraform.tfvars
# Editar: proxmox_url, proxmox_token_id, proxmox_token_secret, netbox_token
```

Variáveis de ambiente obrigatórias:

```bash
export NETBOX_URL=https://192.168.1.72
export NETBOX_TOKEN=<token-gerado-no-netbox>
```

### 2.3 Executar

```bash
cd terraform/proxmox
terraform init
terraform plan -out=tfplan.binary
terraform apply tfplan.binary
```

O Terraform cria as VMs (`k3s-server`, `k3s-worker-cicd`, `ci-runner`) e registra seus IPs no NetBox.

### 2.4 Verificar VMs criadas

```bash
# IPs devem aparecer no NetBox:
# https://192.168.1.72/ipam/ip-addresses/

# Verificar SSH nas VMs recém-criadas:
ssh labadmin@192.168.1.30  # k3s-server
ssh labadmin@192.168.1.31  # k3s-worker-cicd
ssh labadmin@192.168.1.32  # ci-runner
```

---

## 3. Provisionamento bare metal (Ansible)

### 3.1 Variáveis de configuração

Todas as variáveis globais ficam em `ansible/inventory/group_vars/all.yml`.

Variáveis relevantes:

```yaml
ansible_user: labadmin
ansible_ssh_private_key_file: ~/.ssh/lab_id_rsa
nfs_server: "192.168.1.112"
nfs_mount_options: "nfsvers=3,hard,intr,_netdev,rsize=131072,wsize=131072"
k3s_version: "v1.29.3+k3s1"
k3s_server_ip: "192.168.1.30"
```

> **Importante:** `ansible_user: labadmin` em `group_vars/all.yml` tem precedência sobre `-u` na linha de comando. Para usar um usuário diferente, use `-e 'ansible_user=<outro>'`.

### 3.2 Inicialização bare metal (primeira vez)

Para hosts físicos que ainda não têm o usuário `labadmin`:

```bash
cd ansible

# notebook-i5 — usuário inicial: netomussauer
ansible-playbook -i inventory/hosts.yml playbooks/00-baremetal-init.yml \
  --limit notebook-i5 \
  -e "ansible_user=netomussauer" \
  -k --ask-become-pass

# raspberry-pi — usuário inicial: mussa
ansible-playbook -i inventory/hosts.yml playbooks/00-baremetal-init.yml \
  --limit raspberry-pi \
  -e "ansible_user=mussa" \
  -k --ask-become-pass
```

O playbook `00-baremetal-init.yml`:
- Cria o usuário `labadmin` com sudo NOPASSWD
- Instala a chave `~/.ssh/lab_id_rsa.pub` no `authorized_keys` do labadmin
- Endurece SSH (desabilita login root e autenticação por senha)

### 3.3 Configuração base dos nós

```bash
# Todos os nós do cluster (VMs + bare metal):
ansible-playbook -i inventory/hosts.yml playbooks/01-base-setup.yml

# Apenas um nó específico:
ansible-playbook -i inventory/hosts.yml playbooks/01-base-setup.yml \
  --limit notebook-i5
```

O que faz: atualiza pacotes, desativa swap, configura módulos de kernel e sysctl para K8s.

> **Nota:** se o playbook falhar na verificação de swap (`ERRO: Swap ainda ativo`), execute-o novamente — o `swapoff -a` já rodou, e na segunda execução os facts serão coletados com swap=0.

### 3.4 Montagens NFS

```bash
ansible-playbook -i inventory/hosts.yml playbooks/02-nfs-mounts.yml \
  --limit notebook-i5
```

> **Nota:** o export `/backups` pode não estar acessível a todos os hosts (depende da configuração do NAS). A falha nesse mount específico é não-crítica para o funcionamento do cluster — o K3s não depende de montagens NFS de host.

### 3.5 Instalação do K3s server

```bash
ansible-playbook -i inventory/hosts.yml playbooks/03-k3s-server.yml
```

### 3.6 Instalação dos K3s agents

```bash
# Todos os agents (inclui VMs e bare metal):
ansible-playbook -i inventory/hosts.yml playbooks/04-k3s-agents.yml

# Adicionar apenas um nó novo (incluir k3s_server para ler o token):
ansible-playbook -i inventory/hosts.yml playbooks/04-k3s-agents.yml \
  --limit 'k3s_server,notebook-i5'
```

> **Importante:** usar `--limit 'k3s_server,<novo-nó>'` — incluir `k3s_server` para o Play 1 conseguir ler o token de join. Usar `--limit <novo-nó>` sozinho faz o Play 1 ser pulado e o token não fica disponível.

> **Nota sobre hostname:** o K3s registra o nó com o hostname real do SO (`ansible_hostname`), não com o nome do inventário Ansible. Por exemplo, o `notebook-i5` se registra como `ubuntu-neto`. O playbook já usa `ansible_hostname` para o wait e label do nó.

### 3.7 Post-setup

```bash
ansible-playbook -i inventory/hosts.yml playbooks/05-post-setup.yml
```

---

## 4. Bootstrap do cluster K8s

O script `scripts/k8s-bootstrap.sh` instala toda a stack K8s em etapas numeradas. Pode ser executado completo ou por etapa individual.

### 4.1 Execução completa

```bash
# Via WSL:
wsl -d Ubuntu -e bash -c "
  export PATH=/home/netomussauer/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export KUBECONFIG=/home/netomussauer/.kube/infra-lab.yaml
  bash /mnt/c/Users/jose.mussauer/Documents/projetos/infra-lab/scripts/k8s-bootstrap.sh
"
```

### 4.2 Etapa individual

```bash
# Executar apenas uma etapa:
bash scripts/k8s-bootstrap.sh step_gitea
bash scripts/k8s-bootstrap.sh step_monitoring
# etc.
```

### 4.3 Ordem das etapas e dependências

| Etapa | Função | Dependências |
|---|---|---|
| `step_namespaces` | Cria namespaces (`cicd`, `monitoring`, `edge`, `registry`) | Cluster acessível |
| `step_metallb` | Instala MetalLB v0.14.3 + pool 192.168.1.200-220 | Namespaces |
| `step_storage` | Instala NFS Subdir Provisioner (StorageClass `nfs-storage`) | MetalLB |
| `step_gitea` | Instala Gitea 1.25.5 + PostgreSQL bundled | storage, MetalLB |
| `step_harbor` | Instala Harbor 2.14.3 | storage, MetalLB |
| `step_argocd` | Instala ArgoCD v3.3.8 | MetalLB |
| `step_app_of_apps` | Cria Application ArgoCD apontando para `kubernetes/apps/` | ArgoCD running |
| `step_tekton` | Instala Tekton Pipelines + Triggers + Pipeline `build-and-push` | Cluster, secrets pré-criados |
| `step_monitoring` | Instala kube-prometheus-stack (requer nó `workload=monitoring`) | Nó ubuntu-neto no cluster |
| `step_loki` | Instala Loki Stack | Monitoring namespace |
| `step_shared_infra` | Instala PostgreSQL 16 + Redis 7 compartilhados (ns `shared-infra`) | Nó ubuntu-neto no cluster |
| `step_pihole` | Instala Pi-hole + pool MetalLB `infra-services-pool` (ns `network-services`) | MetalLB, nó ubuntu-neto |
| `step_internal_dns` | Aplica playbook Ansible que reconfigura DNS dos nós (Pi-hole primário) | `step_pihole` |
| `step_harbor_trust` | Aplica playbook Ansible que instala CA do Harbor no trust store dos nós | `step_harbor` |
| `step_sealed_secrets` | Instala Sealed Secrets controller (`kube-system`) + Kustomize com nodeSelector amd64 | Cluster running |
| `step_hello_lab` | Deploy da aplicação de exemplo | Cluster running |

### 4.4 Secrets obrigatórios antes do Tekton

Criar antes de executar `step_tekton`:

```bash
# Credenciais do Harbor para push de imagens:
kubectl create secret docker-registry harbor-registry-secret \
  --docker-server=harbor.lab.local \
  --docker-username=admin \
  --docker-password=Harbor12345! \
  --namespace=cicd

# Credenciais do Gitea para push de commits (update-manifest):
kubectl create secret generic gitea-auth-secret \
  --from-literal=username=labadmin \
  --from-literal=password=labadmin123! \
  --namespace=cicd

# Secret HMAC para validar webhooks do Gitea:
kubectl create secret generic gitea-webhook-secret \
  --from-literal=secretToken=$(openssl rand -hex 32) \
  --namespace=cicd
```

### 4.5 Configurar webhook no Gitea

Após `step_tekton`:

1. Acessar Gitea: `http://192.168.1.201:3000` (ou `http://gitea.lab.local:3000`)
2. No repositório da aplicação → Settings → Webhooks → Add Webhook → Gitea
3. Preencher:
   - **URL:** `http://192.168.1.204`
   - **Content-Type:** `application/json`
   - **Secret:** valor do secret `gitea-webhook-secret` (campo `secretToken`)
   - **Events:** Push Events

```bash
# Recuperar o token HMAC:
kubectl get secret -n cicd gitea-webhook-secret \
  -o jsonpath='{.data.secretToken}' | base64 -d
```

### 4.6 DNS interno do lab (Pi-hole)

A partir de 2026-05-11, o lab tem **Pi-hole** rodando no cluster em `192.168.1.53` servindo DNS para a LAN inteira. Todos os 5 nós já estão configurados para usar Pi-hole como DNS primário via playbook `ansible/playbooks/06-internal-dns.yml`.

**Registros disponíveis (gerenciados via `kubernetes/network-services/pihole/configmap-records.yaml`):**

| Hostname | IP |
| --- | --- |
| `gitea.lab.local` | 192.168.1.201 |
| `harbor.lab.local` / `harbor.infra.local` | 192.168.1.202 |
| `argocd.lab.local` | 192.168.1.203 |
| `tekton.lab.local` | 192.168.1.204 |
| `grafana.lab.local` | 192.168.1.210 |
| `pihole.lab.local` | 192.168.1.53 |
| `proxmox.lab.local` | 192.168.1.20 |
| `*.amfit.local` | 192.168.1.205/206/207 (reserva) |

**Para máquinas fora do cluster** (PCs, celulares, dev WSL):

- Configurar a máquina para usar `192.168.1.53` como DNS primário, **ou**
- Configurar o roteador para distribuir `192.168.1.53` via DHCP, **ou**
- Adicionar entradas manuais em `/etc/hosts` (fallback):

```text
192.168.1.53   pihole.lab.local
192.168.1.201  gitea.lab.local
192.168.1.202  harbor.lab.local
192.168.1.203  argocd.lab.local
192.168.1.210  grafana.lab.local
```

**Adicionar/remover registro DNS no Pi-hole:**

```bash
# 1. Editar ConfigMap
vi kubernetes/network-services/pihole/configmap-records.yaml

# 2. Aplicar
kubectl apply -f kubernetes/network-services/pihole/configmap-records.yaml

# 3. Forçar reload do dnsmasq (rollout do pod)
kubectl rollout restart deployment/pihole -n network-services

# 4. Validar
nslookup novo-host.lab.local 192.168.1.53
```

**Reconfigurar DNS de um nó manualmente** (caso o playbook 06 não tenha rodado):

```bash
# Ubuntu (systemd-resolved)
sudo tee /etc/systemd/resolved.conf.d/lab-dns.conf <<EOF
[Resolve]
DNS=192.168.1.53
FallbackDNS=1.1.1.1 8.8.8.8
Domains=lab.local infra.local amfit.local
EOF
sudo systemctl restart systemd-resolved

# Raspbian (NetworkManager)
sudo tee /etc/NetworkManager/conf.d/lab-dns.conf <<EOF
[global-dns-domain-*]
servers=192.168.1.53,1.1.1.1,8.8.8.8

[global-dns]
searches=lab.local,infra.local,amfit.local
EOF
sudo systemctl restart NetworkManager
```

### 4.7 Sealed Secrets — encriptar secrets por projeto

A partir de 2026-05-11, o lab tem **Sealed Secrets** (Bitnami Labs) v0.36.6 instalado no cluster como plataforma compartilhada de gestão de secrets. Qualquer projeto pode encriptar localmente e commitar o resultado no Git — apenas o controller no cluster decripta. Ver [ADR-011](./adr.md#adr-011) para o racional da escolha.

**Pré-requisitos (uma vez por máquina de dev):**

```bash
# Instalar kubeseal CLI (Linux/WSL — versão deve bater com o controller)
KUBESEAL_VERSION=0.36.6
ARCH=$(dpkg --print-architecture)
curl -sSL -o /tmp/kubeseal.tar.gz \
  "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz"
tar xzf /tmp/kubeseal.tar.gz -C /tmp
sudo mv /tmp/kubeseal /usr/local/bin/
```

**Workflow recomendado (qualquer projeto):**

```bash
# 1. Criar Secret normal localmente (NUNCA comitar este arquivo)
kubectl create secret generic my-app-secrets \
  --from-literal=DATABASE_URL='postgres://...' \
  --from-literal=API_KEY='s3cret123' \
  --namespace=my-app \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 2. Encriptar — gera SealedSecret usando o cert público em kubernetes/sealed-secrets/pub-cert.pem
./scripts/seal-secret.sh /tmp/secret.yaml > my-app/k8s/sealedsecret.yaml

# 3. Commitar o SealedSecret no Git do projeto
git add my-app/k8s/sealedsecret.yaml
git commit -m "feat: add my-app secrets as SealedSecret"

# 4. ArgoCD (ou kubectl apply manual) aplica o SealedSecret
#    → controller no cluster decripta automaticamente → cria Secret/my-app-secrets

# 5. Limpar o Secret descriptografado local
shred -u /tmp/secret.yaml
```

**Variáveis do script `seal-secret.sh`:**

| Var | Default | Uso |
| --- | --- | --- |
| `PUB_CERT` | `kubernetes/sealed-secrets/pub-cert.pem` | Caminho do cert público para encryption offline |
| `SCOPE` | `strict` | `strict` (name+ns travados) · `namespace-wide` · `cluster-wide` |
| `FETCH_CERT` | `false` | Se `true`, busca cert do cluster em runtime (requer kubeconfig) |

**Atualizar o cert público após rotação do controller (a cada 30 dias):**

```bash
# O controller mantém keys antigas para decryption — SealedSecrets existentes
# continuam funcionando. Mas para encriptar NOVOS secrets, use o cert mais recente.
ssh labadmin@192.168.1.30 \
  "k3s kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
    -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d" \
  > kubernetes/sealed-secrets/pub-cert.pem

git add kubernetes/sealed-secrets/pub-cert.pem
git commit -m "chore: refresh sealed-secrets public cert"
```

**Backup do master key (CRÍTICO — sem ele, todos os SealedSecrets viram inúteis):**

```bash
# Exportar todas as keys (ativa + arquivadas) para um único arquivo PEM
ssh labadmin@192.168.1.30 \
  "k3s kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
    -o yaml" > /tmp/sealed-secrets-keys-backup-$(date +%Y%m%d).yaml

# Guardar em local SEGURO e offline:
#   - 1Password / Bitwarden em campo de attachment
#   - Pendrive criptografado guardado fisicamente
#   - NÃO em repositório Git, mesmo privado
shred -u /tmp/sealed-secrets-keys-backup-*.yaml   # após copiar para destino seguro
```

**Restore (disaster recovery):**

```bash
# Reinstalar o controller e ANTES de qualquer SealedSecret ser aplicado:
kubectl apply -f /caminho/seguro/sealed-secrets-keys-backup-YYYYMMDD.yaml
kubectl delete pod -n kube-system -l name=sealed-secrets-controller   # re-load das keys
```

---

## 5. Operações day-2

### 5.1 Adicionar um nó ao cluster

```bash
cd ansible

# 1. Garantir que o nó tem labadmin configurado (se bare metal novo):
ansible-playbook -i inventory/hosts.yml playbooks/00-baremetal-init.yml \
  --limit <hostname> -e "ansible_user=<usuario-inicial>" -k --ask-become-pass

# 2. Configuração base:
ansible-playbook -i inventory/hosts.yml playbooks/01-base-setup.yml \
  --limit <hostname>

# 3. Instalar K3s agent (incluir k3s_server para o token):
ansible-playbook -i inventory/hosts.yml playbooks/04-k3s-agents.yml \
  --limit 'k3s_server,<hostname>'

# 4. Verificar join:
kubectl get nodes -o wide
```

### 5.2 Atualizar um chart Helm

```bash
# Exemplo: atualizar kube-prometheus-stack
helm repo update prometheus-community
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f kubernetes/monitoring/kube-prometheus-stack/helm-values.yaml \
  --namespace monitoring

# Verificar:
kubectl get pods -n monitoring
```

### 5.3 Verificar status de um PipelineRun

```bash
# Listar PipelineRuns recentes:
kubectl get pipelineruns -n cicd --sort-by='.metadata.creationTimestamp' | tail -5

# Ver detalhes de um run específico:
kubectl describe pipelinerun -n cicd <nome-do-run>

# Ver logs de uma Task:
kubectl logs -n cicd -l tekton.dev/pipelineRun=<nome-do-run> --all-containers

# Forçar um run manual (criar PipelineRun):
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: manual-run-
  namespace: cicd
spec:
  pipelineRef:
    name: build-and-push
  params:
    - name: source-repo-url
      value: "http://gitea.lab.local/lab/hello-lab.git"
    - name: source-revision
      value: "main"
    - name: image-name
      value: "harbor.lab.local/lab/hello-lab"
    - name: image-tag
      value: "manual"
    - name: dockerfile
      value: "Dockerfile"
    - name: manifest-repo-url
      value: "http://gitea.lab.local/lab/infra-lab.git"
    - name: manifest-path
      value: "kubernetes/apps/hello-lab/deployment.yaml"
  workspaces:
    - name: source
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 1Gi
    - name: manifest-repo
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 500Mi
    - name: docker-credentials
      secret:
        secretName: harbor-registry-secret
    - name: git-credentials
      secret:
        secretName: gitea-auth-secret
EOF
```

### 5.4 Forçar sincronização ArgoCD

```bash
# Via CLI (se argocd CLI instalado):
argocd app sync <nome-da-app> --server 192.168.1.203

# Via kubectl (trigger de reconciliação):
kubectl annotate application -n cicd <nome-da-app> \
  argocd.argoproj.io/refresh=normal --overwrite
```

### 5.5 Reiniciar um deployment

```bash
kubectl rollout restart deployment/<nome> -n <namespace>
kubectl rollout status deployment/<nome> -n <namespace>
```

### 5.6 Verificar uso de recursos por nó

```bash
# Uso atual (requer metrics-server — K3s inclui por padrão):
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -20

# PVCs e uso de storage:
kubectl get pvc -A
```

### 5.7 Helm — release em estado travado

Se um `helm upgrade --install` com `--wait` expirar, o release pode ficar em `pending-install` ou `failed`, bloqueando upgrades futuros.

```bash
# Verificar status:
helm list -A

# Se STATUS = pending-install: aguardar o status mudar para failed (~timeout do helm)
# Se STATUS = failed: tentar upgrade normalmente
helm upgrade <release> <chart> -f <values> -n <namespace> --timeout 5m

# Se ainda bloqueado, rollback para versão anterior:
helm rollback <release> -n <namespace>

# Último recurso — deletar e reinstalar (perda de histórico):
helm delete <release> -n <namespace>
# Aguardar limpeza dos recursos e reinstalar
```

### 5.8 Limpar PipelineRuns antigos

```bash
# Ver runs mais antigos que 7 dias (requer kubectl-neat ou filtragem manual):
kubectl get pipelinerun -n cicd \
  --sort-by='.metadata.creationTimestamp' | head -20

# Deletar runs concluídos:
kubectl delete pipelinerun -n cicd \
  $(kubectl get pipelinerun -n cicd \
    -o jsonpath='{.items[?(@.status.conditions[0].reason=="Succeeded")].metadata.name}')
```

---

## 6. Acessos e credenciais

Movido para `docs/CREDENTIALS.local.md` em 2026-09-18 — arquivo local,
**gitignored** (`*.local.md`), nunca commitado. Serviços cobertos: Pi-hole,
Gitea, Harbor, ArgoCD, Grafana, Proxmox, NetBox, os bancos PostgreSQL/Redis
compartilhados do namespace `shared-infra`, e os comandos para buscar
secrets rotativos (senha inicial do ArgoCD, HMAC do webhook Tekton).

Motivo: essas tabelas continham senhas reais em texto puro versionadas no
git (não só valores de exemplo), inclusive das bases de dados em uso pelas
apps `amfit`/`realtpmsys` — violava a própria política de credenciais deste
workspace (`AGENTS.md` → "Credentials and Secrets"). Ver `secrets/README.md`
para o caminho de migração para SOPS+age (`app-passwords.enc.yaml`).

Se `docs/CREDENTIALS.local.md` não existir na sua cópia local, veja a nota
"Se este arquivo for perdido" dentro dele mesmo (fontes: `helm-values.yaml`
de cada serviço, `kubernetes/shared-infra/*/secret.yaml`) — ou peça pra
quem tem acesso reencriptar/compartilhar via o fluxo já documentado em
`secrets/README.md`.

---

## 7. Troubleshooting — problemas conhecidos

Esta seção documenta problemas encontrados durante a implantação e suas soluções.

---

### P1: Ansible conecta com usuário errado

**Sintoma:** `Permission denied (publickey,password)` mesmo passando `-u <usuario>`.

**Causa:** `ansible_user: labadmin` em `group_vars/all.yml` tem precedência sobre a flag `-u` da linha de comando. Apenas `-e` (extra vars) consegue sobrescrever.

**Solução:**

```bash
ansible-playbook ... -e "ansible_user=netomussauer"
```

---

### P2: NFS — `Protocol not supported`

**Sintoma:** `mount.nfs: Protocol not supported` ao montar share NFS.

**Causa:** NAS Seagate Black Armor suporta apenas NFSv3.

**Solução:** usar `nfsvers=3` em todas as opções de montagem. Ver `ansible/inventory/group_vars/all.yml` e `kubernetes/bootstrap/storage/nfs-csi-values.yaml`.

---

### P3: NFS — `Operation not permitted` em init containers

**Sintoma:** init container falha com `chown /data: Operation not permitted`.

**Causa:** NAS impõe `root_squash` (sem opção de desabilitar na interface web). Requisições de `chown` do UID 0 são mapeadas para `nobody` e negadas.

**Solução:** usar `local-path` StorageClass para todos os workloads. Ver [ADR-005](./adr.md#adr-005).

---

### P4: Gitea — chart v12 falha com SQLite

**Sintoma:** `configure-gitea: SQLite: unable to open database file`.

**Causa:** chart gitea v12 não monta o volume de dados no init container `configure-gitea`, tornando SQLite inacessível durante a configuração.

**Solução:** habilitar PostgreSQL bundled no `helm-values.yaml`:

```yaml
postgresql:
  enabled: true
  global:
    postgresql:
      auth:
        username: "gitea"
        password: "gitea123"
        database: "gitea"
```

Ver [ADR-008](./adr.md#adr-008).

---

### P5: Gitea chart v12 — imagem não encontrada

**Sintoma:** `ImagePullBackOff` tentando puxar `docker.gitea.com/gitea/gitea:1.21-rootless`.

**Causa:** chart v12 mudou o registry padrão para `docker.gitea.com` e o appVersion para `1.25.5`.

**Solução:** definir explicitamente no `helm-values.yaml`:

```yaml
image:
  registry: ""
  repository: gitea/gitea
  tag: "1.25.5"
  rootless: false
```

---

### P6: Gitea chart v12 — Valkey CrashLoopBackOff

**Sintoma:** pod `valkey-cluster-*` em CrashLoopBackOff logo após a instalação.

**Causa:** chart v12 substituiu `redis-cluster` por `valkey-cluster`. Se o values antigo tinha `redis-cluster.enabled: false` mas não desabilitava `valkey-cluster`, o Valkey tenta inicializar com configuração inválida.

**Solução:**

```yaml
valkey-cluster:
  enabled: false
valkey:
  enabled: false
redis-cluster:
  enabled: false
redis:
  enabled: false
```

---

### P7: MetalLB — `can't change sharing key`

**Sintoma:** serviço `gitea-http` não consegue IP porque `gitea-ssh` já alocou `192.168.1.201`.

**Causa:** dois Services queriam o mesmo IP sem a annotation de sharing, ou a configuração de `gitea-ssh` como LoadBalancer bloqueou o IP.

**Solução:** mudar o serviço SSH para NodePort:

```yaml
service:
  http:
    type: LoadBalancer
    port: 3000
    loadBalancerIP: "192.168.1.201"
  ssh:
    type: NodePort
    port: 22
    nodePort: 30022
```

---

### P8: Helm — release em `pending-install`

**Sintoma:** `helm upgrade --install` com `--wait` excede o timeout e deixa o release em estado `pending-install`, bloqueando upgrades subsequentes com `cannot re-use a name that is still in use`.

**Causa:** o `--wait` aguarda os pods ficarem Ready antes de retornar. Se um pod demorar mais que o timeout, o processo é interrompido mas o release fica em estado travado.

**Solução:** aguardar o release mudar para `failed` (acontece automaticamente após alguns minutos) e então rodar `helm upgrade` novamente sem `--wait`:

```bash
helm list -n <namespace>  # aguardar STATUS = failed
helm upgrade <release> <chart> -f <values> -n <namespace> --timeout 5m
```

---

### P9: Tekton — `unknown field spec.steps[].resources`

**Sintoma:** `Error from server (BadRequest): error when applying patch ... unknown field "spec.steps[0].resources"`.

**Causa:** API `tekton.dev/v1` renomeou o campo de recursos de containers de `resources` para `computeResources`.

**Solução:** substituir `resources:` por `computeResources:` em todos os steps de todas as Tasks:

```yaml
# Errado (v1beta1):
steps:
  - name: clone
    resources:
      requests:
        cpu: "50m"

# Correto (v1):
steps:
  - name: clone
    computeResources:
      requests:
        cpu: "50m"
```

---

### P10: Tekton EventListener — `must not set containers[0].name`

**Sintoma:** `admission webhook denied the request: must not set containers[0].name`.

**Causa:** o admission webhook do Tekton Triggers proíbe definir o campo `name` no container do pod template do EventListener.

**Solução:** remover qualquer `name:` dentro do bloco `containers` do `kubernetesResource`.

---

### P11: Tekton EventListener — `selector does not match template labels`

**Sintoma:** `Deployment.apps "el-gitea-event-listener" is invalid: spec.template.metadata.labels: Invalid value ... selector does not match template labels`.

**Causa:** adicionar `metadata.labels` no pod template do `kubernetesResource` do EventListener conflita com o seletor gerado automaticamente pelo Tekton.

**Solução:** remover o bloco `metadata.labels` do pod template. O EventListener gera o Deployment com seu próprio seletor — não interferir:

```yaml
# Errado:
spec:
  template:
    metadata:
      labels:                  # ← REMOVER este bloco inteiro
        app.kubernetes.io/name: "gitea-event-listener"
    spec:
      nodeSelector: ...

# Correto:
spec:
  template:
    spec:
      nodeSelector:
        workload: "cicd"
```

---

### P12: Tekton EventListener — CrashLoopBackOff por RBAC

**Sintoma:** pod do EventListener em CrashLoopBackOff com logs:

```
clusterinterceptors.triggers.tekton.dev is forbidden: cannot list resource "clusterinterceptors" at the cluster scope
clustertriggerbindings.triggers.tekton.dev is forbidden: cannot list resource "clustertriggerbindings" at the cluster scope
```

**Causa:** a ServiceAccount do EventListener tem um ClusterRoleBinding para `tekton-triggers-eventlistener-roles` (recursos namespaced), mas não para `tekton-triggers-eventlistener-clusterroles` (recursos cluster-scoped como `ClusterInterceptor`).

**Solução:** adicionar um segundo ClusterRoleBinding:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tekton-triggers-cicd-clusterinterceptors
subjects:
  - kind: ServiceAccount
    name: tekton-triggers-sa
    namespace: cicd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tekton-triggers-eventlistener-clusterroles
```

---

### P13: kube-prometheus-stack — `selector does not match template labels`

**Sintoma:** `DaemonSet.apps "kube-prometheus-stack-prometheus-node-exporter" is invalid: spec.template.metadata.labels: Invalid value ... selector does not match template labels`.

**Causa:** uso de `commonLabels` no `helm-values.yaml`. O Helm aplica esses labels aos templates de todos os sub-charts, mas os seletores dos DaemonSets dos sub-charts (como `prometheus-node-exporter`) não incluem esses labels extras, causando inconsistência.

**Solução:** remover o bloco `commonLabels` do `helm-values.yaml`. Usar `podLabels` por componente quando necessário (esses labels são adicionados apenas ao pod template, não ao seletor).

```yaml
# Remover do helm-values.yaml:
commonLabels:       # ← REMOVER
  environment: "lab"
  lab_id: "lab-k8s-01"
```

---

### P14: loki-stack — volumes duplicados no Promtail

**Sintoma:** `DaemonSet.apps "loki-promtail" is invalid: spec.template.spec.volumes[6].name: Duplicate value: "run"`.

**Causa:** o chart `loki-stack` já inclui por padrão volumes para `/var/log`, `/var/lib/docker/containers` e `/run/promtail`. Adicionar esses mesmos volumes em `extraVolumes` causa duplicação.

**Solução:** remover os volumes que o chart já cria dos blocos `extraVolumes` e `extraVolumeMounts`. Manter apenas volumes verdadeiramente adicionais.

---

### P15: loki — `field embedded_cache not found`

**Sintoma:** pod `loki-0` em CrashLoopBackOff com log `failed parsing config: field embedded_cache not found in type cache.Config`.

**Causa:** a opção `embedded_cache` no bloco `query_range.results_cache.cache` não existe no Loki v2.9.x (foi adicionada em versões posteriores).

**Solução:** remover o bloco `query_range` do `helm-values.yaml`:

```yaml
# Remover:
    query_range:
      results_cache:
        cache:
          embedded_cache:
            enabled: true
            max_size_mb: 100
```

---

### P16: Ansible playbook 04 — `k3s_join_token not found`

**Sintoma:** `Error while resolving value for 'cmd': object of type 'HostVarsVars' has no attribute 'k3s_join_token'`.

**Causa:** o playbook `04-k3s-agents.yml` tem dois plays: Play 1 lê o token do `k3s_server`, Play 2 instala nos agents. Ao usar `--limit <agent>` sem incluir `k3s_server`, Play 1 é pulado e o token não fica disponível.

**Solução:** incluir `k3s_server` no `--limit`:

```bash
ansible-playbook ... --limit 'k3s_server,notebook-i5'
```

---

### P17: ansible.cfg — callback plugin removido

**Sintoma:**

```
[ERROR]: The 'community.general.yaml' callback plugin has been removed...
```

**Causa:** versão mais recente do `ansible` removeu o callback `community.general.yaml`.

**Solução:** atualizar `ansible/ansible.cfg`:

```ini
[defaults]
stdout_callback = ansible.builtin.default
result_format = yaml
```

---

### P18: K3s agent no Raspberry Pi — memory cgroup não encontrado

**Sintoma:**

```
[INFO]  Failed to find memory cgroup, you may need to add "cgroup_memory=1 cgroup_enable=memory"
        to your linux cmdline (/boot/firmware/cmdline.txt on a Raspberry Pi)
Job for k3s-agent.service failed because the control process exited with error code.
```

**Causa:** Raspbian com kernel ≥6.x usa **cgroups v2 puro** (`CONFIG_MEMCG_V1 is not set`). O script de instalação do K3s busca `/sys/fs/cgroup/memory/` (cgroups v1), não encontra, e emite o aviso — mas esse caminho não existe em cgroupsv2. O agente falha na startup porque as ferramentas `iptables`/`ip6tables` também não estavam no PATH do ambiente de serviço.

**Diagnóstico:**

```bash
# Verificar cgroups
cat /proc/cgroups | grep memory          # vazio = sem cgroup v1 memory
cat /sys/fs/cgroup/cgroup.controllers    # deve listar "memory" = cgroup v2 OK
mount | grep cgroup                      # deve mostrar "cgroup2"

# Verificar iptables
sudo iptables --version
```

**Solução:**

1. Adicionar parâmetros ao cmdline.txt (necessário mesmo em cgroupsv2 para K3s 1.29):

   ```bash
   sudo sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
   ```

1. Instalar iptables (em `/usr/sbin`, não `/usr/bin`):

   ```bash
   sudo apt-get install -y iptables iptables-persistent
   ```

1. Se K3s já foi instalado com falha, remover antes de reinstalar:

   ```bash
   sudo /usr/local/bin/k3s-agent-uninstall.sh
   ```

1. Reiniciar o RPi:

   ```bash
   sudo reboot
   ```

1. Após reboot, re-executar o playbook (o agente instala e sobe normalmente):

   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/04-k3s-agents.yml \
     --limit 'k3s_server,raspberry-pi'
   ```

**Referência:** K3s 1.29.x suporta cgroupsv2 nativamente. O aviso sobre `/boot/firmware/cmdline.txt` é um falso positivo quando o kernel já usa cgroupsv2, mas os parâmetros de kernel ainda são necessários para que o K3s inicialize corretamente o kubelet.

---

### P19: Playbook 04 — `k3s_join_token not found` ao usar `--limit`

**Sintoma:**

```text
fatal: [raspberry-pi]: FAILED! => {"msg": "The task includes an option with an undefined variable. 'k3s_join_token' is undefined"}
```

**Causa:** ao usar `--limit raspberry-pi`, o Play 1 (que lê o token no `k3s_server`) é pulado porque o host do server não está no limite.

**Solução:** sempre incluir o servidor no limit para este playbook:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/04-k3s-agents.yml \
  --limit 'k3s_server,raspberry-pi'
```

---

### P20: musl libc — `getaddrinfo` falha em pods Alpine (Gitea, apk update, etc)

**Sintoma:**

- `getent hosts github.com` retorna exit code 2 sem output em pod Alpine/musl
- `git ls-remote https://github.com/...` falha com `Could not resolve host`
- `apk update` falha com `temporary error (try again later)` em pods Alpine
- `nslookup` (busybox) **funciona** porque usa `/etc/resolv.conf` direto, sem `getaddrinfo()`

**Causa:** musl libc tem comportamento bugado no `getaddrinfo()` quando combinado com `options ndots:5` (default do Kubernetes), múltiplos search domains, e queries paralelas A + AAAA contra CoreDNS. Documentado em <https://github.com/gliderlabs/docker-alpine/issues/8>.

**Diagnóstico:**

```bash
# Pod Alpine no cluster
kubectl exec -n cicd <pod> -c <container> -- sh -c '
  echo "--- nslookup (deve funcionar)"
  nslookup github.com
  echo "--- getent (DEVE FALHAR antes do fix)"
  getent hosts github.com
'
```

**Solução:** adicionar `dnsConfig` com `ndots:1` e `single-request-reopen` ao Deployment Alpine (Gitea v1.25.5 e qualquer outro pod Alpine futuro). No helm-values do Gitea (`kubernetes/cicd/gitea/helm-values.yaml`):

```yaml
dnsPolicy: None
dnsConfig:
  nameservers:
    - 10.43.0.10           # Service IP do CoreDNS
  searches:
    - cicd.svc.cluster.local
    - svc.cluster.local
    - cluster.local
  options:
    - name: ndots
      value: "1"           # default era 5, força queries de hostnames "puros"
    - name: single-request-reopen   # evita race A/AAAA do musl
```

Para outros pods Alpine ad-hoc, aplicar o mesmo bloco em `spec.template.spec` (Deployment) ou `spec` (Pod).

---

### P21: Gitea — `Recreate` strategy obrigatória com 1 réplica + LevelDB

**Sintoma:** ao fazer `kubectl rollout` ou `helm upgrade` no Gitea, o novo pod fica em `CrashLoopBackOff` com erro:

```text
Failed to create queue "notification-service":
unable to lock level db at /data/queues/common: resource temporarily unavailable
```

**Causa:** `replicaCount: 1` + `strategy: RollingUpdate` (default) faz com que o novo pod tente iniciar **antes** do antigo terminar. Como o PVC é `ReadWriteOnce` e ambos os pods são agendados no mesmo nó (`k3s-worker-cicd`), eles montam o mesmo volume — e o LevelDB em `/data/queues/common` só permite um único processo segurando o lock.

**Solução:** definir `strategy.type: Recreate` no helm-values:

```yaml
strategy:
  type: Recreate
  rollingUpdate: null
```

Aceita um pequeno blip de indisponibilidade (~30s) durante upgrades, mas elimina o crash loop.

---

### P22: CoreDNS pinned em k3s-server por imagem ausente nos workers

**Sintoma:** após `kubectl rollout restart deployment/coredns -n kube-system`, novo pod fica em `ImagePullBackOff` em outros nós. Apenas `k3s-server` tem a imagem `rancher/mirrored-coredns-coredns:1.10.1` cacheada.

**Workaround temporário (anti-pattern):**

```bash
kubectl patch deploy coredns -n kube-system --type=strategic \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k3s-server"}}}}}'
```

**Solução definitiva:**

1. Pre-pull da imagem em todos os nós workers:

   ```bash
   for IP in 192.168.1.31 192.168.1.32 192.168.1.65 192.168.1.110; do
     ssh -i ~/.ssh/lab_id_rsa labadmin@$IP \
       "sudo crictl pull rancher/mirrored-coredns-coredns:1.10.1"
   done
   ```

1. Remover o nodeSelector custom:

   ```bash
   kubectl patch deploy coredns -n kube-system --type=json \
     -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector/kubernetes.io~1hostname"}]'
   ```

1. Escalar para 2 réplicas (HA real):

   ```bash
   kubectl scale deploy coredns -n kube-system --replicas=2
   ```

---

### P23: Harbor TLS — `x509: certificate signed by unknown authority` no image pull

**Sintoma:** ao criar um Pod com `image: harbor.lab.local/<projeto>/<app>:<tag>`, o pod fica em `ImagePullBackOff` com evento:

```text
Failed to pull image "harbor.lab.local/amfit/api:latest":
... tls: failed to verify certificate: x509: certificate signed by unknown authority
```

**Causa:** o Harbor usa certificado autoassinado pelo CA interno `harbor-ca` (não confiado pelo trust store padrão do SO de cada nó). O `containerd` valida TLS contra `/etc/ssl/certs/ca-certificates.crt` e rejeita.

**Por que `registries.yaml` com `insecure_skip_verify: true` NÃO funciona:**

K3s v1.29.3 gera o `/var/lib/rancher/k3s/agent/etc/containerd/certs.d/<host>/hosts.toml` em formato legacy (top-level `skip_verify`), mas o containerd 1.7+ requer `skip_verify` dentro do bloco `[host."..."]`. A config é gerada mas ignorada no handshake. Editar manualmente o arquivo é inútil — K3s sobrescreve no próximo restart.

**Solução:** instalar o CA do Harbor no trust store de cada nó.

```bash
# Playbook idempotente que extrai o CA do secret harbor-nginx do cluster
# e instala em /usr/local/share/ca-certificates/harbor-ca.crt dos 5 nós,
# depois roda update-ca-certificates e reinicia k3s/k3s-agent.
ansible-playbook -i inventory/hosts.yml playbooks/07-k3s-registries.yml
```

**Validar:**

```bash
# Em qualquer nó, curl SEM -k deve retornar HTTP 401 (auth obrigatória):
curl -sS -o /dev/null -w "%{http_code}\n" https://harbor.lab.local/v2/

# Pull real com credenciais — deve baixar sem TLS error:
sudo crictl pull --creds "admin:Harbor12345!" harbor.lab.local/<projeto>/<app>:latest
```

**Quando o CA do Harbor for rotacionado:** re-executar o playbook 07, nó a nó (`--limit`). Desde 2026-09-24 ele instala a CA **estável do repo** (`kubernetes/cicd/harbor/harbor-ca.crt`), não mais extraída do Secret — ver P28. Antes disso o Harbor usava `certSource: auto`, que regenera a CA a cada `helm upgrade`.

### P24: Terraform — providers quebrados impedem `plan`/`apply`/`import` (pendente de correção)

**Sintoma:** qualquer comando Terraform em `terraform/proxmox/` falha, mesmo operações que não deveriam tocar no NetBox (ex. `terraform import` de um recurso `proxmox_virtual_environment_vm`).

**Causa 1 — provider NetBox:** `e-breuninger/netbox` v5.3.0 falha na etapa de `configure` contra o NetBox 4.4.1 do lab:

```text
Error: 0xc... (*interface {}) is not supported by the TextConsumer, can be
resolved by supporting TextUnmarshaler interface
  with provider["registry.terraform.io/e-breuninger/netbox"]
```

Como o provider é declarado no mesmo `main.tf`, esse erro bloqueia **qualquer** comando Terraform no repo, mesmo os que não usam nenhum recurso `netbox_*`. A API do NetBox em si está saudável (confirmado via `curl` direto) — o bug é na comunicação interna do provider.

**Causa 2 — provider Proxmox:** `bpg/proxmox` v0.104.0 falha especificamente em `terraform import` de VM (`proxmox_virtual_environment_vm`) contra Proxmox VE 9.2.3:

```text
Error: failed to get resources list of type ("vm") for cluster: received an
HTTP 401 response - Reason: Authentication failed!
```

Confirmado que **não é problema de credencial** — o mesmo token (`root@pam!root`) funciona perfeitamente via `curl` direto nesse exato endpoint (`/cluster/resources?type=vm`), inclusive com permissões completas (`root@pam` é superuser). Testado com 5 tentativas e retry entre elas — falha de forma consistente, não é intermitência de rede.

**Impacto prático:** o `terraform.tfstate` deste repo está vazio/ausente (nunca houve um `apply`/`import` bem-sucedido nesta máquina) — as VMs do cluster K3s (`k3s-server`, `k3s-worker-cicd`, `ci-runner`, `k3s-worker-pve2`) existem e funcionam normalmente no Proxmox, mas o Terraform não tem registro delas. Um `terraform apply` às cegas tentaria recriar essas VMs do zero (provavelmente falhando por conflito de `vm_id`, não destruindo nada — mas travando feio).

**Solução (não aplicada ainda):** atualizar os dois providers para a versão mais recente disponível (`bpg/proxmox` e `e-breuninger/netbox`) e revalidar `terraform init`/`plan`/`import` antes de qualquer `apply` real. Só depois disso reconciliar o state com `terraform import` nas 4 VMs + todos os recursos de `netbox.tf` (ip_addresses, virtual_machines, prefixes, tags, site, tenant, cluster — nenhum está no state hoje).

**Workaround usado em 2026-09-18** para criar a VM `k3s-worker-pve2` sem depender do Terraform: clone manual via API do Proxmox (`qm clone` + `qm migrate` entre nós, já que clone direto cross-node falha com storage local não-compartilhado) + Ansible normal (`01-base-setup.yml` → `04-k3s-agents.yml` → `05-post-setup.yml`). O código Terraform equivalente já está escrito em `main.tf`/`netbox.tf`/`variables.tf`, só não foi importado.

### P25: Edge/Cloudflare Tunnel — dois gotchas na implantação inicial (2026-09-18)

Encontrados durante a implantação do `kubernetes/edge/` (túnel público, ver [ADR-013](./adr.md#adr-013)). Nenhum dos dois é bug de infra real — ambos são efeito de decisões de design deste próprio lab que precisam ser lembradas ao reaplicar ou depurar o namespace `edge`.

**1. Admission webhook do ingress-nginx falha com "502 Bad Gateway" ao criar/editar qualquer `Ingress`:**

```text
Internal error occurred: failed calling webhook "validate.nginx.ingress.kubernetes.io":
failed to call webhook: Post "https://ingress-nginx-controller-admission.edge.svc:443/...":
proxy error from 127.0.0.1:6443 while dialing 10.42.x.x:8443, code 502: 502 Bad Gateway
```

Causa: o apiserver conecta direto no pod IP do controller na porta `8443` — sem identidade de pod/namespace, então a `NetworkPolicy` do controller (`kubernetes/edge/cloudflared/networkpolicy.yaml`) precisa de uma regra `ipBlock: 0.0.0.0/0` liberando essa porta especificamente (só valida sintaxe de `Ingress`, não expõe tráfego de aplicação). Sem essa regra, a validação falha **cluster-wide, independente do nó onde o controller está rodando** — não confunda com um problema de rede do `k3s-worker-pve2` (foi a primeira hipótese testada e descartada). A regra já está no manifest atual; se recriar a `NetworkPolicy` do zero, não esquecer dela.

**2. `kubectl apply` manual em recurso gerenciado pelo ArgoCD é revertido em segundos:**

Qualquer app sob `kubernetes/apps/` (ex. `hello-lab`) é sincronizado pelo `app-of-apps` do ArgoCD com self-heal ativo. Editar o `Ingress`/`NetworkPolicy` localmente e aplicar com `kubectl apply` funciona só até o próximo ciclo de reconciliação (segundos, não minutos) — o ArgoCD reverte pro estado do Git automaticamente. Sintoma confuso: parece um problema de rede/CNI intermitente (a mudança "não pega"), mas na verdade é o `NetworkPolicy` antigo voltando.

**Fix:** commitar + dar push antes de validar (`git push origin main` — o `app-of-apps` aponta pro GitHub direto, não pro Gitea, ver `kubernetes/cicd/argocd/app-of-apps.yaml`). Para forçar sync imediato sem esperar o polling padrão do ArgoCD:

```bash
kubectl patch application app-of-apps -n cicd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

**Implicação para onboarding de projetos novos** (`kubernetes/edge/ingress-template.yaml`): se `amfit`/`amactive`/`realtpmsys`/`training-performance-hub` também forem ArgoCD-managed (confirmado para os 3 primeiros via `kubectl get application -n cicd`), o `Ingress`/`NetworkPolicy` do template só entra em vigor de verdade depois de commitado no repo de cada projeto — testar com `kubectl apply` direto dá falso negativo se o self-heal reverter antes da validação.

### P26: `ubuntu-neto` — IO do HDD saturado derruba pods e trava o containerd (2026-09-24)

**Sintoma:** builds Tekton (pinados no nó) falhando com `TLS handshake timeout`, `containerd` com `failed to reserve container name`/`context deadline exceeded`, `postgresql-0`/`redis-0` ~5 min em `ContainerCreating` após reboot, SSH com `Connection timed out during banner exchange`, `kubectl top` mostrando só ~15% CPU / ~50% RAM.

**Causa provável (não provada — SMART não foi lido):** o nó é um notebook com **um único HDD rotacional** (`sda`, `ROTA=1`) que hospeda containerd (31 GB), PVCs `local-path` (15 GB: Prometheus, Loki, Postgres, Redis, Pi-hole) e as camadas do kaniko. Medido: `%util` 74–99%, `r_await` 24–48 ms, `iowait` 39–73%, `/proc/pressure/io` `some avg10=41%`/`full 33%`; PSI de memória = 0 e swap = 0, então não é falta de RAM. Sob esse IO, `exec` probes com o `timeoutSeconds` padrão (1s) estouram, o kubelet mata os pods e gera restarts em cascata (`metallb-speaker` do nó: 6440 restarts em 147 dias, contra 4 nos outros nós). Agravantes: cabo negociado a **100 Mb/s** (`ethtool enp2s0`; deveria ser 1 Gb/s) e Ubuntu Desktop (GDM/GNOME/snaps) rodando no nó.

**Mitigações aplicadas em 2026-09-24:**

1. GDM parado e `default.target` = `multi-user.target` (reverter: `systemctl set-default graphical.target && systemctl start gdm3`).
2. `timeoutSeconds` explícito (5–10s) e `failureThreshold: 6` nas sondas de `postgresql`, `redis` e `postgres-exporter` (`kubernetes/shared-infra/`) — um engasgo de IO deixa de matar o pod.
3. Cabo de rede trocado: link voltou a **1000 Mb/s** (download real medido: 78,7 MB/s, antes ~12 MB/s).
4. **Grafana movido para o `k3s-worker-pve2` (SSD)** — `grafana.nodeSelector` = `kubernetes.io/hostname: k3s-worker-pve2` em `kubernetes/monitoring/kube-prometheus-stack/helm-values.yaml`. Depois do boot pós-troca de cabo, o Grafana 13 (SQLite + reconstrução de índices `bleve`, em loop de `database is locked`) lia ~27 MB/s do HDD e mantinha o IO PSI em 80–94%. Procedimento: `scale --replicas=0`, `delete pvc kube-prometheus-stack-grafana` (perde usuários/preferências locais; dashboards e datasources voltam via sidecars), `helm upgrade`, `scale --replicas=1`. Resultado medido no `ubuntu-neto`: IO PSI `some avg10` 80–94% → 1,5%, `iowait` 60–83% → ~0%.

**Pendente (correção durável):** builds Tekton fora do nó, ler SMART do disco e SSD no lugar do HDD (ou mover Pi-hole/Postgres/Redis/Prometheus/Loki para o worker do `pve2`, que tem SSD; hoje 47% de RAM usada lá, então há pouca folga além do Grafana). Diagnóstico: `iostat -x 1 3`, `cat /proc/pressure/io`, `ethtool enp2s0 | grep Speed`, `sudo smartctl -H -A /dev/sda` (smartmontools não estava instalado).

### P27: Harbor — `harbor-database` morto por sonda de 1s; push do kaniko falha com 401/"stopped after 10 redirects" (2026-09-24)

**Sintoma:** builds Tekton (ex. `amactive`, 15–17/set) compilam tudo e falham só no push: `stopped after 10 redirects` no `/service/token`, `401 Unauthorized` em `HEAD /v2/.../manifests`, `checking push permission … POST /v2/.../blobs`. Builds de API só passam no pod `-retry1`. `harbor-database-0` com **16 restarts** (exit 137).

**Causa provável (correlação, não prova):** todo o Harbor (database, registry, redis, trivy, core) tem PVC `local-path` no **mesmo disco do `k3s-worker-cicd`**, onde também rodam os builds kaniko (IO PSI `some avg10` 18% medido; ~12,9 h acumuladas de stall de IO em 48 dias de uptime). O healthcheck do banco (`/docker-healthcheck.sh`) tinha `timeoutSeconds: 1` (padrão do chart 1.19.2): num engasgo de IO ele falha, o kubelet mata o Postgres, que leva > 1 min para desligar (`the database system is shutting down` a cada 10s) e acaba com SIGKILL. Sem banco, o token service do Harbor falha e o push quebra. Memória não é a causa (banco usa ~71 MiB de 1 GiB). Os pods de build antigos em `Error` eram só resíduo — todos os builds do `amactive` desde 18/set completaram. Já documentado nos comentários do `trigger-amfit.yaml` (retries mascaram o problema; builds do amfit fixados no `ubuntu-neto` para evitar o Harbor no `cicd`).

**Mitigação aplicada em 2026-09-24** (`kubernetes/cicd/harbor/helm-values.yaml`, `helm upgrade harbor … --version 1.19.2`): `database.internal` liveness/readiness com `timeoutSeconds: 10` e `failureThreshold: 6`; `redis.internal` 5s/6; `core` liveness/readiness/startup com `timeoutSeconds: 5` (padrão do chart era 1s e `failureThreshold: 2`). Pós-upgrade: token de push 200 sem redirects, todos os pods `Running`.

**Isolamento de IO aplicado em 2026-09-24 — Postgres do Harbor movido para o `k3s-worker-pve2` (SSD):** `database.internal.nodeSelector` = `kubernetes.io/hostname: k3s-worker-pve2` em `kubernetes/cicd/harbor/helm-values.yaml`. O banco é pequeno (13 MB; 5 projetos, 10 repositórios, 150 artefatos, 49 tabelas); os blobs das imagens continuam no PVC `harbor-registry` do nó cicd. Procedimento (reutilizável): (1) sem build em andamento, `pg_dumpall` via `kubectl exec harbor-database-0 -c database` para `~/harbor-backup/` (modo 600) + contagens de linha de referência; (2) `kubectl patch pv <pv> reclaimPolicy=Retain` (a StorageClass `local-path` é `Delete`); (3) escalar `harbor-core`/`jobservice`/`registry` e `harbor-trivy` a 0, depois `harbor-database` a 0, e apagar o PVC; (4) `helm upgrade` com o `nodeSelector` novo **e `--set core.replicas=0 jobservice.replicas=0 registry.replicas=0 trivy.replicas=0`** (senão o core sobe contra o banco vazio e cria o schema antes do restore); (5) subir o banco, `drop database registry` (criado vazio pelo initdb) e restaurar o dump com `psql -U postgres < dump.sql` (o único erro esperado é `role "postgres" already exists`); (6) conferir as contagens contra a linha de base; (7) `helm upgrade` final só com o arquivo de valores. Resultado: contagens idênticas, `/api/v2.0/health` = healthy, token de push 200 sem redirects. Downtime do Harbor: ~10 min.

**Rollback / limpeza:** o PV antigo (`pvc-1cb5d066-6069-49d7-bdd0-8be0214ab724`, `Retain`/`Released`) e o dump em `~/harbor-backup/` foram mantidos. Depois de alguns dias estável: `kubectl delete pv pvc-1cb5d066-…` e remover `/var/lib/rancher/k3s/storage/pvc-1cb5d066-…` no `k3s-worker-cicd` (com `Retain`, apagar o PV não apaga o diretório). A RAM do worker do `pve2` **não foi aumentada**: o host tem só ~2 GB realmente livres (5,74 de 7,72 GB usados) e o banco usa ~70 MiB, então não compensou o risco.

**Pendente:** os builds continuam gravando no disco do `k3s-worker-cicd` (blobs do registry incluídos) — confirmar a melhoria medindo `dmesg`/`iostat` durante um build real. Também: bancos/usuários de `amactive` e `training_hub` fora do initdb do Postgres compartilhado (ver `context/facts/shared-infra-databases.md`).

> **Atenção (P28):** os `helm upgrade` deste procedimento, feitos com `certSource: auto`, regeneraram a CA do Harbor e quebraram o TLS dos nós. Corrigido em P28 (certificado estável); com `certSource: secret` um `helm upgrade` do Harbor não mexe mais na CA.

### P28: Harbor — `x509: certificate signed by unknown authority` após `helm upgrade` (CA regenerada) (2026-09-24)

**Sintoma:** depois de um `helm upgrade` do Harbor, `ImagePullBackOff` em pods com `imagePullPolicy: Always` (`x509: certificate signed by unknown authority (possibly because of "crypto/rsa: verification error" while trying to verify candidate authority certificate "harbor-ca")`), `curl` sem `-k` no nó dá erro de TLS, e pipelines Tekton quebram no push.

**Causa (confirmada):** com `expose.tls.certSource: auto` o chart 1.19.2 **gera uma CA `harbor-ca` nova a cada `helm upgrade`** (não só na instalação). Os nós confiam numa cópia da CA instalada em `/usr/local/share/ca-certificates/harbor-ca.crt` (playbook 07), que fica obsoleta. Evidência: `helm history harbor -n registry` (revisões 4–6, todas em 24/09) e o certificado servido com `notBefore` = horário exato da última revisão; nós com CAs de 29/abr (ubuntu-neto) e 14/set (demais), nenhuma igual à servida. As revisões 2 (2/set) e 3 (14/set) já haviam regenerado a CA; o `ubuntu-neto`, `ci-runner` e `raspneto` nunca foram atualizados depois disso.

**Correção durável aplicada em 2026-09-24:**

1. CA `harbor-ca` (10 anos, `CN=harbor-ca, O=infra-lab`) e certificado do servidor (825 dias, SAN `harbor.lab.local` + `192.168.1.202`) **gerados do zero** com `openssl`. Chave da CA em `secrets/harbor-ca.enc.yaml` (SOPS; chaves `HARBOR_CA_KEY`/`HARBOR_CA_CRT`); CA pública em `kubernetes/cicd/harbor/harbor-ca.crt`; Secret `harbor-tls` (`tls.crt`, `tls.key`, `ca.crt`) selado em `kubernetes/cicd/harbor/harbor-tls-sealedsecret.yaml` (scope strict, namespace `registry`).
2. `helm-values.yaml` do Harbor: `expose.tls.certSource: secret` + `secret.secretName: harbor-tls`. **Não voltar para `auto`.**
3. Playbook `07-k3s-registries.yml` passou a instalar a CA do repo (não mais extraída do cluster). Rodado nos 6 nós, um de cada vez (`--limit`), com verificação de chave de host ligada — o `ansible.cfg` do repo desliga (`StrictHostKeyChecking=no`), então sobrescrever com `ANSIBLE_HOST_KEY_CHECKING=True` e `ANSIBLE_SSH_ARGS="-C -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=accept-new"`. Ordem usada: `k3s-worker-cicd`, `k3s-worker-pve2`, `ci-runner`, `raspneto`, `k3s-server`, `ubuntu-neto` (cada um reinicia `k3s`/`k3s-agent`).
4. Validação: `openssl s_client -CAfile kubernetes/cicd/harbor/harbor-ca.crt` → `Verification: OK`; nos 6 nós, fingerprint da CA `26:27:5C:77:…:90:8B:16` e `curl` sem `-k` → 401.

**Renovar o certificado do servidor (825 dias, expira em ~dez/2028):** decriptar a chave da CA de `secrets/harbor-ca.enc.yaml` (`sops -d`), emitir novo `tls.crt`/`tls.key` com a mesma CA, refazer o SealedSecret e `kubectl apply`; **não há necessidade de tocar nos nós** enquanto a CA for a mesma. Trocar a CA exige rodar o playbook 07 nos 6 nós.

**Pendências / observações:**

- **Inventário Ansible corrigido em 2026-09-24:** `notebook-i5` (`192.168.1.65`) virou `ubuntu-neto` (`192.168.1.67`) e `raspberry-pi` virou `raspneto`, para bater com os nomes/IPs reais dos nós (os playbooks usam `{{ inventory_hostname }}` em `kubectl get/label node` — com os nomes antigos o `05-post-setup` nunca rotulava esses dois nós). O registro `ubuntu-neto.lab.local` do Pi-hole (`kubernetes/network-services/pihole/configmap-records.yaml`) foi corrigido para `192.168.1.67` em 2026-09-24 (ConfigMap aplicado + `rollout restart deployment/pihole`, pois o mount é `subPath`; janela de DNS de ~21 s, 8 consultas de 1/s falharam — o Pi-hole já falhava 4 de 7 consultas antes do restart, ver abaixo). Ainda com o nome/IP antigo: IP `192.168.1.65` em `terraform/proxmox/netbox.tf` e os devices `notebook-i5`/`raspberry-pi` de `00-netbox-register.yml`, além de `scripts/bootstrap.sh`, `scripts/init-baremetal.sh` e `scripts/k8s-bootstrap.sh` (comentários/menus) — não alterados porque NetBox/Terraform mudariam dados vivos. Registros `k3s-worker-pve2.lab.local` (`192.168.1.33`) e `app.realtpmsys.local` (LB `192.168.1.211`) adicionados ao ConfigMap em 2026-09-24 (novo restart do Pi-hole, janela de DNS de ~24 s, 9 consultas de 1/s falharam). O `app.realtpmsys.local` **já resolvia antes do restart**, isto é, existia no Pi-hole fora do ConfigMap (cadastro manual pela UI, guardado no PVC `pihole-etc`) — pode haver outros registros assim; o ConfigMap não é a única fonte. Ainda ausentes no ConfigMap: `pve2.lab.local` (`192.168.1.21`) e `bookstack.lab.local` (`192.168.1.64`). **Observação:** antes do restart, consultas de `ubuntu-neto`, `harbor`, `gitea` e `grafana` ao Pi-hole (`192.168.1.53`) davam timeout (4 de 7), e depois todas responderam — o Pi-hole roda no `ubuntu-neto` (HDD saturado, P26). **Ressalva (2026-09-25):** essas consultas foram feitas do WSL do dono, cuja rede até a LAN estava instável (RTT de 30–240 ms para o gateway e o `.30`, e um `no route to host` transitório), então o timeout pode ser do caminho do PC e não do Pi-hole — não confirmado; para medir o Pi-hole, consultar a partir de um nó do cluster.
- O `ansible.cfg` mantém `StrictHostKeyChecking=no` e `group_vars/all.yml` usa `UserKnownHostsFile=/dev/null` — decisão antiga, não alterada aqui.
- A task kaniko compartilhada (`kubernetes/cicd/tekton/pipeline-build-push.yaml`) usa `--skip-tls-verify`; o `amactive` usa `--skip-tls-verify-registry`. Não foi alterado.
- O erro `stopped after 10 redirects` no `/service/token` (visto em 15–17/set, antes deste incidente) é uma causa separada e **continua sem diagnóstico**.
- `helm-values.yaml` do Harbor ainda contém `harborAdminPassword` e `secretKey` em texto puro no repo (pré-existente).

### P29: BookStack — IP DHCP mudou após a migração para o pve2; docs/Terraform apontavam para um IP sem host (2026-09-24)

**Sintoma:** `bookstack.lab.local` não existia no Pi-hole e o IP documentado do BookStack (`192.168.1.76`, em README, `docs/architecture.md`, `terraform/proxmox/netbox.tf`, `scripts/bookstack-sync/` e `secrets/README.md`) não respondia (100% de perda, sem host).

**Causa provável (não confirmada):** o CT 106 usa `ip=dhcp` e pegou outro lease ao ser migrado de `virt` para `pve2` em 2026-09-18 (uptime do CT ~6,4 dias na medição). O IP real era `192.168.1.64` (`GET /nodes/pve2/lxc/106/interfaces`), com o BookStack respondendo (`/login` 200). A migração não conferiu o IP depois.

**Correção aplicada em 2026-09-24:** `net0` do CT 106 trocado para IP estático preservando o MAC (`name=eth0,bridge=vmbr0,gw=192.168.1.254,hwaddr=BC:24:11:8D:3A:DF,ip=192.168.1.64/24,type=veth`) e `nameserver: 192.168.1.254 1.1.1.1` (o DNS vinha do DHCP; sem isso o CT herdaria o `127.0.0.1` do host). A mudança de rede de um LXC só vale após `POST /nodes/pve2/lxc/106/status/reboot` (~25 s até o `/login` responder). Repo: `.76` → `.64` em todos os arquivos; registros `bookstack.lab.local` (`.64`) e `pve2.lab.local` (`.21`) adicionados ao ConfigMap do Pi-hole (restart do Pi-hole, janela de DNS de ~25 s, 9 consultas de 1/s falharam).

**NetBox:** o registro real do BookStack (`.76`) foi corrigido para `.64` em 2026-09-25 (ver P31); o `netbox_ip_address` em `terraform/proxmox/netbox.tf` já estava com `.64`. O IP do CT `netbox` (100), migrado no mesmo dia, estava certo (`192.168.1.72`, estático), só a descrição dizia "@ virt". Lição para migrações de CT: conferir `interfaces` do guest e fixar IP estático antes de migrar.

### P30: Harbor — `stopped after 10 redirects` no `/service/token` durante o push do kaniko (2026-09-25)

**Sintoma:** o push do kaniko (Tekton, `kaniko-build-push`) falha de forma intermitente com `Get "https://harbor.lab.local/service/token?scope=repository%3A<projeto>%2F<app>%3Apush%2Cpull&service=harbor-registry": stopped after 10 redirects` (ou `creating push check transport for harbor.lab.local failed: … stopped after 10 redirects`). O retry costuma passar. Ocorrências vistas: 15–17/set (`amactive`), 24/set 18:03 e 18:16 (`amfit-web`) e 25/set 15:06 (`amactive-web`, **depois** da correção da CA — não tem relação com o certificado, P28).

**Causa (confirmada no código, `go-containerregistry` v0.19.0 — a versão do kaniko v1.21/v1.23):**

1. `pkg/name/registry.go`: `reLocal = .*\.local(?:host)?…` → `Scheme()` devolve `"http"` para `harbor.lab.local`.
2. `pkg/v1/remote/transport/ping.go`: com `Scheme()=="http"` o `Ping` usa `pingParallel`: sonda HTTPS primeiro e, se ela não responder em `fallbackDelay`, dispara em paralelo uma sonda HTTP; **vale a primeira que der sucesso**. A sonda HTTP bate na porta 80 do nginx do Harbor (`301` → https → `401`) e também "dá sucesso"; se ganhar a corrida o esquema `http` é gravado.
3. `schemer.go` (`schemeTransport`): passa a reescrever para o esquema vencedor toda requisição ao host do registro, inclusive `/service/token`. O nginx responde `301` para https, o cliente segue e é reescrito de volta para http — 10 vezes.

**Evidência (Loki, nginx do Harbor, 21–25/set):** nos dois eventos investigados a sequência é idêntica: `GET /v2/` **301** (sonda HTTP), dois `401`, depois `/service/token` **301 ×10**. A sonda HTTP disparou 8 vezes em 4,2 dias (HTTPS demorou > `fallbackDelay`) e venceu em 3 (as 3 falhas). **Todos os 38 acessos 3xx ao Harbor no período vieram do kaniko** — ninguém mais usa a porta 80. Por que o HTTPS às vezes demora: provavelmente engasgo de rede/IO no nó no instante do ping (hipótese, não medido).

**Mitigação aplicada em 2026-09-25:** `expose.loadBalancer.ports.httpPort: 8081` em `kubernetes/cicd/harbor/helm-values.yaml` (antes `80`), via `helm upgrade`. Sem nada ouvindo na 80 do LB a sonda HTTP **não consegue mais dar sucesso**, então só o HTTPS pode vencer. Efeitos: (a) `http://harbor.lab.local` deixa de funcionar — de um nó a porta 80 agora **estoura em 5 s** (o pacote é descartado, não recusado); HTTPS responde em ~0,2 s; (b) o `helm upgrade` regenera os segredos internos do chart (chave de assinatura do core, `CSRF_KEY`, `REGISTRY_HTTP_SECRET`, htpasswd) e reinicia core/registry/jobservice por ~1–2 min; (c) o certificado (P28) não muda (mesmo fingerprint antes e depois). Docs atualizados para `https://` (`README.md`, `context/facts/lab-services-inventory.md`, comentário do `helm-values.yaml`).

**Validação feita:** `/api/v2.0/health` = healthy, `/service/token` = 200 sem redirects, pods todos `Running`. **Ainda não validado ponta a ponta:** nenhum build rodou depois da mudança; o próximo push do kaniko é o teste real. Se o erro reaparecer, a causa é outra (o HTTP:80 não é mais possível).

**Não corrige a biblioteca:** se o HTTPS falhar por outro motivo, o push falha normalmente (os `retries` dos pipelines continuam valendo). Alternativas descartadas: registro com hostname sem `.local` (exigiria trocar o `config.json` de credenciais por host); `--insecure` (força http).

**Observação de processo:** o passo "há build em andamento?" do script de upgrade usou `kubectl … | wc -l`; com a API inacessível (`no route to host` a partir do PC do dono) a contagem saiu `0` por engano e o upgrade rodou sem a checagem real. Verificação posterior confirmou que nenhum PipelineRun estava ativo. Em scripts, tratar falha do `kubectl` como erro, não como zero.

**Pendente:** `docs/CREDENTIALS.local.md` (arquivo local, fora do git) e o README do `amfit` (`amfit/infra/tekton/README.md`, exemplo de `curl` para a API do Harbor) ainda citam `http://harbor…`.

### P31: NetBox IPAM desatualizado — IPs deslocados, ausentes e descrições velhas (2026-09-25)

**Sintoma/achado:** auditoria dos IPs de `192.168.1.0/24` no NetBox contra o cluster, os CTs (API do Proxmox) e os LoadBalancers do MetalLB. Divergências: (1) BookStack registrado em `.76` (sem host) e nada em `.64`, o IP real (P29); (2) registros do MetalLB **deslocados em 1** — `.200` "Gitea", `.201` "Harbor", `.202` "ArgoCD", `.203` "Tekton EL", quando o real é `.201` Gitea, `.202` Harbor, `.203` ArgoCD, `.204` Tekton EL e `.200` livre; (3) `.65` ainda como `notebook-i5`, mas hoje é do **CT 105 `homepage`** (DHCP) e o `ubuntu-neto` está em `.67`, sem registro; (4) descrições velhas: CT `netbox` "@ virt" (é `pve2`), `immich` "CT 102" (é o CT 103); (5) sem registro: `.33` (`k3s-worker-pve2`), `.53` (Pi-hole), `.67`, `.204`–`.209`, `.211`.

**Correção aplicada em 2026-09-25 (API, credencial admin do NetBox):** 8 atualizações e 10 criações, todas listadas por `--dry-run` antes de aplicar; resultado 18 ok / 0 erro. `.76` foi **re-endereçado** para `.64` (mantém o histórico do objeto); `.200` passou a `reserved`; `dns_name` preenchido onde há registro no Pi-hole. **Backup do estado anterior:** `~/netbox-backup/ips-192.168.1.0-24-<data>.json` (WSL, modo 600, fora do repo). Re-auditoria com o token somente-leitura do agente confere com a realidade.

**Como reauditar:** listar `ipam/ip-addresses/?parent=192.168.1.0/24` e cruzar com `kubectl get nodes/svc`, `GET /nodes/<node>/lxc/<id>/interfaces` (Proxmox) e o ConfigMap do Pi-hole.

**Drift conhecido (não alterado):** o Terraform (`terraform/proxmox/netbox.tf`) e o playbook `00-netbox-register.yml` ainda declaram `notebook-i5`/`raspberry-pi` em `192.168.1.65` e não conhecem os registros criados aqui; como o Terraform não tem state e os providers estão quebrados (P24), o NetBox foi corrigido pela API e o código de IaC ficou defasado — reconciliar quando o P24 for resolvido, senão um `apply` recriaria os registros antigos. Sobram no NetBox IPs `Auto-discovered` (`.75`, `.97`, `.101`–`.103`, `.254`, `dns_name` `unknown`) do `netbox-sync-lab-ips.sh`, `.84` (ollama, `dhcp`, CT parado) e `.107` (HomeAssistant, não verificado).

**Pendente:** o CT 105 `homepage` (no `virt`) está em **DHCP com o IP antigo do ubuntu-neto** (`.65`) — fixar IP estático como no BookStack (P29); os CTs `ollama` (parado) e `omniroute` também são DHCP.
