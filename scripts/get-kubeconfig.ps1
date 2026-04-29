#Requires -Version 5.1
<#
.SYNOPSIS
    Copia o kubeconfig do K3s server para a máquina local.

.DESCRIPTION
    1. Conecta via SSH no k3s-server (192.168.1.30)
    2. Lê /etc/rancher/k3s/k3s.yaml
    3. Substitui 127.0.0.1/localhost pelo IP real do servidor
    4. Salva em ~/.kube/infra-lab.yaml (ou caminho customizado)
    5. Exibe instrução para setar $env:KUBECONFIG

.PARAMETER Output
    Caminho local para salvar o kubeconfig. Padrão: ~/.kube/infra-lab.yaml

.PARAMETER Server
    IP do K3s server. Padrão: 192.168.1.30

.PARAMETER Key
    Caminho da chave SSH privada. Padrão: ~/.ssh/lab_id_rsa

.EXAMPLE
    .\get-kubeconfig.ps1
    .\get-kubeconfig.ps1 -Output "$HOME\.kube\meu-lab.yaml"
    .\get-kubeconfig.ps1 -Server 192.168.1.30 -Key "$HOME\.ssh\lab_id_rsa"
#>
[CmdletBinding()]
param(
    [Alias('o')]
    [string]$Output = "$env:USERPROFILE\.kube\infra-lab.yaml",

    [Alias('s')]
    [string]$Server = '192.168.1.30',

    [Alias('k')]
    [string]$Key = "$env:USERPROFILE\.ssh\lab_id_rsa"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$K3S_USER           = 'labadmin'
$REMOTE_KUBECONFIG  = '/etc/rancher/k3s/k3s.yaml'

# ---------------------------------------------------------------------------
# Verificações
# ---------------------------------------------------------------------------

Write-Host '[INFO] Verificando pré-requisitos...'

if (-not (Test-Path $Key)) {
    Write-Error "[ERRO] Chave SSH não encontrada: $Key"
    exit 1
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Error '[ERRO] ssh não encontrado. Instale o OpenSSH Client (Configurações → Apps → Recursos opcionais).'
    exit 1
}

# Testar conectividade SSH
Write-Host "[INFO] Testando conectividade SSH com ${K3S_USER}@${Server}..."
$testResult = ssh -i $Key `
    -o ConnectTimeout=10 `
    -o StrictHostKeyChecking=no `
    -o BatchMode=yes `
    "${K3S_USER}@${Server}" `
    'echo ok' 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERRO] Não foi possível conectar ao K3s server ($Server).`n       Verifique: IP correto, SSH ativo, chave SSH autorizada."
    exit 1
}
Write-Host '[OK]   Conexão SSH estabelecida' -ForegroundColor Green

# ---------------------------------------------------------------------------
# Criar diretório .kube se necessário
# ---------------------------------------------------------------------------

$kubeDir = Split-Path $Output -Parent
if (-not (Test-Path $kubeDir)) {
    Write-Host "[INFO] Criando diretório $kubeDir..."
    New-Item -ItemType Directory -Path $kubeDir -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Fazer backup do kubeconfig atual (se existir)
# ---------------------------------------------------------------------------

if (Test-Path $Output) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup    = "${Output}.backup.${timestamp}"
    Write-Host "[INFO] Backup do kubeconfig atual: $backup"
    Copy-Item $Output $backup
}

# ---------------------------------------------------------------------------
# Copiar e adaptar kubeconfig
# ---------------------------------------------------------------------------

Write-Host "[INFO] Copiando kubeconfig de ${Server}:${REMOTE_KUBECONFIG}..."

$rawConfig = ssh -i $Key `
    -o StrictHostKeyChecking=no `
    "${K3S_USER}@${Server}" `
    "sudo cat $REMOTE_KUBECONFIG" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERRO] Falha ao ler $REMOTE_KUBECONFIG no servidor.`n       Verifique se o K3s está rodando e se labadmin tem sudo."
    exit 1
}

# Substituir loopback pelo IP real do servidor
$adaptedConfig = $rawConfig `
    -replace '127\.0\.0\.1', $Server `
    -replace 'localhost',     $Server

# Salvar
$adaptedConfig | Set-Content -Path $Output -Encoding UTF8

# Restringir permissões do arquivo (equivalente a chmod 600 no Windows)
$acl  = Get-Acl $Output
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
    'FullControl',
    'Allow'
)
$acl.AddAccessRule($rule)
Set-Acl $Output $acl

Write-Host "[OK]   Kubeconfig salvo em: $Output" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Verificar acesso ao cluster
# ---------------------------------------------------------------------------

Write-Host '[INFO] Verificando acesso ao cluster...'
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    $nodes = kubectl --kubeconfig $Output get nodes 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host '[OK]   Acesso ao cluster K3s confirmado' -ForegroundColor Green
        Write-Host ''
        kubectl --kubeconfig $Output get nodes -o wide
    } else {
        Write-Warning "[WARN] Não foi possível verificar acesso ao cluster.`n       Verifique se o K3s está rodando: ssh labadmin@$Server 'sudo k3s kubectl get nodes'"
    }
} else {
    Write-Warning '[WARN] kubectl não encontrado — instale para verificar o cluster.'
}

# ---------------------------------------------------------------------------
# Instruções finais
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ' Kubeconfig pronto para uso!'             -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host ' Para usar na sessão atual:'
Write-Host "   `$env:KUBECONFIG = '$Output'" -ForegroundColor Yellow
Write-Host '   kubectl get nodes -o wide'
Write-Host ''
Write-Host ' Para persistir no perfil PowerShell (adicione ao $PROFILE):'
Write-Host "   `$env:KUBECONFIG = '$Output'" -ForegroundColor Yellow
Write-Host ''
