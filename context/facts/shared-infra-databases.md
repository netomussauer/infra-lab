---
key: shared-infra-databases
type: factual
tags: [databases, postgres, redis, shared-infra]
priority: high
---

Bancos compartilhados no cluster K3s, namespace `shared-infra`. Ambos StatefulSets
rodam no nó `ubuntu-neto` (label `workload=monitoring`) com storage `local-path`
(SSD local).

**PostgreSQL 16** (`postgresql-0`):
- Imagem: `postgres:16-alpine`.
- Service: `postgresql.shared-infra.svc.cluster.local:5432` (ClusterIP).
- 10Gi PVC `local-path`. Requests: 250m CPU / 256Mi RAM.
- Databases: `realtpmsys` (owner `realtpmsys`), `amfit` (owner `amfit`) —
  ambos com `REVOKE ALL ON SCHEMA public FROM PUBLIC` (schema restrito ao owner).
- Credenciais em Secret `postgresql-secret`.

**Redis 7** (`redis-0`):
- Imagem: `redis:7-alpine`.
- Service: `redis.shared-infra.svc.cluster.local:6379` (ClusterIP).
- 2Gi PVC `local-path`. Requests: 100m CPU / 128Mi RAM.
- Config: maxmemory 200mb + allkeys-lru + AOF + RDB.
- Auth via `requirepass` do Secret `redis-secret`.

Aplicações amfit e realtpmsys consomem via DNS interno do cluster. Localmente
(dev via `docker-compose`) os equivalentes são `localhost:5432` e `localhost:6379`.

Referências: [[k3s-cluster]] · [[k3s-node-recovery]]
