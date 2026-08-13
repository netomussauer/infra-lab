#!/usr/bin/env bash
# secrets-bootstrap.sh
#
# Setup inicial de um host novo pra participar do secret sharing do lab.
# 1. Instala sops + age (binários standalone em ~/.local/bin)
# 2. Gera par de chaves age (se ainda não existir)
# 3. Imprime a public key desta máquina — cole em .sops.yaml do repo
#
# Após executar este script:
#   - Owner do repo adiciona a nova public key em .sops.yaml
#   - Owner roda: sops updatekeys secrets/*.enc.yaml
#   - Commit + push
#   - Este host faz `git pull && ./scripts/secrets-refresh.sh` pra descriptar

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR"

# Adicionar ~/.local/bin ao PATH se ainda não estiver
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "AVISO: $INSTALL_DIR não está no PATH. Adicione em ~/.bashrc ou ~/.zshrc:"
     echo "  export PATH=$INSTALL_DIR:\$PATH"
     ;;
esac

echo "=== 1) Instalar age ==="
if command -v age >/dev/null 2>&1; then
  echo "  já instalado: $(age --version)"
else
  AGE_VER=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  echo "  latest: $AGE_VER"
  curl -sL "https://github.com/FiloSottile/age/releases/download/${AGE_VER}/age-${AGE_VER}-linux-amd64.tar.gz" \
    | tar xz -C /tmp
  mv /tmp/age/age /tmp/age/age-keygen "$INSTALL_DIR/"
  chmod +x "$INSTALL_DIR/age" "$INSTALL_DIR/age-keygen"
  rm -rf /tmp/age
  echo "  instalado: $(${INSTALL_DIR}/age --version)"
fi

echo
echo "=== 2) Instalar sops ==="
if command -v sops >/dev/null 2>&1; then
  echo "  já instalado: $(sops --version | head -1)"
else
  SOPS_VER=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  echo "  latest: $SOPS_VER"
  curl -sL "https://github.com/getsops/sops/releases/download/${SOPS_VER}/sops-${SOPS_VER}.linux.amd64" \
    -o "$INSTALL_DIR/sops"
  chmod +x "$INSTALL_DIR/sops"
  echo "  instalado: $($INSTALL_DIR/sops --version | head -1)"
fi

echo
echo "=== 3) Gerar chave age (se ainda não existir) ==="
mkdir -p "$HOME/.config/sops/age"
KEY_FILE="$HOME/.config/sops/age/keys.txt"

if [ -f "$KEY_FILE" ]; then
  echo "  já existe: $KEY_FILE (mantendo)"
else
  "$INSTALL_DIR/age-keygen" -o "$KEY_FILE" 2>&1
  chmod 600 "$KEY_FILE"
  echo "  criada em $KEY_FILE"
fi

echo
echo "=== 4) Public key desta máquina ==="
PUBKEY=$(grep '^# public key:' "$KEY_FILE" | awk '{print $NF}')
HOSTNAME_TAG="$(whoami)@$(hostname)"
echo "  hostname: $HOSTNAME_TAG"
echo "  public key: $PUBKEY"

echo
echo "=========================================================================="
echo "  PRÓXIMOS PASSOS (dono do repo):"
echo
echo "  1. Adicione esta linha em .sops.yaml sob 'creation_rules[].age':"
echo "        # $HOSTNAME_TAG"
echo "        - $PUBKEY"
echo
echo "  2. Reencripte os secrets com o novo recipient:"
echo "        cd infra-lab && sops updatekeys secrets/*.enc.yaml"
echo
echo "  3. git commit + push"
echo
echo "  DEPOIS neste host:"
echo "     git pull && ./scripts/secrets-refresh.sh"
echo "=========================================================================="
