#!/usr/bin/env bash
# seal-secret.sh — wrapper de `kubeseal` para projetos do lab.
#
# Padroniza a geração de SealedSecret a partir de um Secret K8s qualquer.
# Usa o cert público local (kubernetes/sealed-secrets/pub-cert.pem) por padrão
# para encryption offline — não exige acesso ao cluster.
#
# Escopo default: strict (NAME e NAMESPACE precisam bater no apply). Mais
# seguro. Para escopos diferentes, usar SCOPE=namespace-wide / cluster-wide.
#
# Uso:
#   # 1. Gerar um Secret normal localmente (não comitar este):
#   kubectl create secret generic foo \
#     --from-literal=API_KEY=s3cret123 \
#     --namespace=meu-app \
#     --dry-run=client -o yaml > /tmp/secret.yaml
#
#   # 2. Encriptar — saída é o SealedSecret (este sim, comita no Git):
#   ./scripts/seal-secret.sh /tmp/secret.yaml > sealed-foo.yaml
#
#   # 3. Apply (ou commit pro ArgoCD pegar):
#   kubectl apply -f sealed-foo.yaml
#
# Variáveis opcionais:
#   PUB_CERT     — caminho do cert público (default: kubernetes/sealed-secrets/pub-cert.pem)
#   SCOPE        — strict (default) | namespace-wide | cluster-wide
#   FETCH_CERT   — true para buscar cert do cluster em runtime em vez do arquivo local
#                  (requer kubectl configurado para o cluster)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUB_CERT="${PUB_CERT:-${REPO_ROOT}/kubernetes/sealed-secrets/pub-cert.pem}"
SCOPE="${SCOPE:-strict}"
FETCH_CERT="${FETCH_CERT:-false}"

if [ $# -lt 1 ]; then
    echo "Uso: $0 <secret.yaml>" >&2
    echo "Lê o Secret e emite o SealedSecret correspondente no stdout." >&2
    exit 1
fi

SECRET_FILE="$1"

if [ ! -f "$SECRET_FILE" ]; then
    echo "Erro: arquivo $SECRET_FILE não encontrado" >&2
    exit 1
fi

# Validar escopo
case "$SCOPE" in
    strict|namespace-wide|cluster-wide)
        ;;
    *)
        echo "Erro: SCOPE inválido '$SCOPE'. Use: strict | namespace-wide | cluster-wide" >&2
        exit 1
        ;;
esac

# Decidir entre cert offline (arquivo) e cert do cluster
if [ "$FETCH_CERT" = "true" ]; then
    KUBESEAL_ARGS=(--scope "$SCOPE" --format yaml)
else
    if [ ! -f "$PUB_CERT" ]; then
        echo "Erro: cert público não encontrado em $PUB_CERT" >&2
        echo "Sugestões:" >&2
        echo "  - rodar com FETCH_CERT=true (busca do cluster)" >&2
        echo "  - definir PUB_CERT=/caminho/para/cert.pem" >&2
        exit 1
    fi
    KUBESEAL_ARGS=(--cert "$PUB_CERT" --scope "$SCOPE" --format yaml)
fi

kubeseal "${KUBESEAL_ARGS[@]}" < "$SECRET_FILE"
