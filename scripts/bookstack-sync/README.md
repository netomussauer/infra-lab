# bookstack-sync

Script Python que sincroniza os documentos técnicos do `infra-lab` para o
BookStack do laboratório (CT 106, `192.168.1.64`, ver `docs/architecture.md`
§2.3).

Migrado de `infra-lab-proxmox` em 2026-09-22 e adaptado para a estrutura
real de docs deste repo (arquivo único por tema, não um diretório com uma
página por arquivo) — ver `docs/adr.md` ADR-014.

Origem → destino:

| Arquivo local          | Livro no BookStack             |
|-------------------------|---------------------------------|
| `README.md`             | Visão Geral                     |
| `docs/architecture.md`  | Arquitetura                     |
| `docs/adr.md`           | Architecture Decision Records   |
| `docs/runbook.md`       | Runbook                         |

Todos os livros ficam dentro da Prateleira `infra-lab`.

Hierarquia BookStack: **Prateleira (Shelf) → Livro (Book) → Página (Page)**

Cada arquivo vira uma página única (título = primeiro `# H1` do arquivo).
Idempotente por hash do conteúdo — arquivo sem alteração recebe `[SKIP]`,
sem nova versão criada no BookStack.

---

## Pré-requisitos

- Python 3.10 ou superior
- pip (gerenciador de pacotes Python)
- Acesso de rede ao BookStack com token de API válido

Instale as dependências:

```bash
pip install -r scripts/bookstack-sync/requirements.txt
```

---

## Configuração de variáveis de ambiente

O script requer três variáveis obrigatórias. Nunca exportar os valores reais
manualmente num arquivo versionado — usar `./scripts/secrets-refresh.sh`
(ver `secrets/README.md` seção "Credencial do BookStack"), que materializa
`~/.env.bookstack` a partir de `secrets/env.bookstack.enc.yaml` (SOPS).

```bash
export BOOKSTACK_URL="http://192.168.1.64:80"
export BOOKSTACK_TOKEN_ID="<gerado em Settings → API Tokens no BookStack>"
export BOOKSTACK_TOKEN_SECRET="<idem>"
```

---

## Uso

```bash
# Dry-run (verificar o que seria publicado, sem escrever nada)
python scripts/bookstack-sync/sync.py --dry-run --verbose

# Publicar arquivos novos e alterados
python scripts/bookstack-sync/sync.py

# Forçar republicação de tudo, ignorando o hash
python scripts/bookstack-sync/sync.py --force
```

## Ver também

- `docs/adr.md` ADR-014 — decisão de migrar esta ferramenta do
  `infra-lab-proxmox` (descontinuado) para cá.
- `secrets/README.md` — fluxo de credencial do BookStack.
