# Lab Context — corpus compartilhado do infra-lab

Base de conhecimento estruturada em **blocos atômicos** consumida por qualquer host
de desenvolvimento via OmniRoute. Cada bloco é um `.md` autocontido com frontmatter
YAML, agrupado em `context/facts/`.

## Fluxo

```
context/facts/*.md                              (fonte de verdade, versionada)
        ↓ build-lab-context.py
context/build/LAB-CONTEXT.md                    (corpus consolidado, gerado)
        ↓ omniroute-upload.sh
POST /v1/files @ OmniRoute (192.168.1.117)      (distribuição centralizada)
        ↓ lab-context-fetch.sh   (roda em cada host)
~/.lab-context.md                               (cache local do host)
        ↓ system prompt de Continue.dev / Open-WebUI / etc
LLM chega ao chat com o contexto do lab
```

Fonte-de-verdade do **conteúdo** = git (`context/facts/`). Fonte-de-verdade da
**distribuição** = `/v1/files` do OmniRoute (source-of-truth central acessível a
qualquer host com a API key).

## Formato do bloco atômico

Cada arquivo em `context/facts/*.md` segue:

```markdown
---
key: proxmox-cluster                  # slug único (usado como âncora)
type: semantic                        # semantic | factual | episodic | procedural
tags: [proxmox, infra, topology]
priority: high                        # high | medium | low (ordenação)
expires_at: null                      # ISO8601 opcional (fato temporário)
---

Conteúdo curto e denso do bloco (idealmente 2-4 parágrafos, sem redundância).

Referências: [[outro-bloco]] se relevante.
```

Regras:

- **Nunca** colocar credenciais/tokens/senhas — corpus é upload público pra API
  key `self:usage` do OmniRoute (leitura de todos os hosts).
- Bloco = 1 fato/decisão/procedimento. Se for maior, quebrar em 2.
- `key` deve ser lowercase-kebab-case e único em todo `facts/`.
- `type` determina como o LLM deve tratar:
  - `semantic` — conceito, arquitetura (o que É)
  - `factual` — valor/config específica (endereço, versão, path)
  - `episodic` — evento passado (crash, upgrade, mudança)
  - `procedural` — how-to (rebootar X, restaurar Y)

## Uso

### Atualizar o corpus (ao editar/adicionar blocos)

```bash
cd infra-lab/context
python3 build-lab-context.py                    # gera build/LAB-CONTEXT.md
./omniroute-upload.sh                           # sobe pro OmniRoute
```

Ou automatizar via git hook (`post-push`) apontando pro cron do repo mirror.

### Configurar um novo host de dev

```bash
curl -O https://raw.githubusercontent.com/netomussauer/infra-lab/main/context/lab-context-fetch.sh
chmod +x lab-context-fetch.sh
./lab-context-fetch.sh                          # gera ~/.lab-context.md
```

Depois configura o cliente LLM (Continue.dev / Open-WebUI / etc) apontando o
system prompt para o conteúdo de `~/.lab-context.md`.

## Migração futura para /v1/memories

Quando o OmniRoute expuser a API pública de memories (feature latente na v3.8.49),
cada bloco `.md` do `facts/` pode virar 1 entrada em `memories` mantendo `type`,
`tags` e `key`. O `build-lab-context.py` ganhará um modo `--sync-memories` para
POST individual. **Sem retrabalho no conteúdo**.
