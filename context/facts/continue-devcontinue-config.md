---
key: continue-dev-config
type: factual
tags: [ai, continue-dev, vscode, dev-env]
priority: medium
---

Continue.dev (extensão VS Code) no ambiente de desenvolvimento aponta primário
direto para o [[ollama-lab]] (baixa latência LAN) e secundário para o
[[omniroute-gateway]] (fallback + cloud providers).

Config: `~/.continue/config.yaml` (Windows: `C:\Users\jose.mussauer\.continue\config.yaml`).

Papéis dos modelos:

| Role | Modelo | apiBase | Observação |
|---|---|---|---|
| chat / edit / apply | `qwen2.5-coder:7b` | `http://192.168.1.84:11434` | keepAlive 300 (libera VRAM p/ Immich ML) |
| autocomplete | `qwen2.5-coder:0.5b-base` | idem | keepAlive 1800 |
| embed (codebase) | `nomic-embed-text` | idem | keepAlive 1800 |

Alternativa: trocar `apiBase` para `http://192.168.1.117:20128/v1` e model para
`auto/best-coding` — ganha fallback cloud, perde ~50-100ms de latência.

Contexto do lab (this file's parent corpus) deve ser injetado no `systemMessage`
via `~/.lab-context.md` gerado por `lab-context-fetch.sh`.
