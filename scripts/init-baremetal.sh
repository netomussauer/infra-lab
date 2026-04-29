#!/usr/bin/env bash
# =============================================================================
# init-baremetal.sh — Provisionamento inicial dos nós bare-metal
#
# Realiza o bootstrap de autenticação em nós que ainda não têm o usuário
# labadmin configurado. Deve ser executado UMA VEZ por nó, antes de rodar
# os playbooks 01–05 do bootstrap principal.
#
# O que faz:
#   1. Verifica conectividade SSH com o usuário inicial do nó
#   2. Copia a chave lab_id_rsa para o authorized_keys do usuário inicial
#   3. Executa 00-baremetal-init.yml para criar labadmin + sudo + SSH hardening
#   4. Verifica que labadmin está acessível com a chave do laboratório
#
# Uso:
#   ./scripts/init-baremetal.sh [--host <ip_ou_nome>] [--user <usuario>] [--port <porta>]
#
# Exemplos:
#   ./scripts/init-baremetal.sh --host 192.168.1.110 --user pi
#   ./scripts/init-baremetal.sh --host 192.168.1.65  --user ubuntu
#   ./scripts/init-baremetal.sh  # sem flags: guia interativo
#
# Pré-requisitos:
#   - ssh-keygen disponível (para gerar lab_id_rsa se não existir)
#   - sshpass instalado (para copiar a chave com senha) OU acesso com chave
#   - ansible disponível
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Cores
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERRO]${NC} $*" >&2; }
log_step()  { echo -e "\n${CYAN}========================================${NC}\n${CYAN} $* ${NC}\n${CYAN}========================================${NC}\n"; }
die()       { log_error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Caminhos
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
INVENTORY="${ANSIBLE_DIR}/inventory/hosts.yml"
LAB_KEY="${HOME}/.ssh/lab_id_rsa"
LAB_KEY_PUB="${HOME}/.ssh/lab_id_rsa.pub"

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
HOST=""
INIT_USER=""
SSH_PORT=22

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host|-H)    HOST="$2";      shift 2 ;;
        --user|-u)    INIT_USER="$2"; shift 2 ;;
        --port|-p)    SSH_PORT="$2";  shift 2 ;;
        --help|-h)
            echo "Uso: $0 [--host <ip>] [--user <usuario>] [--port <porta>]"
            echo "  Sem argumentos: modo guiado interativo."
            exit 0
            ;;
        *) die "Argumento desconhecido: $1. Use --help." ;;
    esac
done

# ---------------------------------------------------------------------------
# Verificar dependências
# ---------------------------------------------------------------------------
log_step "Verificando dependências"

if ! command -v ssh &>/dev/null; then
    die "ssh não encontrado."
fi

if ! command -v ssh-copy-id &>/dev/null; then
    die "ssh-copy-id não encontrado."
fi

HAVE_SSHPASS=false
if command -v sshpass &>/dev/null; then
    HAVE_SSHPASS=true
    log_ok "sshpass disponível — autenticação com senha possível"
else
    log_warn "sshpass não disponível — será necessário digitar a senha interativamente"
    log_warn "Instale com: sudo apt-get install sshpass  (ou brew install hudochenkov/sshpass/sshpass)"
fi

if ! command -v ansible-playbook &>/dev/null; then
    die "ansible-playbook não encontrado. Adicione ~/.local/bin ao PATH."
fi

# ---------------------------------------------------------------------------
# Verificar/gerar chave do laboratório
# ---------------------------------------------------------------------------
log_step "Verificando chave SSH do laboratório"

if [[ ! -f "${LAB_KEY}" ]]; then
    log_warn "Chave ${LAB_KEY} não encontrada. Gerando nova chave..."
    ssh-keygen -t ed25519 -C "lab-key" -f "${LAB_KEY}" -N ""
    log_ok "Chave gerada: ${LAB_KEY}"
else
    log_ok "Chave existente: ${LAB_KEY}"
fi

# ---------------------------------------------------------------------------
# Modo interativo se nenhum argumento fornecido
# ---------------------------------------------------------------------------
if [[ -z "${HOST}" ]]; then
    echo ""
    echo "Nós bare-metal do laboratório:"
    echo "  1) notebook-i5   — 192.168.1.65   (Ubuntu 22.04 — monitoring)"
    echo "  2) raspberry-pi  — 192.168.1.110  (Raspbian 12 — edge ARM)"
    echo "  3) Outro host"
    echo ""
    read -rp "Escolha o nó [1/2/3]: " NODE_CHOICE

    case "${NODE_CHOICE}" in
        1)
            HOST="192.168.1.65"
            INIT_USER="${INIT_USER:-ubuntu}"
            log_info "notebook-i5 selecionado"
            ;;
        2)
            HOST="192.168.1.110"
            INIT_USER="${INIT_USER:-pi}"
            log_info "raspberry-pi selecionado"
            ;;
        3)
            read -rp "IP ou hostname: " HOST
            read -rp "Usuário inicial (ex: ubuntu, pi, root): " INIT_USER
            ;;
        *) die "Opção inválida." ;;
    esac
fi

if [[ -z "${INIT_USER}" ]]; then
    read -rp "Usuário inicial do nó ${HOST} (ex: ubuntu, pi): " INIT_USER
fi

# ---------------------------------------------------------------------------
# Verificar conectividade
# ---------------------------------------------------------------------------
log_step "Verificando conectividade com ${INIT_USER}@${HOST}:${SSH_PORT}"

if ! ping -c 1 -W 3 "${HOST}" &>/dev/null; then
    die "Host ${HOST} não responde a ping. Verifique a rede."
fi
log_ok "Ping OK"

if ! nc -z -w 5 "${HOST}" "${SSH_PORT}" &>/dev/null; then
    echo ""
    log_error "SSH não acessível em ${HOST}:${SSH_PORT}"
    echo ""
    echo -e "${YELLOW}Para habilitar SSH no host (execute localmente na máquina):${NC}"
    echo "  # Ubuntu/Debian:"
    echo "  sudo apt-get install -y openssh-server"
    echo "  sudo systemctl enable --now ssh"
    echo ""
    echo "  # Raspberry Pi OS:"
    echo "  sudo systemctl enable --now ssh"
    echo "  # Ou: sudo raspi-config → Interface Options → SSH → Enable"
    echo ""
    die "Habilite o SSH no host e execute este script novamente."
fi
log_ok "Porta ${SSH_PORT} acessível"

# ---------------------------------------------------------------------------
# Testar se a chave lab_id_rsa já funciona para o usuário inicial
# ---------------------------------------------------------------------------
KEY_WORKS=false
if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       -i "${LAB_KEY}" -p "${SSH_PORT}" \
       "${INIT_USER}@${HOST}" 'echo ok' &>/dev/null; then
    KEY_WORKS=true
    log_ok "Chave lab_id_rsa já autorizada para ${INIT_USER}@${HOST}"
fi

# ---------------------------------------------------------------------------
# Instalar a chave no usuário inicial (se necessário)
# ---------------------------------------------------------------------------
if [[ "${KEY_WORKS}" == "false" ]]; then
    log_step "Instalando chave SSH no ${INIT_USER}@${HOST}"
    echo ""
    echo -e "${YELLOW}A chave lab_id_rsa precisa ser copiada para ${INIT_USER}@${HOST}.${NC}"
    echo "Você precisará digitar a senha do usuário ${INIT_USER}."
    echo ""

    if [[ "${HAVE_SSHPASS}" == "true" ]]; then
        read -rsp "Senha do ${INIT_USER}@${HOST}: " INIT_PASS
        echo ""
        sshpass -p "${INIT_PASS}" ssh-copy-id \
            -i "${LAB_KEY_PUB}" \
            -o StrictHostKeyChecking=no \
            -p "${SSH_PORT}" \
            "${INIT_USER}@${HOST}" \
            || die "Falha ao instalar a chave. Verifique a senha."
    else
        # Sem sshpass: interativo
        ssh-copy-id \
            -i "${LAB_KEY_PUB}" \
            -o StrictHostKeyChecking=no \
            -p "${SSH_PORT}" \
            "${INIT_USER}@${HOST}" \
            || die "Falha ao instalar a chave."
    fi

    log_ok "Chave instalada em ${INIT_USER}@${HOST}"
fi

# ---------------------------------------------------------------------------
# Verificar acesso com a chave antes de prosseguir
# ---------------------------------------------------------------------------
if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
         -i "${LAB_KEY}" -p "${SSH_PORT}" \
         "${INIT_USER}@${HOST}" 'echo ok' &>/dev/null; then
    die "Acesso SSH com lab_id_rsa falhou após instalação. Verifique manualmente."
fi
log_ok "Acesso SSH com lab_id_rsa confirmado"

# ---------------------------------------------------------------------------
# Executar playbook de inicialização
# ---------------------------------------------------------------------------
log_step "Executando provisionamento Ansible em ${HOST}"

# Localizar o host no inventário pelo IP
INVENTORY_HOST=$(grep -B5 "ansible_host: ${HOST}" "${INVENTORY}" | grep -E '^\s+\w' | head -1 | tr -d ' :' || true)
if [[ -z "${INVENTORY_HOST}" ]]; then
    log_warn "Host ${HOST} não encontrado no inventário. Usando o IP diretamente."
    INVENTORY_TARGET="${HOST},"
    EXTRA_INVENTORY="-i ${INVENTORY_TARGET}"
else
    log_info "Host encontrado no inventário: ${INVENTORY_HOST}"
    EXTRA_INVENTORY="-i ${INVENTORY}"
fi

# Verificar se o usuário tem sudo sem senha no host alvo.
# Se precisar de senha (sudo -n falha), adiciona -K para o Ansible pedir interativamente.
log_info "Verificando se ${INIT_USER} tem sudo sem senha..."
BECOME_FLAG=""
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
         -i "${LAB_KEY}" -p "${SSH_PORT}" \
         "${INIT_USER}@${HOST}" 'sudo -n true' &>/dev/null; then
    log_warn "sudo requer senha para ${INIT_USER} — será solicitada pelo Ansible."
    BECOME_FLAG="-K"
fi

# shellcheck disable=SC2086
ansible-playbook \
    ${EXTRA_INVENTORY} \
    "${ANSIBLE_DIR}/playbooks/00-baremetal-init.yml" \
    --limit "${INVENTORY_HOST:-${HOST}}" \
    -u "${INIT_USER}" \
    --private-key "${LAB_KEY}" \
    -e "baremetal_init_user=${INIT_USER}" \
    ${BECOME_FLAG} \
    || die "Playbook 00-baremetal-init.yml falhou."

# ---------------------------------------------------------------------------
# Verificação final
# ---------------------------------------------------------------------------
log_step "Verificação final"

if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       -i "${LAB_KEY}" -p "${SSH_PORT}" \
       "labadmin@${HOST}" 'echo ok' &>/dev/null; then
    log_ok "labadmin@${HOST} acessível com lab_id_rsa"
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Nó ${HOST} provisionado com sucesso!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo "  Próximos passos:"
    echo "  1. Execute o bootstrap completo no nó:"
    echo -e "     ${CYAN}./scripts/bootstrap.sh --skip-terraform --skip-vm-wait${NC}"
    echo ""
    echo "  Ou execute apenas os playbooks necessários:"
    echo -e "     ${CYAN}ansible-playbook -i ansible/inventory/hosts.yml \\${NC}"
    echo -e "     ${CYAN}  ansible/playbooks/01-base-setup.yml --limit ${INVENTORY_HOST:-${HOST}}${NC}"
else
    die "labadmin@${HOST} NÃO acessível após provisionamento. Verifique o output acima."
fi
