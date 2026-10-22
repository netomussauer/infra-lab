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
| [ADR-012](#adr-012) | Credenciais de escopo reduzido para agentes de IA (vs. reuso das credenciais admin, vs. HashiCorp Vault) | Aceito |
| [ADR-013](#adr-013) | Cloudflare Tunnel + ingress-nginx interno para expor endpoints públicos (vs. port-forward direto, vs. VPS reverse proxy, vs. Tailscale Funnel) | Aceito |
| [ADR-014](#adr-014) | Descontinuar infra-lab-proxmox e migrar bookstack-sync/netbox-scripts para infra-lab | Aceito |
| [ADR-015](#adr-015) | Nuvem pública para ambiente produtivo (AWS como padrão) + conectividade lab↔cloud via mesh outbound-only | Aceito (referência — nenhum projeto migrado ainda) |
| [ADR-016](#adr-016) | Acesso administrativo de fallback à infraestrutura quando a rede primária está indisponível (vs. VPN dedicada, vs. nada formal) | Aceito (canal local já em uso; SSH via Cloudflare Tunnel ainda não implementado) |
| [ADR-017](#adr-017) | Gestão de credenciais humanas com Bitwarden Cloud + Vaultwarden self-hosted (vs. 1Password, vs. KeePassXC, vs. HashiCorp Vault, vs. nada formal) | Aceito (decisão registrada; provisionamento ainda não feito) |

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

---

## ADR-012

**Título:** Credenciais de escopo reduzido para agentes de IA (vs. reuso das credenciais admin, vs. HashiCorp Vault)

**Status:** Aceito

**Contexto:**

Sessões de agente de IA (Claude Code e afins) rodando no WSL do host de dev passaram a executar operações reais no lab — SSH em nós, chamadas à API do Proxmox, `kubectl` no cluster, API do NetBox. Até 2026-09-18, essas sessões usavam exatamente as mesmas credenciais admin de um humano (`root@pam!root` no Proxmox, usuário `labadmin` com `sudo NOPASSWD:ALL` via SSH, kubeconfig admin completo, token NetBox de escrita). Não havia diferenciação entre "o dono do lab operando" e "um agente executando uma tarefa" — nem em privilégio, nem em auditoria. O único controle existente era um classificador heurístico do lado do Claude Code (auto mode), que bloqueia ações que *parecem* arriscadas — não é controle de acesso real, é best-effort e gera falsos positivos.

**Alternativas consideradas:**

| Critério | Escopo nativo por sistema (Proxmox ACL, sudoers, K8s RBAC, NetBox permissions) | HashiCorp Vault (secrets dinâmicos + audit device) |
| --- | --- | --- |
| Infra nova necessária | Nenhuma — usa mecanismos que cada sistema já tem | Um serviço 24/7 a mais (unseal, storage backend, políticas) |
| Custo operacional em hardware Sandy Bridge/Ivy Bridge (2011-2012) | Zero | Real — mais um processo competindo por CPU/RAM já escassos |
| Secrets engine pronta para Proxmox/NetBox | N/A (usa token/permissão nativa de cada um) | Não existe — precisaria de plugin customizado |
| Auditoria | Logs nativos de cada sistema (Proxmox tasks/`pveproxy` access log, SSH `auth.log`, K8s audit log, NetBox changelog) — suficiente uma vez que o agente tem identidade própria em cada um | Audit device nativo, mas redundante com os logs acima |
| Consistência com decisão já tomada (ADR-011) | Mesma lógica de frugalidade | Contradiria a justificativa já usada para rejeitar Vault no ADR-011, para um problema de escopo *menor* (1 operador + 1 agente local, não multi-time) |

**Decisão:** Criar uma identidade de escopo reduzido — usuário/token/ServiceAccount próprios, chamados `agente-ia` — em cada sistema que o agente precisa tocar, em vez de reusar credenciais admin ou introduzir Vault:

- **Proxmox:** usuário `agente-ia@pve`, role `PVEAuditor` (só auditoria — sem `VM.Allocate`, `Sys.Modify`, `Sys.PowerMgmt`), token com expiração de 90 dias.
- **SSH:** usuário Linux `agente-ia` em todos os nós (criado por `ansible/playbooks/01-base-setup.yml`), chave própria, `sudoers` restrito a uma allowlist de comandos de diagnóstico (`systemctl status`, `journalctl`, `df`, `free`, `crictl ps/logs`, etc.) — sem `NOPASSWD:ALL`.
- **Kubernetes:** `ServiceAccount agente-ia` (namespace `kube-system`) + `ClusterRole agente-ia-readonly` — leitura ampla, **sem** acesso a `Secrets`, sem nenhuma permissão de escrita (`kubernetes/bootstrap/agente-ia-rbac.yaml`).
- **NetBox:** usuário `agente-ia` (não-staff, não-superuser), permissão `view`-only, token com `write_enabled: false` e expiração de 90 dias.

Distribuídas via o mesmo fluxo SOPS+age já existente (`secrets/env.agent.enc.yaml`, ver ADR-011 e `secrets/README.md`), não um mecanismo novo.

**Justificativa:**

- Cada sistema envolvido já tinha controle de acesso granular nativo (ACL+token expiry no Proxmox, RBAC+ServiceAccount no K8s, permissions+expires no NetBox, usuário/sudoers no SSH) — o gap real não era "falta uma ferramenta de secrets", era "ninguém tinha configurado uma identidade separada pro agente".
- Resolve o problema de fundo: uma vez decriptado, um secret vira plaintext acessível a qualquer processo do mesmo usuário do host. Vault não elimina isso — só adiciona uma camada de indireção em cima. O que fecha o gap é o agente ter, estruturalmente, um conjunto de credenciais **diferente** (não só "mais bem guardado") do humano.
- Consistente com a "Frugalidade de recursos" já documentada como princípio do lab e com a rejeição de Vault no ADR-011 para um problema irmão.
- Reversível e revogável por sistema, sem depender de nenhum componente novo: apagar o token/usuário/ServiceAccount em cada sistema é suficiente.

**Consequências:**

- Qualquer operação que exija privilégio maior (escrita em VM, deploy, restart de serviço, migração) precisa cair para as credenciais admin deliberadamente — isso é esperado, não um bug a contornar. Ver `AGENTS.md` seção "AI Agent Credentials".
- Tokens Proxmox/NetBox expiram em 90 dias — rotação é automática/forçada por design; precisa gerar novos antes do prazo (ou perde acesso, fail-safe).
- `notebook-i5` (`ubuntu-neto`) ainda não recebeu o usuário `agente-ia` — a chave `labadmin` estava falhando lá no momento da implementação (problema pré-existente, não causado por isso). Pendente de correção separada.
- Vault permanece como opção de fase futura, condicional: só revisitar se o lab virar multi-agente/multi-operador ou precisar de secrets dinâmicos em escala — nesse caso rodaria como LXC dedicado em `virt` (mais headroom), fora do K3s, com unseal manual (sem KMS de nuvem disponível).
- O controller em `kube-system` segue a convenção oficial do projeto. Migrar para namespace dedicado (`sealed-secrets`) é possível mas exige `--controller-namespace` em todo `kubeseal` — fricção alta para todos os projetos.

---

## ADR-013

**Título:** Cloudflare Tunnel + ingress-nginx interno para expor endpoints públicos (vs. port-forward direto no roteador, vs. VPS reverse proxy, vs. Tailscale Funnel)

**Status:** Aceito

**Contexto:**

Quatro projetos hospedados neste lab (`amfit`, `amactive`, `realtpmsys`,
`training-performance-hub`) precisam de endpoints alcançáveis pela internet
para integração com aplicações externas (ex.: webhooks). Até 2026-09-18 o
lab não expunha nada publicamente: rede inteira em `192.168.1.0/24`
residencial, sem Ingress Controller ativo (Traefik do K3s desabilitado
desde a instalação — ver `ansible/playbooks/03-k3s-server.yml`), sem
domínio, sem qualquer porta aberta no roteador. É greenfield: nenhuma
exposição existente para migrar, decisão livre de dívida técnica prévia.
Como é residencial, IP WAN é dinâmico e não há orçamento/necessidade de
infraestrutura dedicada de borda — a solução precisa ser barata, não abrir
portas no roteador de casa (superfície de ataque direta sobre a rede
doméstica) e, principalmente, **escalar sem retrabalho** conforme novos
projetos passarem a precisar do mesmo tipo de endpoint.

**Alternativas consideradas:**

| Critério | Cloudflare Tunnel (`cloudflared`) + ingress-nginx interno | Port-forward direto + DynDNS + Let's Encrypt | VPS pequena como jump box (reverse proxy sobre WireGuard) | Tailscale Funnel |
| --- | --- | --- | --- | --- |
| Portas abertas no roteador residencial | Nenhuma — conexão outbound-only do `cloudflared` para a borda Cloudflare | 80/443 expostas diretamente, IP residencial visível | Nenhuma no roteador de casa, mas a VPS em si tem portas públicas | Nenhuma |
| Custo | Zero (tier free cobre DNS, WAF básico, túnel ilimitado) | Zero (fora o domínio) | Mensalidade de VPS (~US$5+/mês) | Zero, mas free tier tem limites de uso mais agressivos |
| Esforço para adicionar um projeto novo | Só um `Ingress` k8s no projeto (ver `kubernetes/edge/ingress-template.yaml`) — nada muda na borda | Novo subdomínio/DNS + config manual de proxy reverso por app | Nova entrada de proxy na VPS por app — mais um lugar pra manter em dia | Novo Funnel por serviço — sem camada de roteamento única |
| Proteção na borda | WAF + DDoS + rate limiting nativos do Cloudflare | Nenhuma — fica sob responsabilidade do proxy local | Depende do que for configurado manualmente na VPS | Limitada, sem WAF completo |
| Maturidade para receber webhooks de terceiros em produção | Alta — caso de uso padrão documentado pela Cloudflare | Alta, mas com mais superfície pra manter segura | Alta, mas com mais infra pra operar | Menor — mais voltado a acesso ponto-a-ponto que ingestão pública |

**Decisão:** Usar **Cloudflare Tunnel** como única via de entrada pública do
lab, terminando sempre em um **ingress-nginx interno** (namespace `edge`,
`Service` `ClusterIP` — nunca `LoadBalancer`/`NodePort`), que por sua vez
roteia por hostname/path usando o recurso `Ingress` padrão do Kubernetes,
um por projeto:

```text
Internet -> Cloudflare (DNS+WAF) -> cloudflared (outbound, namespace edge)
         -> ingress-nginx (ClusterIP, namespace edge) -> Ingress de cada app
```

- `cloudflared` conhece só um destino fixo (o ingress-nginx interno) — isso
  nunca muda ao adicionar projetos (`kubernetes/edge/cloudflared/`).
- Cada projeto (`amfit`, `amactive`, `realtpmsys`,
  `training-performance-hub`, ou qualquer um futuro) ganha seu próprio
  `Ingress` expondo **só a rota de integração** (ex.: `/webhooks/<provider>`),
  nunca a aplicação inteira nem painéis administrativos — template em
  `kubernetes/edge/ingress-template.yaml`.
- Hostname público usa wildcard de **um nível** (`*.amtech.app.br`) — o
  Universal SSL gratuito do Cloudflare não cobre wildcard de dois níveis
  (`*.pub.amtech.app.br` falhava com handshake failure, corrigido em
  2026-09-18); coberto por um único
  registro DNS — onboarding de projeto novo não exige tocar em DNS nem no
  túnel, só aplicar o `Ingress` do projeto.
- Credencial do túnel (`credentials.json`) segue o mesmo fluxo de segredos
  já estabelecido: SOPS+age para distribuição (`secrets/env.cloudflared.enc.yaml`,
  ver ADR-011/012) e SealedSecret para o que o cluster consome
  (`kubernetes/edge/cloudflared/sealedsecret.yaml`, gerado localmente —
  nunca um `Secret` puro comitado).
- `NetworkPolicy` (`kubernetes/edge/cloudflared/networkpolicy.yaml`) limita
  o `cloudflared` a falar só com o ingress-nginx interno + DNS + a borda do
  Cloudflare, e o ingress-nginx interno a aceitar tráfego só do
  `cloudflared` (+ Prometheus para métricas) — nenhum dos dois alcança
  outro pod/namespace do lab.

**Justificativa:**

- Resolve o requisito central (4 projetos hoje, mais no futuro) sem que
  cada projeto novo exija uma mudança de infraestrutura — só um `Ingress`
  no próprio manifest do projeto, o padrão do Kubernetes que qualquer dev
  já conhece.
- Elimina a única fonte real de risco adicional de uma exposição pública
  em ambiente residencial: nenhuma porta fica aberta no roteador, o IP WAN
  de casa nunca é publicado, e o tráfego passa por WAF/DDoS/rate limiting
  antes de chegar ao cluster.
- ingress-nginx interno (em vez de reativar o Traefik do K3s) segue a
  decisão já registrada no comentário do próprio
  `ansible/playbooks/03-k3s-server.yml` ("usaremos ingress-nginx +
  MetalLB") — não introduz um terceiro padrão de Ingress Controller no
  cluster, só termina de implementar o que já estava planejado, com
  `Service` `ClusterIP` em vez de `LoadBalancer` porque o único cliente é
  o `cloudflared` dentro do próprio cluster.
- VPS como jump box resolveria o mesmo problema, mas adiciona custo
  recorrente e mais um sistema a manter atualizado/seguro — inconsistente
  com a frugalidade de recursos já documentada como princípio do lab
  (mesma lógica usada para rejeitar Vault nos ADR-011/012).
- Tailscale Funnel foi descartado por ser menos maduro especificamente
  para o caso de uso (ingestão de webhooks de terceiros, não acesso
  ponto-a-ponto de um usuário autenticado).

**Consequências:**

- Registro de domínio e ativação da zona no Cloudflare são pré-requisitos
  manuais (ação humana, fora do escopo de automação) antes de qualquer
  aplicação dos manifests em `kubernetes/edge/`. Até lá, os manifests
  ficam preparados mas não aplicados — ver placeholders documentados em
  `kubernetes/edge/cloudflared/configmap.yaml`.
- `step_ingress_nginx` e `step_cloudflared` em `scripts/k8s-bootstrap.sh`
  são etapas **manuais**, fora do fluxo automático de `main()` — exigem
  domínio + tunnel ID + `Secret cloudflared-credentials` já aplicados, e
  falham deliberadamente (`exit 1`) se os placeholders não tiverem sido
  preenchidos, para não travar um bootstrap completo do zero.
- Onboarding de projeto novo tem um procedimento documentado e repetível
  (`kubernetes/edge/ingress-template.yaml`) — qualquer projeto além dos 4
  atuais segue o mesmo caminho, sem decisão de arquitetura nova.
- Se o volume de tráfego público crescer a ponto do tier free do
  Cloudflare não bastar (rate limits, WAF avançado), a migração para um
  tier pago é apenas configuração — a topologia (túnel único +
  ingress-nginx + `Ingress` por app) não muda.
- Painéis administrativos (Grafana, ArgoCD, Harbor, K8s API, NetBox)
  continuam deliberadamente fora deste túnel — só rotas de integração
  específicas de cada projeto são expostas.

---

## ADR-014

**Título:** Descontinuar `infra-lab-proxmox` e migrar `bookstack-sync`/scripts NetBox para `infra-lab`

**Status:** Aceito

**Contexto:**

O repositório `infra-lab-proxmox` (`git@github.com:netomussauer/infra-lab-proxmox.git`, primeiro commit em 2026-04-13) foi o design original do laboratório: Kubernetes via `kubeadm` + Calico, CI/CD via Docker Compose, rede segmentada em VLANs (`10.10.0.0/24`, `10.20.0.0/24`, `10.30.0.0/24`), `lab_id: lab-k8s-proxmox-01`. Esse design nunca chegou a ser o ambiente real — foi substituído pelo que hoje é `infra-lab`: K3s + Flannel + MetalLB, Gitea/Harbor/ArgoCD/Tekton via Helm, rede única flat `192.168.1.0/24`, `lab_id: lab-k8s-01`. Os dois repositórios foram mantidos em paralelo por um tempo, criando risco de confusão sobre qual é a fonte da verdade e superfície extra para vazamento de credenciais (confirmado em 2026-09-22: um token de API do BookStack ficou em texto puro, não commitado, num arquivo do `infra-lab-proxmox` — revertido antes de chegar ao git, sem rotação solicitada pelo dono do lab).

Uma auditoria de conteúdo do `infra-lab-proxmox` (46 arquivos versionados) encontrou:

- **Terraform/Ansible (`terraform-proxmox/`, `terraform-cicd/`, `ansible-k8s/`, `ansible-cicd/`) e `docs/guide/01-04`:** descrevem a arquitetura antiga e superada — nada aqui precisa ser recuperado, porque a decisão de design já mudou.
- **`docs/adr/README.md`:** só o template, nenhuma ADR de fato registrada.
- **`scripts/bookstack-sync/sync.py`:** ferramenta Python ativa (refatorada recentemente de uma versão bash), sem equivalente no `infra-lab` — publica os docs do repo no BookStack real do lab.
- **`scripts/netbox-get-available-ips.sh`/`netbox-sync-lab-ips.sh`:** scripts de integração com a API do NetBox, também sem equivalente no `infra-lab` (que só tem integração via provider Terraform + inventário dinâmico Ansible, ambos somente-leitura/alocação — nenhum descobre IPs ativos na rede).

**Alternativas consideradas:**

| Critério | Migrar o que é único e arquivar o resto | Manter os dois repositórios | Deletar o infra-lab-proxmox sem migrar |
| --- | --- | --- | --- |
| Risco de perder ferramentas úteis | Nenhum — `bookstack-sync` e scripts NetBox passam a viver no repo ativo | Nenhum, mas mantém duas fontes da verdade | Perde o sync do BookStack e os scripts de descoberta de IP permanentemente |
| Superfície de vazamento de credenciais | Reduzida — só um repo com segredos do lab daqui pra frente | Dobrada — dois `secrets/`/`.env` possíveis | Reduzida, mas às custas de perder ferramentas |
| Histórico do git | Preservado (arquivar, não deletar) | Preservado | Perdido (seria necessário confirmação explícita separada, não tomada aqui) |
| Confusão sobre fonte da verdade | Resolvida — `infra-lab` passa a ser o único repo ativo | Não resolvida | Resolvida |

**Decisão:**

1. Migrar `scripts/bookstack-sync/sync.py` (+ `requirements.txt`) para `infra-lab/scripts/bookstack-sync/`, adaptado para sincronizar a estrutura real de docs deste repo (`README.md`, `docs/architecture.md`, `docs/adr.md`, `docs/runbook.md` — arquivo único por tema, não um diretório por página) em vez do layout `docs/adr/*.md` + `docs/guide/*.md` do repo original. Shelf renomeada de `infra-lab-proxmox` para `infra-lab` no BookStack.
2. Migrar `scripts/netbox-get-available-ips.sh` (já genérico, sem mudanças) e `scripts/netbox-sync-lab-ips.sh` (adaptado: rede única `192.168.1.0/24` em vez de 4 VLANs, tag `lab-k8s-01` em vez de `lab-k8s-proxmox-01`) para `infra-lab/scripts/`.
3. Credencial do BookStack segue o mesmo fluxo SOPS+age já estabelecido (`secrets/env.bookstack.enc.yaml`, ver `secrets/README.md`) — precisa ser gerada como token novo no BookStack, nunca reaproveitando o valor que vazou no `infra-lab-proxmox` (tratado como potencialmente comprometido).
4. `infra-lab-proxmox` é **arquivado** no GitHub (read-only, histórico preservado, reversível) — não deletado.

**Justificativa:**

- A arquitetura do `infra-lab-proxmox` nunca foi implantada de verdade — arquivá-lo não descarta nenhuma decisão operacional em uso, só um protótipo já substituído.
- `bookstack-sync` e os scripts NetBox são as únicas peças com valor operacional real e sem equivalente — migrá-los evita perda de trabalho ao encerrar o repositório.
- Arquivar (não deletar) preserva o histórico do git para consulta futura, incluindo a auditoria de que nenhuma credencial real chegou a ser commitada — decisão reversível a qualquer momento via GitHub.
- Consolidar em um único repositório ativo reduz a superfície de vazamento de credenciais e elimina a ambiguidade sobre qual repo é a fonte da verdade do lab.

**Consequências:**

- `scripts/bookstack-sync/sync.py` só funciona depois que `secrets/env.bookstack.enc.yaml` for criado com um token novo, gerado em BookStack → Settings → API Tokens — não há sincronização automática configurada por padrão ainda.
- `scripts/netbox-sync-lab-ips.sh` foi adaptado para a rede real, mas seu uso continua opcional — o `infra-lab` já cobre alocação de IP via Terraform/NetBox provider sem depender de descoberta ativa por scan de rede.
- `infra-lab-proxmox` arquivado continua acessível (read-only) para qualquer consulta futura ao design original, mas não recebe mais commits.

---

## ADR-015

**Título:** Nuvem pública para ambiente produtivo (AWS como padrão) + conectividade lab↔cloud via mesh outbound-only

**Status:** Aceito (referência — nenhum projeto migrado ainda; decisão tomada preventivamente para não ser re-discutida projeto a projeto)

**Contexto:**

Este lab hospeda hoje quatro projetos em desenvolvimento (`amfit`, `amactive`, `realtpmsys`,
`training-performance-hub`), todos com o mesmo caminho previsível pela frente: em algum
momento vão precisar de um ambiente produtivo real, servindo dado de terceiros. O lab, por
natureza, não deve ser esse ambiente — é hardware doméstico (notebooks i5/i7 de 2011-2012,
Raspberry Pi, dois hosts Proxmox na mesma casa) atrás de um único link residencial com IP
dinâmico, sem redundância elétrica, sem backup geograficamente distribuído. A própria ADR-013
já reconhece isso ao restringir a exposição pública a rotas de webhook específicas, nunca à
aplicação inteira.

Ao menos um projeto (`amfit`) trata dado de saúde/atividade física e dado financeiro de
terceiros, sob LGPD — o que teria puxado esta decisão de qualquer forma. Em vez de decidir
"qual nuvem" e "como conectar no lab" a cada projeto que chegar nesse ponto, esta ADR
resolve as duas perguntas uma vez, como padrão do lab: qualquer projeto que precisar de
produção em nuvem pública segue este caminho, salvo justificativa específica documentada
na ADR do próprio projeto.

**Alternativas consideradas (provedor):**

| Critério | AWS (`sa-east-1`, São Paulo) | Azure (`Brazil South`) | GCP (`southamerica-east1`, Osasco-SP) | Oracle Cloud (OCI, `sa-saopaulo-1`) |
| --- | --- | --- | --- | --- |
| Região no Brasil, paridade de serviço | Confirmada — EKS, RDS, ElastiCache disponíveis | Confirmada — AKS, Postgres Flexible Server disponíveis | Confirmada — GKE, Cloud SQL, Memorystore disponíveis | Existe, mas com relatos de baixa disponibilidade de instâncias no tier free |
| Object storage | S3 nativo — zero-code para qualquer projeto que já use um SDK compatível com S3 (ex.: MinIO no lab) | Blob Storage — API própria, não é S3 | GCS — API própria, compat S3 não é 1:1 nativo | Object Storage próprio, compat S3 parcial |
| Esforço operacional p/ time pequeno (2-3 devs) | Médio (mitigável com Fargate profiles) | Médio-alto | **Baixo com GKE Autopilot** (sem gestão de nó) | Médio, mas OKE exige conta paga (PAYG) |
| Certificações (ISO 27001/27701, SOC 2) + DPA compatível com LGPD | Sim | Sim | Sim | Ecossistema de compliance menor |
| Maturidade Terraform/suporte em português | Muito alta | Alta | Alta, comunidade BR menor | Baixa |
| Tier gratuito | Padrão (12 meses + free tier limitado) | Padrão | Padrão | "Always Free" agressivo, mas teve limites de ARM reduzidos pela metade em 2026 |

Provedores mais baratos (DigitalOcean, Vultr, Linode/Akamai) ficam de fora por não terem
paridade de certificação/DPA compatível com dado sensível de terceiros — a Vultr tem DC em
São Paulo, mas nenhum desses tem o nível de compliance formal dos quatro acima.

**Decisão:**

1. **AWS `sa-east-1` é o padrão do lab** para qualquer projeto que precisar de produção em
   nuvem pública — EKS (ou Fargate profiles, para reduzir gestão de nó), RDS para
   Postgres/MySQL conforme o projeto, ElastiCache para Redis, S3 para qualquer storage que
   hoje use MinIO (migração de SDK é zero-code, mesma API).
2. **GKE Autopilot é a alternativa aceita** quando o projeto não depender de compatibilidade
   nativa com S3 (nenhum MinIO/storage S3-compatible em uso) e a prioridade for minimizar
   esforço operacional de um time pequeno — é o mais hands-off dos três (paga por pod, sem
   node a gerenciar).
3. **Azure e OCI não são recomendados** sem uma justificativa específica do projeto (ex.:
   stack majoritariamente .NET para Azure) — documentar essa justificativa na ADR do
   próprio projeto se for o caso.
4. **Conectividade lab↔cloud**: nunca abrir porta no roteador residencial — mesma filosofia
   já estabelecida na ADR-013. Um mesh outbound-only (Tailscale, ou WireGuard caso se
   prefira autogerenciar) entre um nó/pod na VPC cloud e a rede do lab, usado como o
   caminho que o Tekton/ArgoCD do lab usam para alcançar o cluster de produção — não uma
   VPN dedicada cara, nem exposição de IP público do lab.
5. **A esteira de deploy não é reconstruída, é estendida**: o cluster cloud entra como um
   segundo destino registrado no ArgoCD (`argocd cluster add` — suporte nativo
   multi-cluster), com overlay Kustomize por ambiente. O lab continua sendo o ambiente de
   CI/CD e dev/staging exatamente como hoje; a promoção para produção é a mesma imagem já
   validada no lab, promovida via Git (gate manual, ex.: tag de release), nunca rebuild.

**Justificativa:**

- Resolve a mesma pergunta uma única vez em vez de a cada projeto — quando `amactive`,
  `realtpmsys` ou `training-performance-hub` chegarem neste ponto, a resposta já existe.
- AWS como padrão evita que um projeto que já escolheu um storage S3-compatible (caso do
  MinIO no `amfit`, documentado no SDD do projeto como decisão pensando exatamente nisso)
  tenha que reabrir essa decisão de arquitetura ao migrar para produção.
- O mesh outbound-only para a conectividade reaproveita um princípio já validado em
  produção neste lab (ADR-013) em vez de introduzir um padrão novo de rede.
- Estender o ArgoCD/Tekton existentes (em vez de outra ferramenta de deploy) significa que
  nenhuma habilidade nova precisa ser aprendida pelo time — o suporte multi-cluster do
  ArgoCD é nativo, não uma extensão não testada.

**Esforço estimado (por projeto, referência):**

| Fase | O que entra | Esforço (pessoa-dia) |
| --- | --- | --- |
| 0 — Conta e decisões | Conta cloud, billing alerts, MFA, decisão de domínio, revisão de DPA/LGPD (jurídico, paralelo) | 0,5–1 |
| 1 — Landing zone de rede | VPC, subnets públicas/privadas, NAT, Security Groups, IAM baseline (least-privilege) via Terraform | 2–3 |
| 2 — Conectividade lab↔cloud | Mesh outbound-only (Tailscale/WireGuard) — ver decisão acima | 1–2 |
| 3 — Cluster + serviços de dado | EKS/GKE Autopilot, banco gerenciado, cache gerenciado, bucket de objeto versionado, secrets manager, via Terraform | 3–5 |
| 4 — Estender o GitOps | Registrar o cluster cloud no ArgoCD, overlay Kustomize por ambiente, task de promoção no Tekton (sem rebuild) | 2–3 |
| 5 — Migração de dados + cutover | Dump/restore ou replicação lógica do banco; migração de objeto (trivial se já S3-compatible); DNS/TLS; smoke tests | 2–4 |
| 6 — Hardening de produção | Backup com teste de restore, alerta (Grafana do lab pode federar), runbook de incidente, WAF, rotação de segredo | 3–5 |

Total de referência: **~14–23 dias-pessoa** de trabalho técnico direto por projeto, fora o
tempo de aprovação jurídica/DPO (que corre em paralelo, não trava a engenharia). Ver o
procedimento operacional detalhado no runbook, [§8](./runbook.md#8-produção-em-nuvem-pública-procedimento-genérico-multi-projeto).

**Consequências:**

- Nenhuma mudança no lab hoje — esta ADR não implanta nada, só resolve a decisão
  antecipadamente para quando um projeto precisar.
- Cada projeto ainda decide individualmente **se e quando** migrar para produção; esta ADR
  decide **qual nuvem e como conectar** quando isso acontecer.
- Custo recorrente de nuvem só começa a existir quando um projeto de fato provisionar —
  nenhum orçamento é comprometido por esta decisão isoladamente.
- Se as circunstâncias mudarem (ex.: um projeto futuro depender fortemente de serviço
  específico de outro provedor), a exceção deve ser justificada e registrada na ADR do
  próprio projeto, não editada aqui — esta ADR é o padrão, não uma regra sem exceção.

---

## ADR-016

**Título:** Acesso administrativo de fallback à infraestrutura quando a rede primária está indisponível (vs. VPN dedicada, vs. nada formal)

**Status:** Aceito (canal local via WAN2 já em uso na prática; SSH via Cloudflare Tunnel ainda não implementado)

**Contexto:**

Em 2026-10, durante uma instabilidade real do link primário de internet
(ISP1, o roteador doméstico em `192.168.1.254`), ficou evidente que não
havia nenhum caminho formal para administrar a infraestrutura do lab
(Proxmox, principalmente) quando a rede `192.168.1.0/24` está inacessível.
O acesso que de fato funcionou naquele incidente foi improvisado: o host
`pve2` já tinha, por acaso, uma segunda interface de rede ligada à ISP2
(parte da obra em andamento de redundância de WAN — ver seção de
incidentes do runbook, 2026-10), e essa interface por coincidência estava
na mesma sub-rede Wi-Fi que o notebook do operador naquele exato momento.
Diagnosticar e corrigir o lab inteiro — incluindo religar VMs que não
subiram sozinhas após o reboot do host — só foi possível por essa
coincidência de topologia, não por um plano.

Isso expõe uma lacuna real: o lab não tem um canal de administração que
seja (a) independente de qual WAN está ativa e (b) utilizável de fora da
rede física do lab, para quando o responsável não está em casa durante um
incidente.

**Alternativas consideradas:**

| Critério | A) Rede da WAN2 como canal de management oficial | B) SSH/API via Cloudflare Tunnel (break-glass) | C) VPN dedicada (WireGuard/Tailscale) | D) Nada formal (ad hoc, caso a caso) |
| --- | --- | --- | --- | --- |
| Funciona fora da rede física do lab | Não — exige estar na mesma LAN/Wi-Fi que a ISP2 | Sim — qualquer lugar com internet | Sim | Não |
| Depende de qual WAN do lab está viva | Só funciona se a ISP2 estiver viva | Qualquer uma, já que é outbound-only do lado do lab | Qualquer uma | — |
| Esforço de implementação | Zero — já existe como efeito colateral do projeto de redundância de WAN | Médio — túnel `cloudflared` dedicado + Cloudflare Access (Zero Trust) | Médio-alto — mais um sistema a provisionar, manter atualizado e segurar | Zero, mas custo alto repetido a cada incidente (horas de troubleshooting reativo, como em 2026-10) |
| Superfície de ataque nova | Nenhuma — não é alcançável de fora do lab | Pequena, mitigada por autenticação na borda (Cloudflare Access) antes de qualquer pacote chegar ao host | Média — VPN é, por natureza, um ponto de entrada remoto adicional | Nenhuma, mas também nenhuma solução |
| Consistência com o resto do lab | — | Mesmo padrão já usado para exposição pública (ADR-013): outbound-only, sem porta aberta no roteador | Introduz um padrão de acesso remoto novo, sem precedente no lab | — |

**Decisão:** Combinar **A + B**, porque resolvem cenários diferentes e não
competem entre si:

- **(A) Oficializar a rede da WAN2 como canal de management local de
  emergência.** Quando a VM de roteamento multi-WAN (OPNsense, projeto de
  redundância em andamento) estiver em produção, reservar uma interface de
  management dedicada nessa segunda rede — não depender de uma interface
  de teste improvisada como aconteceu em 2026-10. Zero custo adicional,
  já comprovado funcionando num incidente real.
- **(B) Construir acesso SSH ao `pve2`/Proxmox via Cloudflare Tunnel**,
  como canal de resposta remota a incidentes — o cenário que mais importa
  para reduzir tempo de resolução, já que nem sempre o responsável estará
  fisicamente em casa. Túnel dedicado e separado do túnel de exposição
  pública dos apps (`lab-edge`, ADR-013), para não misturar raio de
  impacto, protegido por Cloudflare Access (autenticação por e-mail/OTP
  antes de qualquer tentativa de SSH chegar ao host). Ainda não
  implementado — fica como próximo passo deste ADR.

**Justificativa:**

- (A) já se provou na prática: foi o único motivo pelo qual o lab pôde ser
  diagnosticado e corrigido durante o incidente de 2026-10 sem precisar de
  deslocamento físico. Formalizá-lo custa essencialmente nada — só exige
  manter uma interface de management estável nessa rede em vez de uma
  interface de teste descartável.
- (B) resolve a lacuna que (A) não cobre: acesso de qualquer lugar, não só
  de dentro da casa. Segue exatamente o mesmo padrão arquitetural já
  validado e documentado no ADR-013 (outbound-only, sem porta aberta,
  autenticação na borda) — não introduz um paradigma novo de segurança
  para o lab, só estende o já aceito para um caso de uso diferente (acesso
  administrativo em vez de exposição de aplicação).
- VPN dedicada (C) foi descartada pelo mesmo raciocínio de frugalidade já
  usado para rejeitar Vault (ADR-011/012) e VPS como jump box (ADR-013):
  mais um sistema a provisionar e manter seguro, sem resolver nada que a
  combinação A+B não resolva já com infraestrutura que o lab já opera
  (Cloudflare) ou está construindo de qualquer forma (a segunda interface
  de rede do projeto de redundância de WAN).
- Nada formal (D) é o que o lab tinha até 2026-10, e o custo ficou
  evidente: horas de troubleshooting reativo tentando entender por que o
  acesso não funcionava, em vez de minutos usando um canal já desenhado.

**Consequências:**

- (A) depende da VM de roteamento multi-WAN (OPNsense) chegar a produção
  com uma interface de management dedicada nessa rede — enquanto isso não
  acontece, o canal local continua sendo a interface de teste atual
  (`vmbr1` no `pve2`), que não é garantida permanente.
- (B) é trabalho ainda não feito: criar o túnel dedicado, a aplicação no
  Cloudflare Access com a política de autenticação, e documentar o
  procedimento de uso (`cloudflared access ssh`) no runbook antes de
  depender dele num incidente real.
- Se o `pve2` ficar totalmente inacessível por ambas as rotas (ex.: o
  próprio host física/eletricamente fora do ar, não só a rede), nenhuma
  das duas resolve — isso continua exigindo presença física, fora do
  escopo deste ADR.
- Esse acesso de fallback é estritamente administrativo (Proxmox/hosts) —
  não substitui nem se mistura com o túnel de exposição pública de
  aplicações do ADR-013, que continua separado por desenho.

---

## ADR-017

**Título:** Gestão de credenciais humanas com Bitwarden Cloud + Vaultwarden self-hosted (vs. 1Password, vs. KeePassXC, vs. HashiCorp Vault, vs. nada formal)

**Status:** Aceito (decisão registrada; provisionamento ainda não feito)

**Contexto:**

O lab não tem hoje nenhuma solução formal para credenciais que um **humano**
usa para acessar painéis administrativos (Proxmox, OPNsense, Harbor, Gitea,
ArgoCD, NetBox, Pi-hole, Grafana, o app do roteador Deco, a conta
Cloudflare, o registrador de domínio, GitHub). Essas credenciais estão
hoje espalhadas em `docs/CREDENTIALS.local.md` (markdown gitignored, texto
puro) e em múltiplos arquivos `~/.env.*` no WSL (texto puro, chmod 600) —
tudo em uma única máquina Windows, sem backup redundante.

Isso é um problema **diferente** do que o ADR-011 resolve: SealedSecrets/
SOPS cobrem segredos que o **cluster** consome (senha de banco, token de
API injetado em um Pod); este ADR cobre credenciais que um humano digita
para entrar em uma interface. Não compete com o ADR-011, é complementar.

O risco concreto: se a máquina Windows atual falhar, for perdida ou tiver
o disco corrompido, o acesso administrativo a **toda** a infraestrutura do
lab se perde de uma vez — nenhuma credencial está centralizada, versionada
com segurança, nem recuperável de outro lugar.

**Alternativas consideradas:**

| Critério | Bitwarden Cloud (tier pessoal grátis) | Vaultwarden self-hosted (compatível com o protocolo Bitwarden) | 1Password | KeePassXC | HashiCorp Vault |
| --- | --- | --- | --- | --- | --- |
| Custo | Grátis | Grátis (só o compute, já ocioso no lab) | Pago (~US$36/ano) | Grátis | Grátis (self-host), mas operacionalmente caro |
| Onde roda | Fora do lab, SaaS da Bitwarden | Dentro do lab (CT leve — Rust, SQLite) | Fora do lab, SaaS | Local, arquivo único | Dentro do lab |
| Acesso se o lab inteiro cair | Funciona — independente da rede/energia do lab | Não funciona se o lab estiver fora do ar | Funciona | Funciona (arquivo local) | Não funciona se o lab cair |
| Integração (browser, CLI, mobile) | Excelente | Excelente (mesmos apps do Bitwarden) | Excelente | Boa, sem sync nativo | Nenhuma para uso humano — é uma API |
| Esforço de operar | Zero | Baixo (1 CT leve, SQLite, sem dependência externa) | Zero | Zero, mas sync manual | Alto — já rejeitado 2x nesta base de ADRs |
| Compartilhamento/acesso de emergência | Sim (Emergency Access, organizations) | Sim (mesmo recurso, self-hosted) | Sim | Não nativo | N/A |
| Consistência com o lab | — | Segue o padrão já usado para NetBox/Gitea/Harbor/BookStack (self-hosted) | Introduz dependência paga nova | — | Já descartado em ADR-011/012 pelo mesmo motivo (overkill para o caso de uso) |

HashiCorp Vault foi descartado sem disputa — já foi avaliado e rejeitado
duas vezes nesta mesma base de ADRs (011 e 012) pelo motivo certo: é uma
ferramenta de segredos *machine-to-machine*, não um cofre de senhas para
humano. Reabrir essa decisão com a ferramenta errada não faria sentido.

**Decisão:** Combinar **Bitwarden Cloud + Vaultwarden self-hosted**, pela
mesma lógica de dois-canais-que-não-competem já usada na ADR-016:

- **Bitwarden Cloud (tier pessoal grátis)** para o conjunto pequeno de
  credenciais _break-glass_* — root do Proxmox, root do OPNsense, admin do
  roteador Deco, conta Cloudflare, registrador de domínio. Essas precisam
  estar acessíveis **de fora do lab**, sempre, inclusive quando o lab
  inteiro está fora do ar — é exatamente o cenário que a ADR-016 cobre do
  lado da rede; este ADR cobre o mesmo cenário do lado da credencial.
- **Vaultwarden self-hosted** (CT leve em `pve2` ou `virt`, mesmo padrão
  de frugalidade de recursos já usado no resto do lab) para tudo que só
  importa **depois** que o lab já está de pé — Harbor, Gitea, ArgoCD,
  NetBox, Grafana, Pi-hole. Mantém controle total dos dados sem depender
  de um terceiro para 100% das credenciais.

**Justificativa:**

- Resolve um ponto único de falha real e concreto: hoje, perder uma única
  máquina Windows significa perder acesso administrativo a tudo.
- A divisão em dois cofres replica exatamente o raciocínio que já validou
  a ADR-016 — nunca guardar a chave de emergência de um sistema dentro do
  próprio sistema que ela destranca.
- Vaultwarden segue a prática já estabelecida no lab de hospedar serviços
  próprios e leves (NetBox, Gitea, Harbor, BookStack) em vez de depender
  de SaaS para tudo — consistente, não introduz um padrão novo.
- 1Password foi descartado por custo recorrente sem vantagem real sobre a
  combinação Bitwarden/Vaultwarden para este caso de uso — mesma lógica de
  frugalidade já usada para rejeitar VPS como jump box (ADR-013) e Vault
  (ADR-011/012).
- KeePassXC foi descartado por não ter sincronização/compartilhamento
  nativo — exigiria resolver isso com outra ferramenta (Syncthing,
  Nextcloud), adicionando complexidade sem ganhar nada que o Bitwarden já
  não ofereça de fábrica.
- Nada formal (o status quo) é o que gerou o risco que motivou este ADR.

**Consequências:**

- Nenhuma mudança no lab ainda — esta ADR registra a decisão; o
  provisionamento (criar a conta Bitwarden Cloud, subir o CT do
  Vaultwarden, migrar as credenciais de `docs/CREDENTIALS.local.md` e dos
  `~/.env.*`) é trabalho futuro.
- Define um critério claro para decidir onde cada credencial nova vai: se
  é necessária para destrancar o próprio lab quando ele está fora do ar,
  vai no Bitwarden Cloud; se só importa com o lab já funcionando, vai no
  Vaultwarden self-hosted.
- `docs/CREDENTIALS.local.md` e os arquivos `~/.env.*` continuam existindo
  até a migração acontecer — este ADR não os torna obsoletos
  imediatamente.
- Minhas (Claude) regras de não ler nem relocar credenciais existentes
  continuam valendo sem alteração — nenhuma credencial será extraída de
  dentro do Bitwarden/Vaultwarden por mim. Se no futuro fizer sentido um
  token de API de escopo reduzido para uso por agente de IA, isso segue o
  mesmo padrão já estabelecido na ADR-012, como uma decisão separada.
