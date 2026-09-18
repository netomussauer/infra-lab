---
key: proxmox-cluster
type: semantic
tags: [proxmox, infra, topology]
priority: high
---

Cluster Proxmox VE 9.2.3 do infra-lab com 2 nós, ambos `status: online`:

- **`virt`** (192.168.1.20): Intel i7-2670QM (8 cores, Sandy Bridge 2011), 16 GB RAM.
  Nó principal — hospeda as 3 VMs originais do K3s (`k3s-server`, `k3s-worker-cicd`,
  `ci-runner`) + CT `homepage` + VM `haos15.2` (Home Assistant). Estava em ~93%
  de memória usada até 2026-09-18 (quase saturado); após migrar `netbox`/
  `bookstack` para `pve2`, caiu para ~79%.
- **`pve2`** (192.168.1.21): Intel i5-3330 (4 cores, Ivy Bridge 2012), 7.7 GB RAM,
  **GPU NVIDIA GTX 1060 6 GB** (IOMMU group 1). Testes IA / PCI passthrough.
  Desde 2026-09-18 também hospeda: VM `k3s-worker-pve2` (novo worker K3s,
  `workload=general`), CT `netbox` (100) e CT `bookstack` (106) — migrados de
  `virt` para aliviar a pressão de memória lá. CT `ollama` (101) permanece em
  `pve2` mas **parado** (`onboot=0`) desde 2026-09-18 — confirmado via
  Prometheus/RRD do Proxmox 0% de uso de GPU e CPU em 30 dias; ver
  `context/facts/ollama-lab.md`.

Storage no `pve2`: `SeagateNAS` (NFS, ~2.7 TB, compartilhado com `virt` — é o
que viabilizou a migração rápida de `netbox`/`bookstack` sem cópia de disco),
`local-lvm` (~290 GB livres), `local` (~82 GB).

API endpoint: `https://192.168.1.20:8006`. Token admin: `root@pam!root`.
Credenciais em `~/.env.proxmox` no WSL (chmod 600, não versionado). Desde
2026-09-18 também existe um token de escopo reduzido (`agente-ia@pve`, role
`PVEAuditor` — somente leitura) para sessões de agente de IA — ver
`secrets/README.md` seção "Credenciais de agente de IA".

**Terraform**: o `terraform/proxmox/` deste repo NÃO tem `terraform.tfstate`
nesta máquina (nunca houve `apply`/`import` bem-sucedido aqui) — as 4 VMs do
K3s existem e funcionam, mas o Terraform não sabe disso. Providers
`bpg/proxmox`/`e-breuninger/netbox` também estão com bugs que bloqueiam
`plan`/`apply`/`import`. Ver `docs/runbook.md` P24 antes de rodar qualquer
comando Terraform aqui.
