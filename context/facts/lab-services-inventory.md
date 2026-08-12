---
key: lab-services-inventory
type: factual
tags: [inventory, endpoints, dns]
priority: high
---

Endpoints LoadBalancer ativos no lab (MetalLB pool 192.168.1.200-220 e 50-59):

| Serviço | Endpoint | DNS interno (`.lab.local`) |
|---|---|---|
| Pi-hole (DNS interno + filtro) | http://192.168.1.53 | pihole |
| Gitea | http://192.168.1.201 | gitea |
| Harbor (registry) | http://192.168.1.202 | harbor |
| ArgoCD | http://192.168.1.203 | argocd |
| Tekton EventListener | http://192.168.1.204 | tekton |
| amfit API / Web / MinIO | 205 / 206 / 207 | api.amfit / app.amfit / minio.amfit |
| realtpmsys API / Web | 208 / 211 | api.realtpmsys / — |
| Open-WebUI (chat) | http://192.168.1.209 | chat / openwebui |
| Grafana | http://192.168.1.210 | grafana |

Fora do K3s:
- NetBox (IPAM): https://192.168.1.70 (netbox / netbox.lab.local)
- Ollama API: http://192.168.1.84:11434 (ollama.lab.local) — CT 101 LXC @ pve2
- Immich (fotos): http://192.168.1.85:2283 (immich / photos.lab.local) — CT 103 LXC @ pve2
- OmniRoute (AI Gateway): http://192.168.1.117:20128 (omniroute.lab.local) — CT 107 LXC @ pve2

Gateway padrão da LAN: **192.168.1.254** (NÃO 192.168.1.1 — erro comum de wizard
Proxmox). DNS interno: 192.168.1.53 (Pi-hole).

Referências: [[proxmox-cluster]] · [[k3s-cluster]]
