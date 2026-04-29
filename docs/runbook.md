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
- NetBox configurado (192.168.1.72:8000) com token de API
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
export NETBOX_URL=http://192.168.1.72:8000
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
# http://192.168.1.72:8000/ipam/ip-addresses/

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

1. Acessar Gitea: `http://192.168.1.201` (ou `http://gitea.lab.local`)
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

### 4.6 Configurar /etc/hosts (ou DNS local)

Para acesso pelos nomes de domínio `.lab.local`:

```
192.168.1.201  gitea.lab.local
192.168.1.202  harbor.lab.local
192.168.1.203  argocd.lab.local
192.168.1.210  grafana.lab.local
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

> **Segurança:** as senhas abaixo são os valores padrão de instalação. Devem ser trocadas após o primeiro acesso em qualquer ambiente além de home lab completamente isolado.

| Serviço | URL | Usuário | Senha padrão |
|---|---|---|---|
| Gitea | `http://192.168.1.201` | `labadmin` | `labadmin123!` |
| Harbor | `http://192.168.1.202` | `admin` | `Harbor12345!` |
| ArgoCD | `http://192.168.1.203` | `admin` | ver secret abaixo |
| Grafana | `http://192.168.1.210` | `admin` | `lab@admin` |
| Proxmox | `https://192.168.1.20:8006` | `root` | definido na instalação |
| NetBox | `http://192.168.1.72:8000` | `admin` | definido na instalação |

```bash
# Senha inicial do ArgoCD:
kubectl -n cicd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Secret HMAC do webhook Tekton:
kubectl -n cicd get secret gitea-webhook-secret \
  -o jsonpath='{.data.secretToken}' | base64 -d && echo
```

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
