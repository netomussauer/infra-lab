---
key: omniroute-gateway
type: factual
tags: [ai, gateway, omniroute]
priority: high
---

OmniRoute v3.8.49 (AI Gateway multi-provider LLM) rodando como LXC CT 107 no
`pve2`. Hostname `omniroute`. Instalação nativa via `npm install -g omniroute`
(Node 24), systemd service `omniroute.service`.

- IP: 192.168.1.117 (DHCP — pode variar em reboot; item pendente: reserva DHCP).
- DNS: omniroute.lab.local.
- Endpoint OpenAI-compat: `http://192.168.1.117:20128/v1`.
- Data dir: `/root/.omniroute/` (storage.sqlite, call_logs, db_backups).
- Config: `/root/.omniroute/.env`.

Expõe **~144 modelos via 14 providers** simultaneamente:
- `gemini/*` (11 modelos) · `groq/*` (6) · `ollama-local/*` (6 — aponta pra
  [[ollama-lab]]) · `ollama/*` (6 — duplicado, consolidar) · `auto/*` (38
  roteamento inteligente) · providers free (aug, tllm, ddgw, oc, felo, veo,
  pepper, mcode).
- Auto-routing (`auto/best-coding`, `auto/best-fast`, etc.) escolhe provider
  automaticamente por qualidade/custo/latência.

Integração com clientes do lab:
- **Continue.dev** (VS Code): backend primário direto no Ollama (baixa
  latência), OmniRoute como alternativa via `auto/best-coding`.
- **Open-WebUI**: 2 conexões — Ollama direto (via `ollamaUrls` no helm-values) +
  OmniRoute como OpenAI-compat (configurado via Admin UI, persiste em SQLite do PVC).

Feature "Memória" latente no schema (`memories`, `memory_fts`, `memory_vec_meta`,
`skills`, `context_handoffs`) mas **API pública ainda não expõe** na v3.8.49 —
por isso o corpus do lab é distribuído via `/v1/files` (source-of-truth de contexto).
