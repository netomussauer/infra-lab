# Rotação das senhas do Postgres compartilhado

Motivo: as senhas dos papéis do Postgres (superusuário, `amactive`, `amfit`, `realtpmsys`)
estavam em texto plano em `kubernetes/shared-infra/postgresql/secret.yaml`, versionado
em um repositório que esteve **público** no GitHub. O repositório foi tornado privado,
mas o conteúdo antigo pode ter sido copiado. A troca é a única correção real.

Script: `scripts/rotacionar-senhas-postgres.sh` (fases `preparar` e `aplicar`).

## Inventário (quem usa cada senha)

| Papel | Secret no cluster | Chave | Consumidores |
|---|---|---|---|
| `postgres` (superusuário) | `shared-infra/postgresql-secret` | `POSTGRES_PASSWORD` | StatefulSet `postgresql` (só no initdb) |
| `amactive` | `amactive/amactive-secrets` | `pg-password` | `amactive-api`, `amactive-worker`, CronJob `amactive-expirar-reservas` |
| `amfit` | `amfit/amfit-secrets` | `pg-password` | `amfit-api` |
| `realtpmsys` | `realtpmsys/realtpmsys-secrets` | `pg-password` | `realtpmsys-api` |

Papéis **fora do escopo** desta rotação (senha desconhecida; investigar antes):
`realtpmsys_test` e `training_hub`.

Outros segredos em texto plano versionados, a tratar depois desta rotação:
- `kubernetes/shared-infra/postgres-exporter/secret.yaml` (`DATA_SOURCE_NAME`, string de conexão com senha de banco)
- `kubernetes/shared-infra/redis/secret.yaml` (`REDIS_PASSWORD`)
- `kubernetes/network-services/pihole/secret.yaml` (`WEBPASSWORD`)

## Por que duas fases

- **Ordem:** o Secret de cada aplicação precisa receber a senha nova **antes** de o
  Postgres trocá-la. Senão as aplicações caem na hora.
- **Fase preparar:** não toca no cluster. Gera e cifra, e deixa o SealedSecret pronto.
- **Fase aplicar:** só roda com `CONFIRMAR=sim`.

## Passos

### 1. Preparar (sem impacto)

```bash
cd infra-lab && git pull
./scripts/rotacionar-senhas-postgres.sh preparar
```

Resultado: `secrets/postgres-rotacao.enc.yaml` (cifrado com SOPS) e
`kubernetes/shared-infra/postgresql/sealedsecret.yaml`. Revise com `git diff` antes de commitar.

### 2. Selar os Secrets das aplicações

Cada Secret de aplicação contém **outras chaves além da senha do banco**
(`jwt-secret`, `credencial-canal-encryption-key`, `minio-*`, `redis-password`...).
Um SealedSecret substitui o Secret inteiro, então ele precisa conter **todas** as chaves.

Para cada um: leia as chaves atuais no seu terminal, substitua só `pg-password` pela
senha nova do arquivo cifrado, sele com `scripts/seal-secret.sh` e aplique.
Nunca cole valores em chat, commit ou log.

Ordem recomendada: `amactive`, depois `amfit`, depois `realtpmsys`.

### 3. Conferir os pré-requisitos

Antes da fase aplicar, confirme que cada Secret de aplicação já foi atualizado
(sem exibir valores): `kubectl get secret <nome> -n <ns> -o jsonpath='{.metadata.resourceVersion}'`
deve ter mudado em relação ao registro anterior.

### 4. Aplicar (com impacto)

```bash
CONFIRMAR=sim ./scripts/rotacionar-senhas-postgres.sh aplicar
```

O script aplica o SealedSecret do Postgres, espera as 4 chaves, troca as senhas
dentro do banco (`ALTER USER`, pelo stdin) e reinicia as quatro aplicações.

### 5. Verificar

- `kubectl get pods -A | grep -E 'amactive|amfit|realtpmsys'`: todos `1/1 Running`.
- `/health` da API do amactive retorna `database: ok`.
- Logs das aplicações sem `password authentication failed`.

### 6. Limpeza

- Remover `kubernetes/shared-infra/postgresql/secret.yaml` (texto plano) do repositório,
  substituído pelo SealedSecret.
- Tratar os outros três segredos em texto plano (lista acima), com o mesmo processo.
- Conferir `git log -p` para não haver novos valores em texto plano.

## Rollback

Não há como voltar às senhas antigas: elas não estão no repositório e não foram
guardadas. Se algo falhar, **corrija para a frente**: reexecute o `ALTER USER` com a
senha do arquivo cifrado (`sops --decrypt secrets/postgres-rotacao.enc.yaml`) e
reinicie a aplicação afetada.

## Notas

- O Secret `postgresql-secret` no cluster tinha só 3 chaves; a `AMACTIVE_PASSWORD` que o
  StatefulSet referencia não existia no cluster (ver a nota P32 em `docs/runbook.md`).
  A rotação passa a criar essa chave, o que corrige o desencontro.
- Alterar o Secret não reinicia o pod do Postgres. A senha do superusuário só é lida no
  initdb; a troca real acontece pelo `ALTER USER`.
- A conferência dos pré-requisitos (passo 3) é manual: o script não verifica sozinho se
  os Secrets das aplicações já foram atualizados.
