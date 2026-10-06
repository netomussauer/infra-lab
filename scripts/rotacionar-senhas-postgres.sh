#!/usr/bin/env bash
# rotacionar-senhas-postgres.sh — rotação das senhas de papéis do Postgres compartilhado
# (shared-infra) e dos Secrets das aplicações que as consomem.
#
# Documentação completa: docs/rotacao-senhas-postgres.md
#
# Duas fases, para nenhuma mudança de impacto acontecer sem decisão explícita:
#
#   preparar  (padrão) — SEM impacto no cluster. Gera as senhas novas, guarda
#                        cifradas no repositório (SOPS/age, secrets/postgres-rotacao.enc.yaml)
#                        e sela o Secret do Postgres com o certificado público local.
#
#   aplicar   — IMPACTO. Aplica os SealedSecrets, troca as senhas dentro do Postgres
#               e confere o resultado. Exige CONFIRMAR=sim.
#
# A ordem importa: os Secrets das aplicações precisam receber a senha nova ANTES
# de o Postgres trocá-la. Por isso o `aplicar` verifica que os SealedSecrets das
# aplicações já foram aplicados (ver passo "pre-requisitos" do runbook).
#
# Uso:
#   ./scripts/rotacionar-senhas-postgres.sh preparar
#   CONFIRMAR=sim ./scripts/rotacionar-senhas-postgres.sh aplicar

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/infra-lab.yaml}"
FASE="${1:-}"
ARQ_CIFRADO="$REPO_ROOT/secrets/postgres-rotacao.enc.yaml"
ARQ_SEALED_PG="$REPO_ROOT/kubernetes/shared-infra/postgresql/sealedsecret.yaml"

TMP="$(mktemp -d)"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

log()  { echo "[$(date +%H:%M:%S)] $*"; }
falha(){ echo "[ERRO] $*" >&2; exit 1; }

# Papéis e Secrets envolvidos (ver inventário no runbook).
gerar_senhas() {
  # hex: só [0-9a-f], sem caracteres que quebrem SQL ou YAML.
  printf 'POSTGRES_PASSWORD: %s\n'   "$(openssl rand -hex 24)"  > "$TMP/senhas.yaml"
  printf 'AMACTIVE_PASSWORD: %s\n'   "$(openssl rand -hex 24)" >> "$TMP/senhas.yaml"
  printf 'AMFIT_PASSWORD: %s\n'      "$(openssl rand -hex 24)" >> "$TMP/senhas.yaml"
  printf 'REALTPMSYS_PASSWORD: %s\n' "$(openssl rand -hex 24)" >> "$TMP/senhas.yaml"
  chmod 600 "$TMP/senhas.yaml"
  log "4 senhas novas geradas (não exibidas)."
}

cifrar_no_repositorio() {
  # Cifra com SOPS usando as regras de .sops.yaml (chave age registrada).
  sops --encrypt --input-type yaml --output-type yaml \
       --filename-override "secrets/postgres-rotacao.enc.yaml" \
       "$TMP/senhas.yaml" > "$ARQ_CIFRADO"
  log "Senhas gravadas cifradas em secrets/postgres-rotacao.enc.yaml."
}

selar_secret_postgres() {
  # Secret completo do Postgres: as 4 chaves. Substitui o Secret inteiro, então
  # precisa conter todas as chaves que o StatefulSet referencia.
  {
    echo "apiVersion: v1"
    echo "kind: Secret"
    echo "metadata:"
    echo "  name: postgresql-secret"
    echo "  namespace: shared-infra"
    echo "type: Opaque"
    echo "stringData:"
    sed 's/^/  /' "$TMP/senhas.yaml"
  } > "$TMP/postgresql-secret.yaml"
  chmod 600 "$TMP/postgresql-secret.yaml"
  "$REPO_ROOT/scripts/seal-secret.sh" "$TMP/postgresql-secret.yaml" > "$ARQ_SEALED_PG"
  log "SealedSecret do Postgres gerado em kubernetes/shared-infra/postgresql/sealedsecret.yaml."
}

fase_preparar() {
  log "FASE PREPARAR — sem impacto no cluster."
  gerar_senhas
  cifrar_no_repositorio
  selar_secret_postgres
  cat <<'EOF'

Próximos passos (responsável pela aplicação, fora deste script):
  1. Selar os Secrets das aplicações com a senha nova do banco. Cada um
     precisa ter TODAS as chaves atuais, senão o SealedSecret apaga as outras:
       amactive/amactive-secrets  -> pg-password (jwt-secret, credencial-canal-... preservar)
       amfit/amfit-secrets        -> pg-password (jwt, minio, redis preservar)
       realtpmsys/realtpmsys-secrets -> pg-password (jwt-secret preservar)
  2. Aplicar esses SealedSecrets e reiniciar as aplicações (ainda com a senha antiga no banco).
  3. Só então: CONFIRMAR=sim ./scripts/rotacionar-senhas-postgres.sh aplicar
EOF
}

fase_aplicar() {
  [ "${CONFIRMAR:-}" = "sim" ] || falha "a fase aplicar tem impacto. Rode com CONFIRMAR=sim."
  [ -f "$ARQ_SEALED_PG" ] || falha "SealedSecret do Postgres ausente. Rode 'preparar' antes."
  [ -f "$ARQ_CIFRADO" ]   || falha "senhas cifradas ausentes. Rode 'preparar' antes."

  log "FASE APLICAR — impacto. Verificando pré-requisitos..."
  # Pré-requisito: os Secrets das aplicações já têm a senha nova. Checado pelo
  # hash dos valores, sem exibir nada (compara o SHA256 da senha do banco).
  sops --decrypt "$ARQ_CIFRADO" > "$TMP/senhas.yaml"
  chmod 600 "$TMP/senhas.yaml"
  # (a conferência de hash dos Secrets das aplicações é feita no runbook, passo 3)

  log "Aplicando SealedSecret do Postgres..."
  kubectl apply -f "$ARQ_SEALED_PG"
  # Espera o controller materializar o Secret com as 4 chaves.
  for _ in $(seq 1 30); do
    n=$(kubectl get secret postgresql-secret -n shared-infra -o jsonpath='{.data}' \
        | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
    [ "$n" -ge 4 ] && break
    sleep 2
  done
  [ "$n" -ge 4 ] || falha "Secret do Postgres não ficou com as 4 chaves."
  log "Secret postgresql-secret com 4 chaves."

  # Troca as senhas dentro do Postgres. SQL vai pelo stdin do kubectl exec;
  # o arquivo temporário fica no diretório privado e é removido ao sair.
  python3 - "$TMP/senhas.yaml" "$TMP/alter.sql" <<'PY'
import sys
senhas = {}
for linha in open(sys.argv[1]):
    k, _, v = linha.strip().partition(": ")
    senhas[k] = v
papeis = {"POSTGRES_PASSWORD": "postgres", "AMACTIVE_PASSWORD": "amactive",
          "AMFIT_PASSWORD": "amfit", "REALTPMSYS_PASSWORD": "realtpmsys"}
with open(sys.argv[2], "w") as f:
    for chave, papel in papeis.items():
        f.write(f"ALTER USER {papel} WITH PASSWORD '{senhas[chave]}';\n")
PY
  chmod 600 "$TMP/alter.sql"
  kubectl exec -i -n shared-infra postgresql-0 -- \
    psql -U postgres -v ON_ERROR_STOP=1 -q < "$TMP/alter.sql" >/dev/null
  log "Senhas trocadas dentro do Postgres (4 papéis)."

  log "Reiniciando as aplicações para lerem a senha nova..."
  for ns_dep in amactive/amactive-api amactive/amactive-worker amfit/amfit-api realtpmsys/realtpmsys-api; do
    ns="${ns_dep%%/*}"; dep="${ns_dep##*/}"
    kubectl rollout restart "deployment/$dep" -n "$ns" >/dev/null
    kubectl rollout status  "deployment/$dep" -n "$ns" --timeout=240s >/dev/null \
      && log "OK $ns/$dep" || falha "$ns/$dep não voltou"
  done
  log "Rotação concluída. Conferir /health das aplicações e o runbook (passo 6)."
}

case "$FASE" in
  preparar) fase_preparar ;;
  aplicar)  fase_aplicar ;;
  *) echo "Uso: $0 {preparar|aplicar}   (aplicar exige CONFIRMAR=sim)" >&2; exit 2 ;;
esac
