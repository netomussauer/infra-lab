---
key: k3s-cluster
type: semantic
tags: [k3s, kubernetes, infra, topology]
priority: high
---

Cluster K3s v1.29.3 do infra-lab com 5 nós:

| Node | IP | Papel |
|---|---|---|
| `k3s-server` | 192.168.1.30 | control-plane, master |
| `k3s-worker-cicd` | 192.168.1.31 | worker CI/CD |
| `ci-runner` | 192.168.1.32 | worker Tekton runner |
| `ubuntu-neto` | 192.168.1.67 (era .65 antes de crash em 2026-06) | worker bare-metal com label `workload=monitoring` |
| `raspneto` | 192.168.1.110 | worker ARMv7 (Raspberry Pi) com label `workload=edge` |

Kubeconfig: `~/.kube/infra-lab.yaml` no WSL (`KUBECONFIG=~/.kube/infra-lab.yaml`).
CNI: Flannel VXLAN. LoadBalancer: MetalLB (pool lab `192.168.1.200-220`, pool
infra `192.168.1.50-59`). Sem IngressController separado — Traefik do K3s desabilitado.

O nó `ubuntu-neto` é SPOF do stack de observability e do shared-infra (Postgres,
Redis, Prometheus, Grafana, Loki, Alertmanager) porque tem PVC `local-path`
ancorado nele. Ao cair, aplicativos amfit e realtpmsys ficam sem banco.

Referências: [[k3s-node-recovery]] · [[shared-infra-databases]]
