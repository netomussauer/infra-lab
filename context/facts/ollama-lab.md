---
key: ollama-lab
type: factual
tags: [ai, ollama, gpu]
priority: high
---

**Status desde 2026-09-18: PARADO** (`onboot=0`, CT desligado via Proxmox).
Métricas de Prometheus (`nvidia_smi_utilization_gpu_ratio`) e RRD do Proxmox
mostraram 0% de uso de GPU e CPU nos 30 dias anteriores — nenhum request real
chegando à API, apesar de configurado como provider `ollama-local/*` no
OmniRoute. Container mantido (não deletado) para reversão fácil caso algo
dependa dele silenciosamente; reavaliar remoção definitiva depois de um
período de observação. Liberar essa GPU também desbloqueia o plano já
documentado de ativar CUDA no `immich-ml` (hoje rodando em CPU só por causa
do trade-off de VRAM com o Ollama).

Ollama v0.30.10 rodando como LXC CT 101 no `pve2`. Hostname `ollama`.

- IP: 192.168.1.84 (DHCP via vmbr0). DNS: ollama.lab.local.
- API: `http://192.168.1.84:11434` (OpenAI-compat em `/v1`).
- GPU: NVIDIA GTX 1060 6 GB via PCI passthrough (`/dev/nvidia*` bind mount).
- Rootfs: `local-lvm:vm-101-disk-0` (SSD local — Postgres+data exigem, NFS
  causa lentidão severa).
- Recursos: 4 cores, 4 GB RAM.

Modelos disponíveis (todos qwen2.5):
- `qwen2.5-coder:7b` (chat/edit)
- `qwen2.5-coder:3b`
- `qwen2.5-coder:1.5b-base`
- `qwen2.5-coder:0.5b-base` (autocomplete)
- `qwen2.5:0.5b`
- `nomic-embed-text` (embeddings)

Sob o gateway [[omniroute-gateway]] o provider é `ollama-local/*` (com
`baseUrl=http://192.168.1.84:11434/v1`).

Gotcha: se `pve2` reboot, o driver NVIDIA/UVM não carrega automático — o CT 101
falha em subir com `Device /dev/nvidia-uvm does not exist`. Fix definitivo já
instalado: unit systemd `nvidia-uvm-init.service` no pve2 (após pve2 boot,
executa `nvidia-modprobe -u -c 0` antes de `pve-guests.service`).

Referências: [[proxmox-cluster]] · [[omniroute-gateway]]
