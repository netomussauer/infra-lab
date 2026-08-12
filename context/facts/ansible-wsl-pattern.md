---
key: ansible-wsl-pattern
type: procedural
tags: [ansible, wsl, dev-env]
priority: medium
---

Executar Ansible do WSL Ubuntu (usado no lab) exige heredoc + export explícito
do PATH — o `$PATH` do Windows tem parênteses (`Program Files (x86)`) que
quebra qualquer `wsl -d Ubuntu -- bash -c "..."`.

**Padrão obrigatório:**

```bash
wsl -d Ubuntu -- bash << 'EOF'
export PATH=/home/netomussauer/.local/bin:/usr/local/bin:/usr/bin:/bin
cd /mnt/c/Users/jose.mussauer/Documents/projetos/infra-lab/ansible
ansible-playbook -i inventory/hosts.yml playbooks/NOME.yml
EOF
```

**Nunca** usar `wsl -d Ubuntu -- bash -c "export PATH=... && ..."` — quebra com
parênteses no PATH do Windows.

**Hostname real vs inventário Ansible** (nomes diferentes entre inventário do
Ansible e o hostname efetivo do Kubernetes):

- `notebook-i5` (inventário Ansible) → `ubuntu-neto` (hostname K8s)
- `raspberry-pi` (inventário Ansible) → `raspneto` (hostname K8s)

Referências: [[k3s-cluster]]
