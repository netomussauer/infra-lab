---
key: immich-lab
type: factual
tags: [ai, immich, photos, gpu]
priority: high
---

Immich v3.0.3 (galeria de fotos self-hosted) rodando como LXC CT 103 no `pve2`.
Hostname `immich`. Instalação **nativa systemd**, não Docker (community-script v2).

- IP: 192.168.1.85/24 estático, gw 192.168.1.254. DNS: immich/photos.lab.local.
- Web/API: `http://192.168.1.85:2283`.
- GPU: passthrough compartilhado com CT 101 (`/dev/nvidia*`).
- Rootfs: `local-lvm:vm-103-disk-0` 15 GB (Postgres 16 + vectorchord em SSD local — obrigatório).
- Library de fotos: mount `mp0` NFS SeagateNAS 200 GB em `/mnt/immich-library` (expansível com `pct resize`).
- Config app: `/opt/immich/.env`, `IMMICH_MEDIA_LOCATION=/mnt/immich-library`.

Services systemd:
- `immich-web.service` (Node, porta 2283) — API + Web UI
- `immich-ml.service` (Python, porta 3003) — Machine Learning
- `postgresql@16-main.service` — Postgres 16 + `vectorchord` (não pgvector)
- `redis-server.service`

Estado do ML: **rodando em CPU** (pendente ativar CUDA via `onnxruntime-gpu` no
venv Python + `libcudnn9-cuda-12` — trade-off VRAM com Ollama que já usa a GPU).

Referências: [[proxmox-cluster]] · [[ollama-lab]]
