# secrets/

Credenciais do lab criptografadas via **SOPS + age**, versionadas no git.

## O que fica aqui

| Arquivo | Decripta em | Conteúdo |
|---|---|---|
| `env.proxmox.enc.yaml` | `~/.env.proxmox` | Token API + SSH info do cluster Proxmox (`virt` + `pve2`) |
| `env.omniroute.enc.yaml` | `~/.env.omniroute` | Bearer key + URL do gateway OmniRoute |
| `kubeconfig.enc.yaml` | `~/.kube/infra-lab.yaml` | Admin kubeconfig do cluster K3s |
| `ssh-keys.enc.yaml` | `~/.ssh/{id_ed25519,lab_id_rsa}{,.pub}` | Chaves SSH usadas para acesso ao lab |
| `app-passwords.enc.yaml` | `~/.env.lab-apps` | Senhas admin: Grafana, NetBox token, Gitea admin, etc |
| `env.agent.enc.yaml` | `~/.env.agent` | Credenciais de **escopo reduzido** para sessões de agente de IA (Claude Code e afins) — ver seção "Credenciais de agente de IA" abaixo |

## Fluxo — host novo entra no lab

1. **No host novo**, roda o bootstrap (instala sops+age + gera chave):
   ```bash
   git clone git@github.com:netomussauer/infra-lab.git
   cd infra-lab
   ./scripts/secrets-bootstrap.sh
   ```
   O script imprime a **public key** dele. Anote.

2. **No repo (owner)**, adiciona essa public key em [`.sops.yaml`](../.sops.yaml)
   sob `creation_rules[].age`, e reencripta os arquivos:
   ```bash
   sops updatekeys secrets/*.enc.yaml
   git add .sops.yaml secrets/*.enc.yaml
   git commit -m "chore(secrets): add recipient <hostname>"
   git push
   ```

3. **De volta no host novo**, puxa e descripta:
   ```bash
   git pull
   ./scripts/secrets-refresh.sh
   ```

## Fluxo — atualizar um secret

Sempre editar via `sops` para nunca deixar plaintext no disco:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops secrets/env.proxmox.enc.yaml   # abre no $EDITOR já decriptado, salva encriptado
git diff secrets/env.proxmox.enc.yaml   # deve mostrar só ENC[...] mudando
git add secrets/env.proxmox.enc.yaml
git commit -m "chore(secrets): rotate proxmox token"
git push
```

Em cada host que consome, `git pull && ./scripts/secrets-refresh.sh` pega a versão nova.

## Fluxo — revogar acesso de um host

1. Remover a linha da public key correspondente em [`.sops.yaml`](../.sops.yaml).
2. `sops updatekeys secrets/*.enc.yaml` → reencripta sem aquela recipient.
3. Commit + push.
4. **Importante**: rotacionar os secrets em si (tokens, senhas, kubeconfig).
   Só remover da whitelist age não invalida uma cópia local que já foi descriptada
   antes da revogação — o dono da chave privada revogada ainda tem os valores
   que já viu.

## Como funciona por baixo

- **age**: cada host tem par de chaves em `~/.config/sops/age/keys.txt`
  (chmod 600). Public key vai no `.sops.yaml`; private key **nunca** sai do host.
- **SOPS**: lê `.sops.yaml`, pega os recipients, encripta apenas os valores
  do YAML sob `data:` (o resto — chaves YAML, comentários, metadata sops —
  fica em cleartext). Cada value fica como `ENC[AES256_GCM,...]` no arquivo.
- **Deriva chave**: SOPS gera uma DEK (Data Encryption Key) AES-256 nova por
  arquivo, encripta a DEK com **cada** age public key da lista, e armazena
  todas as versões dentro do próprio arquivo. Descriptar precisa da private
  key de **algum** recipient (basta um).

## Trade-offs conhecidos

- **Revogação real ≠ remover recipient**. A chave privada de um host removido
  não pode mais descriptar versões futuras, mas se ela já tinha uma cópia
  local antes da revogação, o segredo pré-revogação está comprometido.
  Sempre rotacione os valores em si quando revogar um host.

- **Não versionar plaintext**. `.gitignore` cobre `~/.config/sops/age/keys.txt`
  e `*.enc.yaml.dec`. Nunca fazer `sops -d secret.enc.yaml > secret.yaml` e
  commitar por engano.

- **Backup da chave privada age**. Se você perder `~/.config/sops/age/keys.txt`
  e for o único recipient, **os secrets ficam permanentemente inacessíveis**.
  Guarde uma cópia offline (papel, dispositivo separado, cofre).

## Credenciais de agente de IA

`env.agent.enc.yaml` guarda um conjunto de credenciais **separado e de escopo
reduzido**, criado em 2026-09-18 especificamente para sessões de agente de IA
(Claude Code e afins) rodando neste WSL. A diferença para os outros arquivos
não é só "mais uma credencial encriptada" — é que, uma vez decriptado, esse
conjunto **não tem os mesmos privilégios** que as credenciais admin:

| Credencial | Escopo | Onde foi criada |
|---|---|---|
| `PROXMOX_AGENT_TOKEN_ID`/`_SECRET` | usuário `agente-ia@pve`, role `PVEAuditor` (somente auditoria — sem `VM.Allocate`, `Sys.Modify`, `Sys.PowerMgmt`), token expira em 90 dias | Datacenter → Permissions → Users/API Tokens |
| `NETBOX_AGENT_TOKEN` | usuário `agente-ia` (não-staff, não-superuser), permissão `view`-only em dcim/ipam/virtualization/tenancy/extras, token com `write_enabled: false` e expira em 90 dias | Admin → Users |
| `AGENT_SSH_PRIVATE_KEY`/`AGENT_SSH_PUBLIC_KEY` | usuário Linux `agente-ia` (criado por `ansible/playbooks/01-base-setup.yml`, tag `agente-ia`) em todos os nós do cluster — sudo restrito a uma allowlist de comandos de diagnóstico (`systemctl status`, `journalctl`, `df`, `free`, `crictl ps/logs`, etc.), **sem** `NOPASSWD:ALL` como o `labadmin` | `/etc/sudoers.d/agente-ia` em cada nó |
| `AGENT_KUBECONFIG` | `ServiceAccount agente-ia` (namespace `kube-system`) + `ClusterRole agente-ia-readonly` — leitura ampla, **sem** acesso a `Secrets`, sem nenhuma permissão de escrita | `kubernetes/bootstrap/agente-ia-rbac.yaml` |

Uma sessão de agente deve carregar **só** `~/.env.agent` (via
`./scripts/secrets-refresh.sh`, que já materializa `AGENT_SSH_PRIVATE_KEY` em
`~/.ssh/agent-ia/agente_ia_ed25519` e `AGENT_KUBECONFIG` em
`~/.kube/agent-ia.yaml`) — nunca `~/.env.proxmox`, `~/.kube/infra-lab.yaml`
ou a chave `~/.ssh/lab_id_rsa` admin. Qualquer operação que exija privilégio
maior (escrita em VM, deploy no cluster, restart de serviço) deve ser feita
pelo humano com as credenciais admin, não contornada dando mais escopo ao
agente.

**Rotação/revogação**: como os tokens Proxmox/NetBox já expiram sozinhos em
90 dias, a rotação de rotina é automática (é só gerar novos antes do prazo).
Para revogar imediatamente: apagar o token em Proxmox/NetBox, deletar o
Secret `agente-ia-token`/`ServiceAccount agente-ia` do cluster
(`kubectl delete -f kubernetes/bootstrap/agente-ia-rbac.yaml`), remover o
usuário `agente-ia` dos nós (Ansible) — e por fim rotacionar/reencriptar
`env.agent.enc.yaml` com os valores novos, igual ao fluxo de qualquer outro
secret deste diretório.

## Credencial do túnel Cloudflare (exposição pública)

`env.cloudflared.enc.yaml` guarda `CLOUDFLARE_TUNNEL_CREDENTIALS_JSON` — o
conteúdo do `credentials.json` gerado por `cloudflared tunnel create
lab-edge` (ver `docs/adr.md` ADR-013 e `kubernetes/edge/cloudflared/`). É a
única credencial deste diretório que **não** vai direto para um arquivo de
uso local: `./scripts/secrets-refresh.sh` materializa em
`~/.cloudflared/credentials.json` só como insumo para gerar o `Secret`
Kubernetes real, que precisa ser selado antes de ir pro cluster:

```bash
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/credentials.json \
  --namespace=edge \
  --dry-run=client -o yaml \
  | ./scripts/seal-secret.sh /dev/stdin > kubernetes/edge/cloudflared/sealedsecret.yaml
```

O `SealedSecret` resultante é seguro para commit (mesmo padrão do
ADR-011) — o `Secret` puro (`$HOME/.cloudflared/credentials.json`) nunca é.

**Revogação**: `cloudflared tunnel delete lab-edge` no dashboard/CLI do
Cloudflare invalida a credencial imediatamente, independente de apagar o
`SealedSecret` do cluster.

## Credencial do BookStack (scripts/bookstack-sync/)

`env.bookstack.enc.yaml` (ainda não criado neste host — ver abaixo) guarda
`BOOKSTACK_URL`, `BOOKSTACK_TOKEN_ID` e `BOOKSTACK_TOKEN_SECRET`, usados por
`scripts/bookstack-sync/sync.py` para publicar `README.md`/`docs/*.md` no
BookStack do lab (`192.168.1.76`). Ferramenta migrada de
`infra-lab-proxmox` em 2026-09-22 (ver `docs/adr.md` ADR-014).

Gerar o token: BookStack → Settings → API Tokens → Create Token. Depois,
criar o arquivo localmente (nunca commitar o `.yaml` decriptado):

```bash
cat <<'EOF' > /tmp/bookstack-staging.yaml
data:
  BOOKSTACK_URL: "http://192.168.1.76:80"
  BOOKSTACK_TOKEN_ID: "<token id gerado>"
  BOOKSTACK_TOKEN_SECRET: "<token secret gerado>"
EOF
sops --encrypt --filename-override secrets/env.bookstack.enc.yaml \
  /tmp/bookstack-staging.yaml > secrets/env.bookstack.enc.yaml
shred -u /tmp/bookstack-staging.yaml
```

`./scripts/secrets-refresh.sh` materializa em `~/.env.bookstack` a partir
daí — mesmo fluxo dos demais arquivos deste diretório.

**Revogação**: apagar o token em BookStack → Settings → API Tokens invalida
imediatamente, independente do arquivo `.enc.yaml` no repo.

## Ver também

- `.sops.yaml` — configuração dos recipients (public keys)
- `scripts/secrets-bootstrap.sh` — setup de host novo
- `scripts/secrets-refresh.sh` — atualiza secrets locais
