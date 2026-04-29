#!/bin/bash
# =============================================================================
# scripts/k8s-bootstrap.sh
# Bootstrap completo do cluster K3s — Laboratório home-lab
#
# Uso:
#   chmod +x scripts/k8s-bootstrap.sh
#   ./scripts/k8s-bootstrap.sh
#
# Pré-requisitos no host de execução:
#   - kubectl instalado e configurado
#   - helm v3 instalado
#   - Acesso de rede ao cluster K3s (192.168.1.30)
#   - KUBECONFIG apontando para o cluster certo
#
# Nodes do cluster:
#   k3s-server       192.168.1.30  control-plane (NoSchedule)
#   k3s-worker-cicd  192.168.1.31  workload=cicd       (6GB RAM)
#   ci-runner        192.168.1.32  workload=runner     (4GB RAM)
#   notebook-i5      192.168.1.65  workload=monitoring (8GB RAM)
#   raspberry-pi     192.168.1.110  workload=edge, arch=arm (1GB RAM)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Variáveis de configuração
# -----------------------------------------------------------------------------
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/infra-lab.yaml}"
export KUBECONFIG

# Diretório raiz do projeto (relativo ao script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Versões
METALLB_VERSION="v0.14.3"
TEKTON_PIPELINE_VERSION="latest"
TEKTON_TRIGGERS_VERSION="latest"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Funções auxiliares
# -----------------------------------------------------------------------------
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

wait_for_rollout() {
  local resource="$1"
  local namespace="$2"
  local timeout="${3:-300s}"
  log_info "Aguardando rollout: $resource no namespace $namespace (timeout: $timeout)..."
  kubectl rollout status "$resource" -n "$namespace" --timeout="$timeout" || {
    log_warn "Timeout aguardando $resource. Verifique manualmente."
  }
}

wait_for_pods() {
  local selector="$1"
  local namespace="$2"
  local timeout="${3:-120}"
  log_info "Aguardando pods ($selector) no namespace $namespace..."
  kubectl wait pod \
    --selector="$selector" \
    --for=condition=Ready \
    --namespace="$namespace" \
    --timeout="${timeout}s" || {
    log_warn "Pods ainda não prontos. Continuando..."
  }
}

check_prerequisites() {
  log_info "Verificando pré-requisitos..."

  for cmd in kubectl helm curl; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "$cmd não encontrado. Instale antes de prosseguir."
      exit 1
    fi
  done

  # Verificar conectividade com o cluster
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Não foi possível conectar ao cluster. Verifique KUBECONFIG=$KUBECONFIG"
    exit 1
  fi

  log_ok "Pré-requisitos OK. Cluster acessível."
  kubectl get nodes -o wide
}

# -----------------------------------------------------------------------------
# Etapa 1 — Namespaces
# -----------------------------------------------------------------------------
step_namespaces() {
  log_info "=== Etapa 1: Criando namespaces ==="

  kubectl apply -f "$PROJECT_ROOT/kubernetes/bootstrap/namespaces.yaml"

  log_ok "Namespaces criados: cicd, monitoring, edge, registry"
}

# -----------------------------------------------------------------------------
# Etapa 2 — MetalLB
# -----------------------------------------------------------------------------
step_metallb() {
  log_info "=== Etapa 2: Instalando MetalLB $METALLB_VERSION ==="

  # IMPORTANTE: K3s inclui klipper-lb por padrão.
  # Se klipper-lb ainda estiver ativo, desabilitar primeiro:
  if kubectl get daemonset -n kube-system svclb-traefik &>/dev/null 2>&1; then
    log_warn "klipper-lb detectado. Para usar MetalLB, adicione '--disable servicelb' ao K3s."
    log_warn "Edite /etc/rancher/k3s/config.yaml no k3s-server e reinicie: systemctl restart k3s"
    log_warn "Continuando assim mesmo — o MetalLB pode coexistir com cuidado."
  fi

  log_info "Aplicando manifesto do MetalLB..."
  kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

  log_info "Aguardando MetalLB controller e speaker ficarem prontos..."
  kubectl wait deployment -n metallb-system controller \
    --for=condition=Available \
    --timeout=120s || log_warn "MetalLB controller ainda inicializando"

  # Aguardar CRDs estarem disponíveis antes de aplicar pools
  log_info "Aguardando CRDs do MetalLB..."
  for i in $(seq 1 12); do
    if kubectl get crd ipaddresspools.metallb.io &>/dev/null 2>&1; then
      log_ok "CRDs do MetalLB disponíveis."
      break
    fi
    log_info "Aguardando CRDs... ($i/12)"
    sleep 5
  done

  kubectl apply -f "$PROJECT_ROOT/kubernetes/bootstrap/metallb/ipaddresspool.yaml"
  log_ok "MetalLB instalado. Pool: 192.168.1.200-192.168.1.220"
}

# -----------------------------------------------------------------------------
# Etapa 3 — NFS CSI Driver + StorageClass
# -----------------------------------------------------------------------------
step_storage() {
  log_info "=== Etapa 3: Configurando storage NFS ==="

  # Verificar se NFS está acessível
  log_info "Verificando acesso ao NFS 192.168.1.112..."
  if ! kubectl run nfs-test --rm --restart=Never --image=busybox:1.35 \
    --command -- sh -c "nc -z 192.168.1.112 2049 && echo NFS_OK" \
    --timeout=30s &>/dev/null 2>&1; then
    log_warn "Não foi possível verificar NFS. Continuando assim mesmo."
  fi

  # Instalar nfs-subdir-external-provisioner via Helm
  helm repo add nfs-subdir-external-provisioner \
    https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ \
    --force-update

  helm repo update nfs-subdir-external-provisioner

  helm upgrade --install nfs-provisioner \
    nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    -f "$PROJECT_ROOT/kubernetes/bootstrap/storage/nfs-csi-values.yaml" \
    --namespace kube-system \
    --wait \
    --timeout 5m

  log_ok "Storage NFS configurado. StorageClass: nfs-storage (default)"
}

# -----------------------------------------------------------------------------
# Etapa 4 — Gitea
# -----------------------------------------------------------------------------
step_gitea() {
  log_info "=== Etapa 4: Instalando Gitea ==="

  helm repo add gitea-charts https://dl.gitea.com/charts/ --force-update
  helm repo update gitea-charts

  helm upgrade --install gitea gitea-charts/gitea \
    -f "$PROJECT_ROOT/kubernetes/cicd/gitea/helm-values.yaml" \
    --namespace cicd \
    --create-namespace \
    --wait \
    --timeout 10m

  wait_for_rollout "deployment/gitea" "cicd" "300s"

  GITEA_IP=$(kubectl get svc gitea-http -n cicd \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pendente")

  log_ok "Gitea instalado. IP: ${GITEA_IP} | http://gitea.lab.local"
  log_info "Credenciais Gitea: labadmin / labadmin123! (ALTERAR IMEDIATAMENTE)"
}

# -----------------------------------------------------------------------------
# Etapa 5 — Harbor
# -----------------------------------------------------------------------------
step_harbor() {
  log_info "=== Etapa 5: Instalando Harbor ==="

  helm repo add harbor https://helm.goharbor.io --force-update
  helm repo update harbor

  helm upgrade --install harbor harbor/harbor \
    -f "$PROJECT_ROOT/kubernetes/cicd/harbor/helm-values.yaml" \
    --namespace registry \
    --create-namespace \
    --wait \
    --timeout 15m

  log_ok "Harbor instalado. IP: 192.168.1.202 | https://harbor.lab.local"
  log_info "Credenciais Harbor: admin / Harbor12345! (ALTERAR IMEDIATAMENTE)"
}

# -----------------------------------------------------------------------------
# Etapa 6 — ArgoCD
# -----------------------------------------------------------------------------
step_argocd() {
  log_info "=== Etapa 6: Instalando ArgoCD ==="

  helm repo add argo https://argoproj.github.io/argo-helm --force-update
  helm repo update argo

  helm upgrade --install argocd argo/argo-cd \
    -f "$PROJECT_ROOT/kubernetes/cicd/argocd/helm-values.yaml" \
    --namespace cicd \
    --create-namespace \
    --wait \
    --timeout 10m

  wait_for_rollout "deployment/argocd-server" "cicd" "300s"

  # Recuperar senha inicial do ArgoCD
  ARGOCD_PASS=$(kubectl -n cicd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "indisponivel")

  log_ok "ArgoCD instalado. IP: 192.168.1.203 | http://192.168.1.203"
  log_info "Credenciais ArgoCD: admin / ${ARGOCD_PASS}"
  log_warn "Troque a senha do ArgoCD após o primeiro login!"
}

# -----------------------------------------------------------------------------
# Etapa 7 — App of Apps (ArgoCD)
# -----------------------------------------------------------------------------
step_app_of_apps() {
  log_info "=== Etapa 7: Configurando App of Apps no ArgoCD ==="

  # Aguardar ArgoCD estar pronto para aceitar Applications
  wait_for_pods "app.kubernetes.io/name=argocd-server" "cicd" "120"

  kubectl apply -f "$PROJECT_ROOT/kubernetes/cicd/argocd/app-of-apps.yaml"

  log_ok "App of Apps criado. ArgoCD irá sincronizar kubernetes/apps/ automaticamente."
  log_warn "Certifique-se de que o repositório Gitea está acessível em http://gitea.lab.local/lab/infra-lab.git"
}

# -----------------------------------------------------------------------------
# Etapa 8 — Tekton
# -----------------------------------------------------------------------------
step_tekton() {
  log_info "=== Etapa 8: Instalando Tekton Pipelines e Triggers ==="

  log_info "Instalando Tekton Pipelines..."
  kubectl apply --filename \
    "https://storage.googleapis.com/tekton-releases/pipeline/${TEKTON_PIPELINE_VERSION}/release.yaml"

  log_info "Aguardando Tekton Pipelines controller..."
  kubectl wait deployment -n tekton-pipelines tekton-pipelines-controller \
    --for=condition=Available \
    --timeout=180s || log_warn "Tekton Pipelines ainda inicializando"

  log_info "Instalando Tekton Triggers..."
  kubectl apply --filename \
    "https://storage.googleapis.com/tekton-releases/triggers/${TEKTON_TRIGGERS_VERSION}/release.yaml"

  log_info "Instalando Tekton Triggers Interceptors..."
  kubectl apply --filename \
    "https://storage.googleapis.com/tekton-releases/triggers/${TEKTON_TRIGGERS_VERSION}/interceptors.yaml"

  log_info "Aguardando Tekton Triggers controller..."
  kubectl wait deployment -n tekton-pipelines tekton-triggers-controller \
    --for=condition=Available \
    --timeout=180s || log_warn "Tekton Triggers ainda inicializando"

  log_info "Aplicando Pipeline e Triggers do laboratório..."
  kubectl apply -f "$PROJECT_ROOT/kubernetes/cicd/tekton/pipeline-build-push.yaml"
  kubectl apply -f "$PROJECT_ROOT/kubernetes/cicd/tekton/trigger-gitea.yaml"

  log_ok "Tekton instalado. EventListener: 192.168.1.204"
  log_info "Webhook Gitea: http://192.168.1.204 | Secret: configurar no secret gitea-webhook-secret"
  log_warn "Criar secrets antes do primeiro run:"
  echo "  kubectl create secret docker-registry harbor-registry-secret \\"
  echo "    --docker-server=harbor.lab.local \\"
  echo "    --docker-username=admin \\"
  echo "    --docker-password=Harbor12345! \\"
  echo "    --namespace=cicd"
  echo ""
  echo "  kubectl create secret generic gitea-auth-secret \\"
  echo "    --from-literal=username=labadmin \\"
  echo "    --from-literal=password=labadmin123! \\"
  echo "    --namespace=cicd"
  echo ""
  echo "  kubectl create secret generic gitea-webhook-secret \\"
  echo "    --from-literal=secretToken=\$(openssl rand -hex 32) \\"
  echo "    --namespace=cicd"
}

# -----------------------------------------------------------------------------
# Etapa 9 — kube-prometheus-stack
# -----------------------------------------------------------------------------
step_monitoring() {
  log_info "=== Etapa 9: Instalando kube-prometheus-stack ==="

  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts --force-update
  helm repo update prometheus-community

  helm upgrade --install kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    -f "$PROJECT_ROOT/kubernetes/monitoring/kube-prometheus-stack/helm-values.yaml" \
    --namespace monitoring \
    --create-namespace \
    --wait \
    --timeout 15m

  wait_for_rollout "deployment/kube-prometheus-stack-grafana" "monitoring" "300s"

  GRAFANA_IP=$(kubectl get svc kube-prometheus-stack-grafana -n monitoring \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "192.168.1.210")

  log_ok "kube-prometheus-stack instalado."
  log_ok "Grafana: http://${GRAFANA_IP} | admin / lab@admin"

  # Aplicar dashboards customizados
  log_info "Aplicando dashboards Grafana..."
  kubectl apply -f "$PROJECT_ROOT/kubernetes/monitoring/dashboards/k8s-cluster-dashboard.yaml"
  log_ok "Dashboard K8s Cluster Overview carregado."
}

# -----------------------------------------------------------------------------
# Etapa 10 — Loki Stack
# -----------------------------------------------------------------------------
step_loki() {
  log_info "=== Etapa 10: Instalando Loki Stack ==="

  helm repo add grafana https://grafana.github.io/helm-charts --force-update
  helm repo update grafana

  helm upgrade --install loki grafana/loki-stack \
    -f "$PROJECT_ROOT/kubernetes/monitoring/loki-stack/helm-values.yaml" \
    --namespace monitoring \
    --create-namespace \
    --wait \
    --timeout 10m

  log_ok "Loki Stack instalado. Logs disponíveis no Grafana datasource Loki."
}

# -----------------------------------------------------------------------------
# Etapa 11 — App de exemplo
# -----------------------------------------------------------------------------
step_hello_lab() {
  log_info "=== Etapa 11: Deploy da aplicação de exemplo hello-lab ==="

  # Dry-run obrigatório antes do apply real
  log_info "Executando dry-run do hello-lab..."
  kubectl apply --dry-run=client \
    -f "$PROJECT_ROOT/kubernetes/apps/hello-lab/deployment.yaml"
  kubectl apply --dry-run=client \
    -f "$PROJECT_ROOT/kubernetes/apps/hello-lab/service.yaml"
  log_ok "Dry-run OK. Aplicando manifests..."

  kubectl apply -f "$PROJECT_ROOT/kubernetes/apps/hello-lab/deployment.yaml"
  kubectl apply -f "$PROJECT_ROOT/kubernetes/apps/hello-lab/service.yaml"

  wait_for_rollout "deployment/hello-lab" "default" "120s"

  log_ok "hello-lab implantado. Acesso: http://hello.lab.local"
}

# -----------------------------------------------------------------------------
# Resumo final
# -----------------------------------------------------------------------------
print_summary() {
  echo ""
  echo "============================================================"
  echo "  Bootstrap do cluster K3s concluido!"
  echo "============================================================"
  echo ""
  echo "  ACESSOS:"
  echo ""
  echo "  Gitea   : http://192.168.1.201"
  echo "            http://gitea.lab.local"
  echo "            Credenciais: labadmin / labadmin123!"
  echo ""
  echo "  Harbor  : https://192.168.1.202"
  echo "            https://harbor.lab.local"
  echo "            Credenciais: admin / Harbor12345!"
  echo ""
  ARGOCD_PASS=$(kubectl -n cicd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "ver kubectl -n cicd get secret")
  echo "  ArgoCD  : http://192.168.1.203"
  echo "            Credenciais: admin / ${ARGOCD_PASS}"
  echo ""
  echo "  Grafana : http://192.168.1.210"
  echo "            http://grafana.lab.local"
  echo "            Credenciais: admin / lab@admin"
  echo ""
  echo "  Tekton  : EventListener webhook: http://192.168.1.204"
  echo ""
  echo "  Hello   : http://hello.lab.local"
  echo ""
  echo "  PROXIMOS PASSOS:"
  echo "  1. Trocar todas as senhas default"
  echo "  2. Criar secrets do Tekton (harbor-registry-secret, gitea-auth-secret)"
  echo "  3. Configurar webhook no Gitea apontando para 192.168.1.204"
  echo "  4. Adicionar repositorio ao ArgoCD via UI ou ArgoCD CLI"
  echo "  5. Configurar /etc/hosts ou DNS local:"
  echo "     192.168.1.201  gitea.lab.local"
  echo "     192.168.1.202  harbor.lab.local"
  echo "     192.168.1.203  argocd.lab.local"
  echo "     192.168.1.210  grafana.lab.local"
  echo "============================================================"
}

# -----------------------------------------------------------------------------
# Main — execução das etapas
# Descomente/comente etapas para executar parcialmente
# -----------------------------------------------------------------------------
main() {
  echo "============================================================"
  echo "  Bootstrap K3s Lab — $(date '+%Y-%m-%d %H:%M:%S')"
  echo "  KUBECONFIG: $KUBECONFIG"
  echo "============================================================"

  check_prerequisites

  # Bootstrap de infraestrutura
  step_namespaces
  step_metallb
  step_storage

  # CI/CD
  step_gitea
  step_harbor
  step_argocd
  step_app_of_apps
  step_tekton

  # Monitoring
  step_monitoring
  step_loki

  # Aplicação de exemplo
  step_hello_lab

  # Resumo
  print_summary
}

# Suporte a execução de etapa individual:
# ./k8s-bootstrap.sh step_monitoring
# ./k8s-bootstrap.sh step_gitea
if [[ "${1:-}" =~ ^step_ ]]; then
  check_prerequisites
  "$1"
else
  main
fi
