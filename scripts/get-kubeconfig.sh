#!/usr/bin/env bash
# =============================================================================
# get-kubeconfig.sh — Copia o kubeconfig do K3s server para a máquina local
#
# Uso:
#   chmod +x scripts/get-kubeconfig.sh
#   ./scripts/get-kubeconfig.sh
#   ./scripts/get-kubeconfig.sh --output ~/.kube/meu-lab.yaml
#
# O que faz:
#   1. Conecta via SSH no k3s-server (192.168.1.20)
#   2. Lê /etc/rancher/k3s/k3s.yaml
#   3. Substitui 127.0.0.1/localhost pelo IP real do servidor
#   4. Salva em ~/.kube/infra-lab.yaml (ou caminho customizado)
#   5. Exibe instrução para exportar KUBECONFIG
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
K3S_SERVER_IP="192.168.1.20"
K3S_SERVER_USER="labadmin"
SSH_KEY="${HOME}/.ssh/lab_id_rsa"
REMOTE_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
LOCAL_KUBECONFIG="${HOME}/.kube/infra-lab.yaml"

# ---------------------------------------------------------------------------
# Processar argumentos
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o)
            LOCAL_KUBECONFIG="$2"
            shift 2
            ;;
        --server|-s)
            K3S_SERVER_IP="$2"
            shift 2
            ;;
        --key|-k)
            SSH_KEY="$2"
            shift 2
            ;;
        --help|-h)
            echo "Uso: $0 [--output CAMINHO] [--server IP] [--key CHAVE_SSH]"
            echo ""
            echo "  --output, -o  Caminho local para salvar o kubeconfig (padrão: ~/.kube/infra-lab.yaml)"
            echo "  --server, -s  IP do K3s server (padrão: 192.168.1.20)"
            echo "  --key, -k     Caminho da chave SSH (padrão: ~/.ssh/lab_id_rsa)"
            exit 0
            ;;
        *)
            echo "Argumento desconhecido: $1. Use --help para ajuda." >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Verificações
# ---------------------------------------------------------------------------

echo "[INFO] Verificando pré-requisitos..."

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "[ERRO] Chave SSH não encontrada: ${SSH_KEY}" >&2
    exit 1
fi

# Verificar conectividade SSH
echo "[INFO] Testando conectividade SSH com ${K3S_SERVER_USER}@${K3S_SERVER_IP}..."
if ! ssh -i "${SSH_KEY}" \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    "${K3S_SERVER_USER}@${K3S_SERVER_IP}" \
    "echo ok" &>/dev/null; then
    echo "[ERRO] Não foi possível conectar ao K3s server (${K3S_SERVER_IP})." >&2
    echo "       Verifique: IP correto, SSH ativo, chave SSH autorizada." >&2
    exit 1
fi
echo "[OK]   Conexão SSH estabelecida"

# ---------------------------------------------------------------------------
# Criar diretório .kube se necessário
# ---------------------------------------------------------------------------

LOCAL_KUBECONFIG_DIR="$(dirname "${LOCAL_KUBECONFIG}")"
if [[ ! -d "${LOCAL_KUBECONFIG_DIR}" ]]; then
    echo "[INFO] Criando diretório ${LOCAL_KUBECONFIG_DIR}..."
    mkdir -p "${LOCAL_KUBECONFIG_DIR}"
    chmod 0700 "${LOCAL_KUBECONFIG_DIR}"
fi

# ---------------------------------------------------------------------------
# Fazer backup do kubeconfig atual (se existir)
# ---------------------------------------------------------------------------

if [[ -f "${LOCAL_KUBECONFIG}" ]]; then
    BACKUP="${LOCAL_KUBECONFIG}.backup.$(date '+%Y%m%d_%H%M%S')"
    echo "[INFO] Backup do kubeconfig atual: ${BACKUP}"
    cp "${LOCAL_KUBECONFIG}" "${BACKUP}"
fi

# ---------------------------------------------------------------------------
# Copiar e adaptar kubeconfig
# ---------------------------------------------------------------------------

echo "[INFO] Copiando kubeconfig de ${K3S_SERVER_IP}:${REMOTE_KUBECONFIG}..."

# Copia o kubeconfig e substitui o endereço loopback pelo IP real do servidor
ssh -i "${SSH_KEY}" \
    -o StrictHostKeyChecking=no \
    "${K3S_SERVER_USER}@${K3S_SERVER_IP}" \
    "sudo cat ${REMOTE_KUBECONFIG}" \
| sed "s|127\.0\.0\.1|${K3S_SERVER_IP}|g" \
| sed "s|localhost|${K3S_SERVER_IP}|g" \
> "${LOCAL_KUBECONFIG}"

# Proteger o arquivo (kubeconfig é sensível)
chmod 0600 "${LOCAL_KUBECONFIG}"

echo "[OK]   Kubeconfig salvo em: ${LOCAL_KUBECONFIG}"

# ---------------------------------------------------------------------------
# Verificar kubeconfig
# ---------------------------------------------------------------------------

echo "[INFO] Verificando acesso ao cluster..."
if kubectl --kubeconfig "${LOCAL_KUBECONFIG}" get nodes &>/dev/null; then
    echo "[OK]   Acesso ao cluster K3s confirmado"
    echo ""
    kubectl --kubeconfig "${LOCAL_KUBECONFIG}" get nodes -o wide
else
    echo "[WARN] Não foi possível verificar acesso ao cluster." >&2
    echo "       Verifique se o K3s está rodando: ssh labadmin@${K3S_SERVER_IP} 'sudo k3s kubectl get nodes'" >&2
fi

# ---------------------------------------------------------------------------
# Instruções finais
# ---------------------------------------------------------------------------

echo ""
echo "================================================"
echo " Kubeconfig pronto para uso!"
echo "================================================"
echo ""
echo " Para usar permanentemente, adicione ao ~/.bashrc ou ~/.zshrc:"
echo "   export KUBECONFIG=${LOCAL_KUBECONFIG}"
echo ""
echo " Ou use uma sessão apenas:"
echo "   export KUBECONFIG=${LOCAL_KUBECONFIG}"
echo "   kubectl get nodes -o wide"
echo ""
