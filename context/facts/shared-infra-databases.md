---
key: shared-infra-databases
type: factual
tags: [databases, postgres, redis, shared-infra]
priority: high
---

Bancos compartilhados no cluster K3s, namespace `shared-infra`. Ambos StatefulSets
rodam no nó `ubuntu-neto` (label `workload=monitoring`) com storage `local-path`
em **HDD rotacional** (`sda`, `ROTA=1` — não é SSD; ver `docs/runbook.md` P26).
Sob saturação de IO as sondas `exec` estouravam; desde 2026-09-24 têm
`timeoutSeconds` 5–10 s e `failureThreshold: 6`.

**PostgreSQL 16** (`postgresql-0`):
- Imagem: `postgres:16-alpine`.
- Service: `postgresql.shared-infra.svc.cluster.local:5432` (ClusterIP).
- 10Gi PVC `local-path`. Requests: 250m CPU / 256Mi RAM.
- Databases criados pelo initdb (`kubernetes/shared-infra/postgresql/configmap.yaml`):
  `realtpmsys` (owner `realtpmsys`), `amfit` (owner `amfit`) — ambos com
  `REVOKE ALL ON SCHEMA public FROM PUBLIC` (schema restrito ao owner).
- **Drift (registrado em 2026-09-24):** os projetos `amactive` e
  `training-performance-hub` também usam este Postgres, mas seus bancos/usuários
  **não estão no initdb** — foram criados manualmente e só existem no PVC.
  `training-performance-hub` usa `user=training_hub`/`database=training_hub`
  (visto no log do backend); `amactive` recebe a conexão via `DATABASE_URL`
  em Secret (nome do banco/usuário não verificado — Secret não foi lido). Se o
  PVC `data-postgresql-0` for perdido ou recriado, esses bancos somem e o initdb
  não os recria. Pendente: incluí-los no initdb (com senhas vindas de Secret,
  como `AMFIT_PASSWORD`) e/ou documentar backup/restauração.
- Credenciais em Secret `postgresql-secret`.
- Clientes que saem com erro se o banco cair no startup (sem retry) entram em
  crashloop enquanto o Postgres reinicia — ex.: backend do
  `training-performance-hub` (28 restarts em ~3 dias).

**Redis 7** (`redis-0`):
- Imagem: `redis:7-alpine`.
- Service: `redis.shared-infra.svc.cluster.local:6379` (ClusterIP).
- 2Gi PVC `local-path`. Requests: 100m CPU / 128Mi RAM.
- Config: maxmemory 200mb + allkeys-lru + AOF + RDB.
- Auth via `requirepass` do Secret `redis-secret`.

Aplicações amfit e realtpmsys consomem via DNS interno do cluster. Localmente
(dev via `docker-compose`) os equivalentes são `localhost:5432` e `localhost:6379`.

Referências: [[k3s-cluster]] · [[k3s-node-recovery]]
