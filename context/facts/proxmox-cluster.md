---
key: proxmox-cluster
type: semantic
tags: [proxmox, infra, topology]
priority: high
---

Cluster Proxmox VE 9.2.3 do infra-lab com 2 nós, ambos `status: online`:

- **`virt`** (192.168.1.20): 8 cores, 16 GB RAM (~93% memória usada). Nó principal.
- **`pve2`** (192.168.1.21): Intel i5-3330 (4 cores, Ivy Bridge 2012), 7.7 GB RAM,
  **GPU NVIDIA GTX 1060 6 GB** (IOMMU group 1). Testes IA / PCI passthrough.

Storage no `pve2`: `SeagateNAS` (NFS, ~2.7 TB), `local-lvm` (~290 GB livres),
`local` (~82 GB).

API endpoint: `https://192.168.1.20:8006`. Token: `root@pam!root`. Credenciais em
`~/.env.proxmox` no WSL (chmod 600, não versionado).
