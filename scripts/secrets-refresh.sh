#!/usr/bin/env bash
# secrets-refresh.sh
#
# Executado em hosts de dev com chave age já registrada em .sops.yaml.
# Decripta secrets/*.enc.yaml do repo e escreve nos paths locais convencionados:
#   ~/.env.proxmox
#   ~/.env.omniroute
#   ~/.kube/infra-lab.yaml
#   ~/.ssh/id_ed25519, id_ed25519.pub, lab_id_rsa, lab_id_rsa.pub
#   ~/.env.lab-apps   (Grafana/NetBox/Gitea/etc)
#
# Requer: sops, age, python3 (yaml stdlib), curl (opcional para bootstrap remoto).
#
# Uso:
#   cd infra-lab && git pull
#   ./scripts/secrets-refresh.sh
#
# Se estiver ausente sops/age, roda scripts/secrets-bootstrap.sh primeiro.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_DIR="$REPO_ROOT/secrets"

if ! command -v sops >/dev/null 2>&1; then
  echo "ERRO: sops não instalado. Rode scripts/secrets-bootstrap.sh." >&2
  exit 1
fi

if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
  echo "ERRO: chave age não encontrada em ~/.config/sops/age/keys.txt." >&2
  echo "Rode scripts/secrets-bootstrap.sh para gerar." >&2
  exit 1
fi

export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

# ---------------------------------------------------------------------------
# Extrair valores encriptados via python3 (yaml stdlib) e escrever no path
# ---------------------------------------------------------------------------

write_env_file() {
  # args: <secret_file> <target_path>
  local src="$1" dest="$2"
  sops -d "$src" | python3 -c "
import yaml, sys, os
d = yaml.safe_load(sys.stdin)['data']
os.umask(0o077)  # arquivo criado com 600
with open('$dest', 'w') as f:
    for k, v in d.items():
        # escapa aspas duplas no valor
        v = str(v).replace('\"', '\\\\\"')
        f.write(f'export {k}=\"{v}\"\n')
"
  chmod 600 "$dest"
  echo "  ✓ $dest ($(wc -l < "$dest") linhas)"
}

write_kubeconfig() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  sops -d "$src" | python3 -c "
import yaml, sys
d = yaml.safe_load(sys.stdin)['data']
print(d['kubeconfig'], end='')
" > "$dest"
  chmod 600 "$dest"
  echo "  ✓ $dest ($(wc -c < "$dest") bytes)"
}

write_ssh_keys() {
  local src="$1"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  sops -d "$src" | python3 -c "
import yaml, sys, os
d = yaml.safe_load(sys.stdin)['data']
os.umask(0o077)
for k, v in d.items():
    # id_ed25519_pub -> id_ed25519.pub
    if k.endswith('_pub'):
        fname = k[:-4] + '.pub'
    else:
        fname = k
    path = os.path.expanduser('~/.ssh/' + fname)
    with open(path, 'w') as f:
        f.write(v)
    # pub keys podem ser 644; privadas 600
    os.chmod(path, 0o644 if fname.endswith('.pub') else 0o600)
    print(f'  ✓ ~/.ssh/{fname}')
"
}

echo "=== secrets-refresh ==="
echo "sops: $(sops --version 2>/dev/null | head -1)"
echo "recipient (this host): $(grep '^# public key:' "$HOME/.config/sops/age/keys.txt" | awk '{print $NF}')"
echo

echo "== env files =="
[ -f "$SECRETS_DIR/env.proxmox.enc.yaml" ] && {
  write_env_file "$SECRETS_DIR/env.proxmox.enc.yaml" "$HOME/.env.proxmox"
  # Trailer com TF_VAR_* derivadas (consumidas automaticamente pelo Terraform)
  cat >> "$HOME/.env.proxmox" <<'EOF'
export TF_VAR_proxmox_api_url="$PROXMOX_URL"
export TF_VAR_proxmox_api_token_id="$PROXMOX_TOKEN_ID"
export TF_VAR_proxmox_api_token_secret="$PROXMOX_TOKEN_SECRET"
export TF_VAR_proxmox_endpoint="$PROXMOX_ENDPOINT"
export TF_VAR_proxmox_node="$PROXMOX_NODE"
export TF_VAR_proxmox_ssh_private_key="$PROXMOX_SSH_KEY"
export TF_VAR_proxmox_tls_insecure="$PROXMOX_TLS_INSECURE"
EOF
}
[ -f "$SECRETS_DIR/env.omniroute.enc.yaml" ] && write_env_file "$SECRETS_DIR/env.omniroute.enc.yaml" "$HOME/.env.omniroute"
[ -f "$SECRETS_DIR/app-passwords.enc.yaml" ] && write_env_file "$SECRETS_DIR/app-passwords.enc.yaml" "$HOME/.env.lab-apps"

echo
echo "== kubeconfig =="
[ -f "$SECRETS_DIR/kubeconfig.enc.yaml" ] && write_kubeconfig "$SECRETS_DIR/kubeconfig.enc.yaml" "$HOME/.kube/infra-lab.yaml"

echo
echo "== SSH keys =="
[ -f "$SECRETS_DIR/ssh-keys.enc.yaml" ] && write_ssh_keys "$SECRETS_DIR/ssh-keys.enc.yaml"

echo
echo "OK — secrets restaurados. Para carregar env vars no shell atual:"
echo "  source ~/.env.proxmox"
echo "  source ~/.env.omniroute"
echo "  export KUBECONFIG=~/.kube/infra-lab.yaml"
