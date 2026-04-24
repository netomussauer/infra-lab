#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Orquestrador completo do laboratório home-lab K3s
#
# Executa em sequência:
#   1. Terraform apply — cria as VMs no Proxmox
#   2. Aguarda inicialização das VMs
#   3. Ansible 01 — configuração base de todos os nós
#   4. Ansible 02 — montagens NFS
#   5. Ansible 03 — instalação do K3s control-plane
#   6. Ansible 04 — instalação dos K3s workers
#   7. Ansible 05 — configuração pós-instalação (labels, taints)
#
# Pré-requisitos:
#   - terraform >= 1.6.0 instalado e no PATH
#   - ansible >= 2.14 instalado
#   - ansible-lint instalado (validação antes de executar)
#   - terraform/proxmox/terraform.tfvars preenchido (copie de .example)
#   - Chave SSH ~/.ssh/lab_id_rsa gerada e a pública no tfvars
#
# Uso:
#   chmod +x scripts/bootstrap.sh
#   ./scripts/bootstrap.sh [--skip-terraform] [--skip-vm-wait]
#
# Flags:
#   --skip-terraform  Pula o apply do Terraform (útil se VMs já existem)
#   --skip-vm-wait    Pula a espera de 60s após criação das VMs
#   --dry-run         Executa terraform plan + ansible --check sem aplicar
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Cores para output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sem cor

# ---------------------------------------------------------------------------
# Funções utilitárias
# ---------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC}   $(date '+%H:%M:%S') $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $*"
}

log_error() {
    echo -e "${RED}[ERRO]${NC} $(date '+%H:%M:%S') $*" >&2
}

log_step() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN} $* ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

die() {
    log_error "$*"
    exit 1
}

# ---------------------------------------------------------------------------
# Variáveis de configuração
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/proxmox"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
INVENTORY="${ANSIBLE_DIR}/inventory/hosts.yml"
VM_BOOT_WAIT=60  # Segundos para aguardar inicialização das VMs

# Flags de controle
SKIP_TERRAFORM=false
SKIP_VM_WAIT=false
DRY_RUN=false

# ---------------------------------------------------------------------------
# Processar argumentos
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case $arg in
        --skip-terraform) SKIP_TERRAFORM=true ;;
        --skip-vm-wait)   SKIP_VM_WAIT=true ;;
        --dry-run)        DRY_RUN=true ;;
        --help|-h)
            echo "Uso: $0 [--skip-terraform] [--skip-vm-wait] [--dry-run]"
            exit 0
            ;;
        *)
            die "Argumento desconhecido: $arg. Use --help para ajuda."
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Verificar pré-requisitos
# ---------------------------------------------------------------------------

log_step "Verificando pré-requisitos"

check_command() {
    local cmd="$1"
    local min_version="${2:-}"
    if ! command -v "${cmd}" &> /dev/null; then
        die "Comando '${cmd}' não encontrado. Instale antes de continuar."
    fi
    log_ok "${cmd} encontrado: $(${cmd} --version 2>&1 | head -1)"
}

check_command terraform
check_command ansible
check_command ansible-playbook
check_command ansible-lint

# Verificar que terraform.tfvars existe
if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
    die "Arquivo ${TERRAFORM_DIR}/terraform.tfvars não encontrado.
         Copie o exemplo: cp ${TERRAFORM_DIR}/terraform.tfvars.example ${TERRAFORM_DIR}/terraform.tfvars
         Depois preencha com seus valores reais."
fi

# Verificar que a chave SSH existe
if [[ ! -f "${HOME}/.ssh/lab_id_rsa" ]]; then
    log_warn "Chave SSH ~/.ssh/lab_id_rsa não encontrada."
    log_warn "Gere com: ssh-keygen -t ed25519 -C 'lab-key' -f ~/.ssh/lab_id_rsa"
    die "Chave SSH obrigatória."
fi

log_ok "Todos os pré-requisitos verificados"

# ---------------------------------------------------------------------------
# Etapa 1: Terraform
# ---------------------------------------------------------------------------

if [[ "${SKIP_TERRAFORM}" == "false" ]]; then
    log_step "Etapa 1/7: Terraform — Provisionando VMs no Proxmox"

    cd "${TERRAFORM_DIR}"

    log_info "Verificando formatação Terraform..."
    terraform fmt -recursive -check || {
        log_warn "Formatação incorreta. Corrigindo automaticamente..."
        terraform fmt -recursive
    }

    log_info "Inicializando Terraform..."
    terraform init

    log_info "Validando configuração Terraform..."
    terraform validate

    log_info "Gerando plano de execução..."
    terraform plan -out=tfplan.binary

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "Modo dry-run: terraform apply pulado."
    else
        log_info "Aplicando plano Terraform (criando VMs)..."
        terraform apply tfplan.binary
        log_ok "VMs criadas no Proxmox com sucesso"
    fi

    cd "${PROJECT_ROOT}"
else
    log_warn "Etapa 1/7: Terraform pulado (--skip-terraform)"
fi

# ---------------------------------------------------------------------------
# Etapa 2: Aguardar inicialização das VMs
# ---------------------------------------------------------------------------

if [[ "${SKIP_VM_WAIT}" == "false" && "${DRY_RUN}" == "false" && "${SKIP_TERRAFORM}" == "false" ]]; then
    log_step "Etapa 2/7: Aguardando ${VM_BOOT_WAIT}s para VMs inicializarem"
    log_info "VMs recém-criadas precisam de tempo para: boot, cloud-init, SSH ready..."
    for i in $(seq "${VM_BOOT_WAIT}" -10 1); do
        printf "\r${YELLOW}  Aguardando... %ds restantes${NC}  " "${i}"
        sleep 10
    done
    echo ""
    log_ok "Aguardar concluído — VMs devem estar prontas"
else
    log_warn "Etapa 2/7: Espera de boot pulada"
fi

# ---------------------------------------------------------------------------
# Função de execução de playbook com validação prévia
# ---------------------------------------------------------------------------

run_playbook() {
    local playbook="$1"
    local description="$2"

    log_info "Validando sintaxe: ${playbook}"
    ansible-playbook \
        -i "${INVENTORY}" \
        "${ANSIBLE_DIR}/playbooks/${playbook}" \
        --syntax-check \
        || die "Erro de sintaxe em ${playbook}. Corrija antes de continuar."

    log_info "Executando lint: ${playbook}"
    ansible-lint \
        --profile production \
        "${ANSIBLE_DIR}/playbooks/${playbook}" \
        || log_warn "ansible-lint reportou avisos em ${playbook}. Verifique antes de produção."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Modo dry-run — executando ${playbook} com --check --diff..."
        ansible-playbook \
            -i "${INVENTORY}" \
            "${ANSIBLE_DIR}/playbooks/${playbook}" \
            --check --diff \
            --private-key "${HOME}/.ssh/lab_id_rsa"
    else
        log_info "Executando ${playbook}..."
        ansible-playbook \
            -i "${INVENTORY}" \
            "${ANSIBLE_DIR}/playbooks/${playbook}" \
            --private-key "${HOME}/.ssh/lab_id_rsa"
        log_ok "${description} concluído"
    fi
}

# ---------------------------------------------------------------------------
# Etapa 3: Configuração base
# ---------------------------------------------------------------------------

log_step "Etapa 3/7: Configuração base dos nós"
run_playbook "01-base-setup.yml" "Configuração base"

# ---------------------------------------------------------------------------
# Etapa 4: Montagens NFS
# ---------------------------------------------------------------------------

log_step "Etapa 4/7: Configurando montagens NFS"
run_playbook "02-nfs-mounts.yml" "Montagens NFS"

# ---------------------------------------------------------------------------
# Etapa 5: K3s control-plane
# ---------------------------------------------------------------------------

log_step "Etapa 5/7: Instalando K3s control-plane"
run_playbook "03-k3s-server.yml" "K3s server"

# ---------------------------------------------------------------------------
# Etapa 6: K3s workers
# ---------------------------------------------------------------------------

log_step "Etapa 6/7: Instalando K3s workers"
run_playbook "04-k3s-agents.yml" "K3s agents"

# ---------------------------------------------------------------------------
# Etapa 7: Pós-instalação
# ---------------------------------------------------------------------------

log_step "Etapa 7/7: Configuração pós-instalação (labels, taints)"
run_playbook "05-post-setup.yml" "Pós-instalação"

# ---------------------------------------------------------------------------
# Finalização
# ---------------------------------------------------------------------------

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Cluster K3s do home-lab provisionado com sucesso!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  Para usar o cluster:"
echo -e "    ${CYAN}export KUBECONFIG=~/.kube/infra-lab.yaml${NC}"
echo -e "    ${CYAN}kubectl get nodes -o wide${NC}"
echo ""
echo -e "  Nós do cluster:"
echo -e "    k3s-server      (192.168.1.20) — control-plane"
echo -e "    k3s-worker-cicd (192.168.1.21) — worker cicd"
echo -e "    ci-runner       (192.168.1.22) — worker runner"
echo -e "    notebook-i5     (192.168.1.11) — worker monitoring (bare metal)"
echo -e "    raspberry-pi    (192.168.1.12) — worker edge (bare metal, arm)"
echo ""
echo -e "  Kubeconfig: ${CYAN}~/.kube/infra-lab.yaml${NC}"
echo ""
