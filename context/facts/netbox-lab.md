---
key: netbox-lab
type: factual
tags: [ipam, netbox, docs]
priority: medium
---

NetBox v4.4.1 (IPAM/DCIM) rodando em VM no cluster Proxmox.

- URL: **https://192.168.1.72** (HTTPS 443) — mudou de `192.168.1.72:8000` HTTP em 2026-06-22.
- DNS: netbox.lab.local (via Pi-hole).
- Django 5.2.6 + Python 3.11.2.
- Token: em `~/.env.netbox` no WSL (não versionado).

Recursos relevantes já registrados:
- IP `192.168.1.20/24` (virt Proxmox principal)
- IP `192.168.1.21/24` (pve2 com GPU NVIDIA para IA)
- IP `192.168.1.85/24` (immich CT 103)
- IP `192.168.1.117/24` (omniroute CT 107)
- Cluster Virtualization: `proxmox-lab` (id=1, type Proxmox VE).

Usado por [[infra-lab-vmware]] e projetos IaC para reservar IPs antes de
provisionar via Terraform. Automação via API REST retorna JSON — filtragem em
Python usando `pynetbox` ou `requests` direto.
