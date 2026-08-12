---
key: k3s-node-recovery
type: procedural
tags: [k3s, ops, recovery, ubuntu-neto]
priority: high
---

Após um nó K3s ficar offline por muito tempo (crash, cabo mal contato do
`ubuntu-neto`, restart forçado), **restartar o `k3s-agent` imediatamente após o
nó voltar `Ready`** — evita ciclo de DNS/conntrack stale onde pods novos herdam
regras iptables apontando pra IPs de pods que não existem mais.

Sintoma se não fizer: DNS lookups intermitentes para `kube-dns` (`10.43.0.10:53`)
com `i/o timeout` — pods novos como Grafana entram em CrashLoopBackOff pelo
liveness, postgres-exporter fica 0/1 com `/metrics` travando.

Como aplicar (WSL não alcança rede LAN via SSH pra hosts crashados às vezes,
então via pod nsenter privilegiado):

```bash
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: {name: node-restart-k3s, namespace: kube-system}
spec:
  nodeName: <NODE_NOTREADY>
  hostPID: true
  hostNetwork: true
  restartPolicy: Never
  containers:
  - name: nsenter
    image: alpine:3.20
    securityContext: {privileged: true}
    command: ["nsenter","--target","1","--mount","--uts","--ipc","--net","--pid","--","systemctl","restart","k3s-agent"]
YAML
```

Validar: lookup de nomes internos deve responder em ~150 ms (não 2000+ ms).

WSL alcança 192.168.1.0/24 via **TCP** (Windows NAT bridge) para APIs (Proxmox,
NetBox, HTTP dos serviços) mas **não via ICMP** (ping bloqueado) nem via SSH em
alguns cenários — por isso a operação `systemctl restart` no host precisa ser
via pod nsenter em vez de SSH direto (quando o host está com rota degradada).

Referências: [[k3s-cluster]]
