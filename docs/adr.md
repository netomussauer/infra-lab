# ADR — Architecture Decision Records

> **Projeto:** infra-lab home-lab
> **Atualizado em:** 2026-04-29
> **Responsável:** jose.mussauer@stone.com.br

Cada ADR documenta uma decisão de design tomada neste projeto: o contexto que levou à decisão, a alternativa escolhida, e as consequências conhecidas. Decisões superadas por novas têm seu status atualizado para **Substituído**, com referência ao ADR que as substitui.

---

## Índice

| # | Título | Status |
|---|---|---|
| [ADR-001](#adr-001) | K3s em vez de kubeadm full Kubernetes | Aceito |
| [ADR-002](#adr-002) | Harbor em vez de Docker Registry v2 | Aceito |
| [ADR-003](#adr-003) | Tekton em vez de Drone CI ou GitHub Actions | Aceito |
| [ADR-004](#adr-004) | ArgoCD em vez de Flux CD | Aceito |
| [ADR-005](#adr-005) | local-path StorageClass em vez de NFS para PVCs de workloads | Aceito (substitui intenção original de usar NFS) |
| [ADR-006](#adr-006) | Flannel em vez de Calico ou Cilium | Aceito |
| [ADR-007](#adr-007) | NetBox como IPAM centralizado | Aceito |
| [ADR-008](#adr-008) | PostgreSQL para o Gitea em vez de SQLite | Aceito |
| [ADR-009](#adr-009) | NFSv3 para montagens de host — NAS Seagate Black Armor | Aceito |
| [ADR-010](#adr-010) | Pi-hole como DNS interno do lab (vs dnsmasq, CoreDNS, VM dedicada) | Aceito |
| [ADR-011](#adr-011) | Sealed Secrets como plataforma de gestão de secrets (vs SOPS, ExternalSecrets+Vault) | Aceito |

---

## ADR-001

**Título:** K3s em vez de kubeadm full Kubernetes

**Status:** Aceito

**Contexto:**

O cluster precisa rodar em hardware heterogêneo de 2011–2012, incluindo um Raspberry Pi ARMv7 com apenas 1 GB de RAM. A instalação precisa ser replicável via scripts automatizados e suportar múltiplas arquiteturas sem configuração especializada por nó.

**Alternativas consideradas:**

| Critério | K3s | kubeadm K8s |
|---|---|---|
| RAM mínima do control-plane | ~512 MB | ~2 GB |
| Suporte ARMv7 nativo | Sim (binário único) | Requer config manual |
| Instalação | Script único (`get.k3s.io`) | Multi-etapas, múltiplos componentes |
| Traefik + local-path embutidos | Sim | Não |
| etcd embedded (SQLite/etcd) | Sim | Não |
| Produção enterprise | Não recomendado | Sim |

**Decisão:** K3s v1.29.3.

**Consequências:**

- O overhead do control-plane cabe em uma VM de 4 GB e ainda deixa ~2.5 GB livres.
- O Raspberry Pi (1 GB) consegue rodar o agente K3s com margem de ~750 MB para workloads edge.
- A compatibilidade com a API Kubernetes padrão é total — os manifests são idênticos aos de um cluster kubeadm.
- Recursos enterprise (HA etcd multi-node, FIPS, etc.) não estão disponíveis — aceitável para home lab.

---

## ADR-002

**Título:** Harbor em vez de Docker Registry v2

**Status:** Aceito

**Contexto:**

O pipeline CI/CD precisa de um registry privado para armazenar imagens de containers. O `registry:2` oficial é simples e leve. Harbor é mais pesado mas oferece funcionalidades que aproximam o lab de ambientes de produção reais.

**Alternativas consideradas:**

| Critério | Harbor | registry:2 |
|---|---|---|
| Interface web | Sim | Não |
| RBAC por projeto | Sim | Não |
| Vulnerability scanning (Trivy) | Sim | Não |
| Replication entre registries | Sim | Não |
| RAM idle (total) | ~600 MB | ~50 MB |
| Complexidade operacional | Alta (múltiplos pods) | Baixa |

**Decisão:** Harbor 2.14.3 (chart harbor-1.18.3) no namespace `registry`.

**Consequências:**

- O scan de vulnerabilidades de imagens é ativo por padrão — postura de segurança mais próxima da produção.
- O custo de ~600 MB de RAM é absorvido pelo `k3s-worker-cicd` (6 GB).
- O startup do Harbor leva ~5 minutos na primeira vez (migrations de banco). Não é um problema operacional recorrente.
- Imagens ficam em PVCs `local-path` no nó `k3s-worker-cicd` — perda de nó implica perda das imagens (reconstruíveis pelo pipeline).

---

## ADR-003

**Título:** Tekton em vez de Drone CI ou GitHub Actions self-hosted

**Status:** Aceito

**Contexto:**

O lab precisa de um motor de CI/CD nativo Kubernetes. Drone CI é mais simples mas menos integrado ao ecossistema K8s. GitHub Actions self-hosted (act) não é nativo. O objetivo do lab é aprender stacks de produção enterprise.

**Alternativas consideradas:**

| Critério | Tekton | Drone CI | Act (GH Actions) |
|---|---|---|---|
| Nativo Kubernetes (CRDs) | Sim | Parcial | Não |
| Integração natural com ArgoCD | Sim | Requer adaptação | Requer adaptação |
| Reuso de Tasks (Tekton Hub) | Alto | Médio | Alto (Marketplace) |
| Curva de aprendizado | Alta | Baixa | Baixa |
| RAM controller | ~150 MB | ~100 MB | ~200 MB |

**Decisão:** Tekton Pipelines + Tekton Triggers (manifests diretos do `storage.googleapis.com`).

**Consequências:**

- Tasks usam a API `tekton.dev/v1` (não mais `v1beta1`). O campo de recursos de containers é `computeResources` (não mais `resources`) — diferença importante ao usar exemplos antigos.
- O `PipelineRun` com `generateName` é incompatível com `kubectl apply` — deve ser criado com `kubectl create` ou via `TriggerTemplate`.
- O `EventListener` gera seu próprio `Deployment`; labels customizados no pod template conflitam com o seletor gerado automaticamente — não adicionar `metadata.labels` ao pod template do `kubernetesResource`.
- A curva de aprendizado é o investimento intencional do lab.

---

## ADR-004

**Título:** ArgoCD em vez de Flux CD

**Status:** Aceito

**Contexto:**

O lab precisa de um operador GitOps para reconciliar o estado declarado no Git com o estado real do cluster. ArgoCD e Flux CD são as duas opções mainstream.

**Alternativas consideradas:**

| Critério | ArgoCD | Flux CD |
|---|---|---|
| UI web | Sim (rica, visualiza diffs) | Apenas CLI |
| Multi-cluster | Sim | Sim |
| RAM idle (total) | ~600 MB | ~300 MB |
| Modelo mental | App-centric | GitRepository-centric |
| Integração Helm/Kustomize | Sim | Sim |

**Decisão:** ArgoCD v3.3.8 (chart argo-cd-9.5.9) no namespace `cicd`.

**Consequências:**

- A UI do ArgoCD acelera o diagnóstico de diffs de sincronização — valiosa em ambiente de aprendizado.
- ArgoCD corre no `k3s-worker-cicd`, não no control-plane — mantém o control-plane leve.
- Custo de RAM extra (~300 MB vs Flux) é aceito.
- A senha inicial do admin está no secret `argocd-initial-admin-secret` no namespace `cicd`.

---

## ADR-005

**Título:** local-path StorageClass em vez de NFS para PVCs de workloads

**Status:** Aceito _(substitui intenção original de usar NFS Subdir como StorageClass default)_

**Contexto:**

O design original previa usar o NAS (Seagate Black Armor, 192.168.1.112) via NFS como StorageClass default para todos os PVCs do cluster. Durante a implantação, dois problemas bloqueantes foram descobertos:

1. **NFSv4 não suportado**: o NAS Seagate Black Armor suporta apenas NFSv3. Tentativas de mount com `nfsvers=4` ou `nfsvers=4.1` resultam em `Protocol not supported`. Não há opção de habilitação de NFSv4 na interface web do NAS.

2. **`root_squash` não desabilitável**: o NAS impõe `root_squash` em todos os exports (requisições do UID 0 mapeadas para `nobody`). Init containers de vários charts Helm (Gitea, Harbor, kube-prometheus-stack) executam `chown /data` como root antes de iniciar o serviço principal — essa operação falha com `Operation not permitted`. A interface web do NAS (modelo Black Armor) não oferece opção de desabilitar `root_squash`.

**Alternativas consideradas:**

| Opção | Viabilidade | Impacto |
|---|---|---|
| NFS Subdir como default (original) | Bloqueado por root_squash | — |
| Longhorn | Requer ~200 MB por nó; RPi (1 GB) ficaria sem margem | Descartado |
| Rook-Ceph | Requer ~500 MB+ por nó; incompatível com RAM disponível | Descartado |
| local-path (K3s built-in) | Zero overhead adicional; já presente | **Escolhido** |

**Decisão:** usar `local-path` (K3s built-in) como StorageClass default para todos os PVCs de workloads. O NFS Subdir Provisioner permanece instalado e disponível como `nfs-storage`, mas sem uso para workloads.

**Consequências:**

- **Dados são locais ao nó**: a perda do nó implica perda dos dados do PVC. Para um home lab, isso é aceitável — as imagens são reconstruíveis e os dados de monitoramento são temporários.
- **Sem migração de PVC entre nós**: se um workload precisar mover de nó, os dados não seguem. Mitigação: recriar o PVC no novo nó (ou usar backup/restore).
- **Builds do Tekton** usam `VolumeClaimTemplate` (PVC efêmero por PipelineRun) — sem estado persistente entre runs, o impacto é nulo.
- **Simplicidade operacional**: zero componentes adicionais, zero problemas de permissão NFS.
- O NFS ainda é usado para montagens de host (`/mnt/k8s-pv`) com NFSv3, mas não para PVCs Kubernetes.

---

## ADR-006

**Título:** Flannel em vez de Calico ou Cilium

**Status:** Aceito

**Contexto:**

O cluster inclui um Raspberry Pi ARMv7 (Raspbian 12) como nó worker. A escolha do CNI precisa ser compatível com essa arquitetura.

**Decisão:** Flannel VXLAN (CNI padrão do K3s).

**Justificativa:**

- Calico em modo eBPF e Cilium requerem kernel Linux ≥5.4 com suporte completo a eBPF. O kernel do Raspbian para ARMv7 não atende esse requisito.
- Flannel funciona em modo VXLAN sem dependência de eBPF, rodando em todos os nós incluindo o RPi.
- Network policies avançadas não são requisito do lab — a rede plana do Flannel é suficiente.

**Consequências:**

- Sem suporte a Network Policies avançadas (Flannel não implementa NetworkPolicy nativamente — requer um controlador separado como o do Calico em modo de apenas policies).
- Sem observabilidade de rede do eBPF (Hubble do Cilium).
- Compatibilidade total com ARMv7 garantida.
- O Raspberry Pi (Raspbian 12, kernel 6.12.75+rpt-rpi-v7) usa **cgroups v2 puro** (`CONFIG_MEMCG_V1=n`). O script de instalação do K3s emite aviso sobre `cgroup_memory` mas o agente funciona normalmente — a correção requer `cgroup_memory=1 cgroup_enable=memory` no `/boot/firmware/cmdline.txt` e instalação de `iptables` (ver Runbook P18).

---

## ADR-007

**Título:** NetBox como IPAM centralizado

**Status:** Aceito

**Contexto:**

O lab tem hardware heterogêneo com IPs fixos para hosts físicos, VMs, serviços LoadBalancer e CIDRs internos do K3s. Sem gerenciamento centralizado, conflitos de IP são difíceis de diagnosticar e o estado real fica espalhado entre Terraform, Ansible e comentários no código.

**Alternativas consideradas:**

| Critério | NetBox | IPs hardcoded no Terraform | Planilha |
|---|---|---|---|
| Detecta conflitos de IP | Sim (`terraform plan` falha) | Não | Manual |
| Inventário dinâmico Ansible | Sim (plugin `nb_inventory`) | Não | Não |
| Visualização de topologia | Sim | Não | Parcial |
| Documentação de prefixos | Sim | Não | Manual |
| Overhead de RAM | ~512 MB (VM existente) | Zero | Zero |

**Decisão:** NetBox IPAM (192.168.1.72), VM já deployada no Proxmox lab.

**Consequências:**

- O Terraform registra VMs e IPs no NetBox via `netbox.tf` antes de provisioná-las no Proxmox.
- O Ansible pode usar `inventory/netbox.yml` (plugin dinâmico) em vez do `hosts.yml` estático.
- Como o NetBox já estava deployado (VM existente), o custo incremental é zero.
- Token de API do NetBox: nunca commitar no repositório — usar variável de ambiente `NETBOX_TOKEN`.

---

## ADR-008

**Título:** PostgreSQL para o Gitea em vez de SQLite

**Status:** Aceito

**Contexto:**

O Gitea suporta SQLite, PostgreSQL e MySQL. O design original previa SQLite para simplicidade. Durante a implantação com o Gitea chart v12 (gitea-12.5.3), foi descoberto que o chart v12 usa init containers que não montam o volume de dados do SQLite, tornando a configuração de banco incompatível com a estrutura de volumes do chart atual.

**Problema descoberto:**

```
configure-gitea: SQLite: unable to open database file
```

O init container `configure-gitea` tenta abrir `/data/gitea/gitea.db` (SQLite), mas esse volume não é montado no init container no chart v12 — somente o main container tem acesso ao volume de dados.

**Decisão:** PostgreSQL bundled (subchart `postgresql` do Bitnami), habilitado via `postgresql.enabled: true` nos helm values.

**Consequências:**

- PostgreSQL roda como StatefulSet (`gitea-postgresql-0`) no mesmo nó do Gitea (`k3s-worker-cicd`).
- PVC dedicado de 5Gi (`local-path`) para o PostgreSQL.
- RAM adicional: ~256 MB request / ~512 MB limit para o PostgreSQL.
- Backup do banco: incluído no backup do PVC (ou via `pg_dump` para snapshot externo).
- Credenciais: `gitea` / `gitea123` — alterar em produção real.

---

## ADR-009

**Título:** NFSv3 para montagens de host — NAS Seagate Black Armor

**Status:** Aceito

**Contexto:**

As montagens NFS nos nós do cluster (para `/mnt/k8s-pv` e `/mnt/backups`) falhavam com `Protocol not supported` ao usar as opções padrão de montagem (`nfsvers=4` ou `nfsvers=4.1`).

**Diagnóstico:**

O NAS é um Seagate Black Armor 2-Bay. Esse modelo foi descontinuado e suporta apenas NFSv2 e NFSv3. A interface web não oferece opções de configuração do servidor NFS além de habilitar/desabilitar o serviço.

**Decisão:** forçar `nfsvers=3` em todas as configurações de montagem NFS.

**Arquivos afetados:**

- `ansible/inventory/group_vars/all.yml`: `nfs_mount_options: "nfsvers=3,hard,intr,_netdev,..."`
- `kubernetes/bootstrap/storage/nfs-csi-values.yaml`: `mountOptions: [nfsvers=3, ...]`
- `kubernetes/bootstrap/storage/nfs-storageclass.yaml`: `parameters.mountOptions: nfsvers=3`

**Consequências:**

- NFSv3 não suporta locking integrado ao protocolo (usa `lockd` separado). Aceitável para o uso de backup e storage auxiliar.
- Performance do NFSv3 é comparável ao v4 para leitura sequencial de arquivos grandes (workloads do lab).
- Qualquer upgrade de NAS no futuro para um modelo que suporte NFSv4 exigirá reverter `nfsvers=3` para `nfsvers=4` nas configurações.

---

## ADR-010

**Título:** Pi-hole como DNS interno do lab (vs dnsmasq, CoreDNS standalone, VM dedicada)

**Status:** Aceito

**Contexto:**

A entrega do projeto AMFIT revelou que o `containerd` em cada nó do K3s não usa o CoreDNS do cluster — usa o resolver do próprio nó. Quando o build via Tekton/Kaniko faz push de uma imagem para `harbor.lab.local`, e em seguida o ArgoCD tenta deployar essa imagem, o pull pelo container runtime falha com `lookup harbor.lab.local: Try again` (ver `amfit/infra/cluster/PENDING.md` item #1).

Para resolver, é necessário um DNS na LAN que entenda os nomes internos do lab (`*.lab.local`, `*.infra.local`, `*.amfit.local`) e que os nós usem esse DNS no `/etc/resolv.conf` do host.

**Alternativas consideradas:**

| Critério | Pi-hole | dnsmasq | CoreDNS standalone | VM dedicada |
| --- | --- | --- | --- | --- |
| UI web para gestão | Sim (excelente) | Não | Não | depende da imagem |
| Filtro de ads para a LAN | Sim (bônus) | Não | Não | depende |
| Registros A/CNAME custom | Via UI ou arquivo | Apenas arquivo | Apenas Corefile | varia |
| RAM idle | ~256 Mi | ~30 Mi | ~64 Mi | ~512 Mi (VM completa) |
| Métricas Prometheus | Sim (exporter oficial) | Requer adaptador | Nativo | varia |
| Manutenibilidade | Alta (interface familiar) | Baixa (editar YAML) | Média | Alta |
| Resiliência (cluster down → DNS down) | sim | sim | sim | não — VM separada |

**Decisão:** Pi-hole `2024.07.0` deployado como Deployment K3s no namespace `network-services`, exposto via MetalLB em `192.168.1.53` (pool `infra-services-pool`).

**Justificativa:**

- A UI web do Pi-hole acelera operação em ambiente de lab — adicionar um registro CNAME via interface é mais ergonômico que editar Corefile/dnsmasq.conf e fazer rollout.
- O bloqueio de ads no LAN é benefício colateral relevante (todos os dispositivos da casa via DHCP).
- O custo de RAM (~256 Mi) é absorvido pelo nó `ubuntu-neto` que tem ~5 GB de margem após Prometheus + Loki + PostgreSQL + Redis.
- Manter no cluster (vs VM dedicada) evita criar uma nova VM no Proxmox que já está em 16/16 GB de RAM alocada.

**Resiliência:** o `systemd-resolved`/NetworkManager dos nós tem `FallbackDNS=1.1.1.1 8.8.8.8`. Se o Pi-hole cair, resolução externa (image pulls do Docker Hub, apt-get, etc.) continua funcionando — apenas nomes internos `*.lab.local` ficam indisponíveis até o pod voltar.

**Consequências:**

- Novo pool MetalLB `infra-services-pool` (`192.168.1.50-59`, `autoAssign=false`) — reservado para serviços de infraestrutura que precisam de IPs estáveis fora do range de workloads.
- Playbook Ansible `06-internal-dns.yml` configura `systemd-resolved` (Ubuntu) e `NetworkManager` (Raspbian) nos 5 nós para usar Pi-hole como DNS primário.
- Registros customizados estão em `kubernetes/network-services/pihole/configmap-records.yaml` (formato dnsmasq `address=/host/IP`) — mudanças exigem `kubectl apply` + `kubectl rollout restart deployment/pihole`.
- Senha do admin: secret `pihole-admin` no namespace `network-services` — alterar em produção real.
- O Pi-hole roda em um único nó (`ubuntu-neto`) com `strategy: Recreate` — durante upgrade há ~30s de indisponibilidade de DNS. Aceitável pelo fallback configurado.

---

## ADR-011

**Título:** Sealed Secrets como plataforma de gestão de secrets (vs SOPS, ExternalSecrets+Vault)

**Status:** Aceito

**Contexto:**

A entrega do AMFIT (item #2 de `amfit/infra/cluster/PENDING.md`) revelou que o cluster não tinha solução de secret management. O Secret `amfit-secrets` foi criado manualmente no cluster (chaves JWT + credenciais de banco), enquanto o repositório Git tinha **placeholders** (`REPLACE_WITH_*_PEM`). O ArgoCD ignorava o diff via `ignoreDifferences`, mas o risco era que se o Secret fosse deletado, o GitOps reapliciaria os placeholders e quebraria a API.

Como o lab hospedará múltiplos projetos no futuro (`realtpmsys`, AMFIT, outros), foi necessário escolher uma solução **compartilhada** que qualquer projeto possa adotar de forma idêntica.

**Alternativas consideradas:**

| Critério | Sealed Secrets | SOPS + age + KSops | ExternalSecrets + Vault |
| --- | --- | --- | --- |
| Componente no cluster | Controller único (~80 Mi) | Plugin no ArgoCD repo-server | Operator + Vault (~512 Mi+) |
| Encrypted secret no Git | Sim (objeto `SealedSecret`) | Sim (arquivo `.enc.yaml`) | Não (apenas referência) |
| Backend externo necessário | Não | Não | Sim (Vault, AWS SM, etc.) |
| Encryption offline pelo dev | Sim (cert público) | Sim (chave age) | Não (requer backend up) |
| Curva de aprendizado | Baixa (`kubeseal`) | Média (SOPS + KSops plugin) | Alta (Vault auth, policies) |
| Disaster recovery (perda de key) | Reproviar todos secrets | Reprovisar todos secrets | Backend persistente |
| Adequação a múltiplos projetos | Excelente — mesmo pattern para todos | Excelente | Excelente, mas overkill para lab |

**Decisão:** Sealed Secrets `v0.36.6` (Bitnami Labs), controller deployado em `kube-system` via Kustomize (`kubernetes/sealed-secrets/`).

**Justificativa:**

- **Operação simples:** `kubeseal` CLI gera `SealedSecret` localmente → commit no Git → controller decripta automaticamente no cluster. Padrão familiar para qualquer dev.
- **Encryption offline:** o cert público está em `kubernetes/sealed-secrets/pub-cert.pem` (commitado, é seguro). Devs sem acesso ao cluster conseguem encriptar.
- **Helper script:** `scripts/seal-secret.sh` encapsula `kubeseal` com defaults do lab (escopo `strict`, cert local) — qualquer projeto novo usa o mesmo wrapper.
- **Escopo `strict` (default):** o `SealedSecret` só decripta se NAME **e** NAMESPACE baterem no apply. Mais seguro — não é possível copiar entre namespaces para vazar dados.
- **Sem backend externo:** Vault seria overkill para home lab (mais um StatefulSet + RBAC + auth methods). ExternalSecrets é boa solução, mas depende de um backend que ainda não existe.

**Estrutura adotada (cluster-wide, reutilizável por qualquer projeto):**

```text
infra-lab/
├── kubernetes/sealed-secrets/
│   ├── controller-upstream.yaml    # manifest oficial do release (não editar)
│   ├── kustomization.yaml          # patches do lab (nodeSelector, labels)
│   └── pub-cert.pem                # cert público — usado para encryption offline
└── scripts/
    └── seal-secret.sh              # wrapper de kubeseal — padroniza uso entre projetos
```

**Como cada projeto usa:**

```bash
# 1. Criar Secret normal localmente (NÃO comitar este)
kubectl create secret generic my-app-secrets \
  --from-literal=API_KEY=s3cret123 \
  --namespace=my-app \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 2. Encriptar
./scripts/seal-secret.sh /tmp/secret.yaml > my-app/k8s/sealedsecret.yaml

# 3. Commitar — só o SealedSecret vai pro Git, o Secret descriptografado fica só no cluster
```

**Consequências:**

- **Master key fica no cluster:** o controller cria o secret `sealed-secrets-key*` no namespace `kube-system`. Se for perdido (delete + reinstall), **todos** os SealedSecrets do cluster viram inúteis. Procedimento de backup documentado em `docs/runbook.md` seção 5.x (decisão de onde guardar fica com o owner do lab).
- **Rotação automática a cada 30 dias:** o controller gera novas keys e mantém as antigas para decryption de SealedSecrets existentes. Nenhuma re-encryption obrigatória.
- **Cert público pode ser comitado:** é criptografia assimétrica — o `pub-cert.pem` é seguro em repo público.
- **`kubeseal` CLI precisa ser instalado** pelo dev (ou pelo CI) — não está no cluster. Instalação documentada no runbook.
- O escopo `strict` torna refactors de namespace/nome mais custosos (precisa re-encriptar). Aceitável — segurança > conveniência.
- O controller em `kube-system` segue a convenção oficial do projeto. Migrar para namespace dedicado (`sealed-secrets`) é possível mas exige `--controller-namespace` em todo `kubeseal` — fricção alta para todos os projetos.
