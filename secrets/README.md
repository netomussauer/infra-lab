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

## Ver também

- `.sops.yaml` — configuração dos recipients (public keys)
- `scripts/secrets-bootstrap.sh` — setup de host novo
- `scripts/secrets-refresh.sh` — atualiza secrets locais
