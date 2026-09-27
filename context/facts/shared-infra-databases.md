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
  `realtpmsys` (owner `realtpmsys`), `amfit` (owner `amfit`), e desde
  2026-09-27 também `amactive` (owner `amactive`, senha em
  `AMACTIVE_PASSWORD` no Secret `postgresql-secret`) — todos com
  `REVOKE ALL ON SCHEMA public FROM PUBLIC` (schema restrito ao owner). A
  senha de `AMACTIVE_PASSWORD` foi gerada do zero nesse reconcile e **não é**
  a senha em uso pelo banco `amactive` ao vivo hoje — o script de initdb só
  roda em data dir vazio, então isso só produz efeito se o PVC
  `data-postgresql-0` for perdido e recriado; nesse cenário, atualize também
  o Secret do app `amactive` para casar com essa senha. Ver P32 no runbook.
- **Drift ainda pendente (registrado em 2026-09-24, `training_hub` mantido
  fora do initdb deliberadamente):** `training-performance-hub` também usa
  este Postgres (`user=training_hub`/`database=training_hub`, visto no log
  do backend), mas seu banco/usuário **não está no initdb automático** —
  existe um script `training-performance-hub-provisioning.template.sql`
  nesse mesmo diretório, marcado explicitamente como execução manual única
  por um administrador autorizado, e não foi incorporado ao initdb porque
  `training-performance-hub` ainda está em desenvolvimento e mudanças nesse
  projeto ficam a cargo do próprio dono (ver runbook). Se o PVC
  `data-postgresql-0` for perdido, esse banco não é recriado automaticamente
  — seria necessário rodar o template manualmente de novo.
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
