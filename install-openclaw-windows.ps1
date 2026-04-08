# OpenClaw Installer para Windows
# Requisito: Windows 10 (versao 2004+) ou Windows 11

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Auto-elevacao para Administrador -------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "Solicitando permissao de Administrador..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "    OpenClaw - Instalador para Windows" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Este programa vai instalar o OpenClaw no seu computador." -ForegroundColor White
Write-Host "  Isso pode levar alguns minutos. Nao feche esta janela." -ForegroundColor White
Write-Host ""
Write-Host "  Pressione ENTER para comecar ou feche a janela para cancelar."
Read-Host | Out-Null
Write-Host ""
Write-Host "  Iniciando verificacoes..." -ForegroundColor Gray

# --- Funcoes de status ----------------------------------------------------------

function Show-Progress {
    param([int]$Step, [int]$Total, [string]$Message)
    Write-Host ""
    Write-Host "  [$Step/$Total] $Message" -ForegroundColor Cyan
}

function Show-Ok    { param([string]$Msg); Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Show-Warn  { param([string]$Msg); Write-Host "  [!]  $Msg" -ForegroundColor Yellow }
function Show-Fail  { param([string]$Msg); Write-Host "  [X] $Msg" -ForegroundColor Red }
function Pause-End  { Write-Host ""; Write-Host "  Pressione qualquer tecla para fechar..."; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }

# --- Passo 1: Verificar se o computador suporta virtualizacao -------------------

Show-Progress 1 4 "Verificando se o computador suporta WSL2..."

try {
    $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
    $virtEnabled = $cpu.VirtualizationFirmwareEnabled
} catch {
    # Nao foi possivel ler via WMI (comum em VMs) - assume que esta habilitado
    $virtEnabled = $null
}

# Verifica se Virtual Machine Platform ja esta ativo
$vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
$vmpActive  = $vmpFeature -and $vmpFeature.State -eq "Enabled"

# Trata $false explicitamente - $null significa 'nao foi possivel verificar' (nao bloqueia)
if ($virtEnabled -eq $false) {
    Show-Fail "A virtualizacao esta DESATIVADA no BIOS deste computador."
    Write-Host ""
    Write-Host "  Para ativar, siga estes 3 passos simples:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  PASSO 1: Reinicie o computador" -ForegroundColor White
    Write-Host "           Assim que a tela apagar, pressione repetidamente" -ForegroundColor Gray
    Write-Host "           a tecla F2, F10, F12, Del ou Esc (depende da marca)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  PASSO 2: Dentro do BIOS, procure por uma dessas opcoes:" -ForegroundColor White
    Write-Host "           'Intel Virtualization Technology', 'AMD-V' ou 'SVM Mode'" -ForegroundColor Gray
    Write-Host "           Mude para ENABLED (habilitado)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  PASSO 3: Salve (geralmente F10) e reinicie o computador" -ForegroundColor White
    Write-Host "           Depois, rode este instalador novamente" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Referencia: https://aka.ms/enablevirtualization" -ForegroundColor DarkGray
    Write-Host ""
    Pause-End
    exit 1
}

Show-Ok "Virtualizacao disponivel."

# --- Passo 2: Habilitar componentes do Windows ----------------------------------

Show-Progress 2 4 "Habilitando componentes necessarios do Windows..."

$needsReboot = $false

if (-not $vmpActive) {
    Show-Warn "Habilitando 'Plataforma de Maquina Virtual'..."
    dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    $needsReboot = $true
}

$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
if (-not ($wslFeature -and $wslFeature.State -eq "Enabled")) {
    Show-Warn "Habilitando 'Subsistema do Windows para Linux'..."
    dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    $needsReboot = $true
}

if ($needsReboot) {
    Show-Ok "Componentes habilitados. E necessario reiniciar o computador."
    Write-Host ""
    Write-Host "  O computador sera reiniciado em 30 segundos." -ForegroundColor Yellow
    Write-Host "  Apos reiniciar, execute este instalador novamente para continuar." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Pressione ENTER para reiniciar agora ou feche para reiniciar manualmente."
    Read-Host | Out-Null
    Restart-Computer -Force
    exit 0
}

Show-Ok "Componentes do Windows prontos."

# --- Passo 3: Instalar o WSL2 + Ubuntu ------------------------------------------

Show-Progress 3 4 "Instalando WSL2 + Ubuntu (pode demorar alguns minutos)..."

# O teste mais confiavel: tenta rodar um comando dentro do WSL
# Se funcionar, tudo esta pronto. Se falhar, precisa instalar/reiniciar.
$wslFuncional = $false
try {
    $testOut = & wsl -- echo "wsl_ok" 2>&1
    $wslFuncional = ($LASTEXITCODE -eq 0) -and ("$testOut" -match "wsl_ok")
} catch {}

if (-not $wslFuncional) {
    # Verifica se o kernel do WSL2 ja existe
    $kernelOk = $false
    try {
        & wsl --version 2>&1 | Out-Null
        $kernelOk = ($LASTEXITCODE -eq 0)
    } catch {}

    if (-not $kernelOk) {
        # Instala kernel + Ubuntu e reinicia
        $installOut = & wsl --install 2>&1
        $installStr = $installOut -join "`n"

        if ($installStr -match "HCS_E_HYPERV_NOT_INSTALLED|HYPERV_NOT") {
            Show-Fail "Erro: Hyper-V nao esta disponivel."
            Show-Warn "Verifique se a virtualizacao esta ativa no BIOS (passo 1) e tente novamente."
            Pause-End
            exit 1
        }
    } else {
        # Kernel ok mas Ubuntu nao responde - instala a distro
        Show-Warn "Instalando Ubuntu..."
        & wsl --install -d Ubuntu 2>&1 | Out-Null
    }

    Show-Ok "WSL2 instalado. O computador precisa reiniciar para concluir."
    Write-Host ""
    Write-Host "  IMPORTANTE: Apos reiniciar, execute este instalador novamente." -ForegroundColor Yellow
    Write-Host "  Na proxima vez ele instala o OpenClaw direto, sem mais reinicializacoes." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Pressione ENTER para reiniciar agora."
    Read-Host | Out-Null
    Restart-Computer -Force
    exit 0

} else {
    Show-Ok "WSL2 com Ubuntu pronto."
}

# --- Passo 4: Instalar o OpenClaw dentro do WSL2 --------------------------------

Show-Progress 4 4 "Instalando OpenClaw..."

# Habilita systemd (necessario para o daemon do OpenClaw)
$wslConf = & wsl -- cat /etc/wsl.conf 2>&1
if ($wslConf -notmatch "systemd=true") {
    & wsl -- bash -c "printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf > /dev/null"
    & wsl --shutdown
    Start-Sleep -Seconds 4
}

# Instala o OpenClaw (HTTPS garante autenticidade do servidor)
& wsl -- bash -c "curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash"

if ($LASTEXITCODE -ne 0) {
    Show-Fail "Erro ao instalar o OpenClaw. Tente novamente."
    Pause-End
    exit 1
}

Show-Ok "OpenClaw instalado com sucesso!"

# --- Configuracao inicial -------------------------------------------------------

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "    OpenClaw instalado! Vamos configurar agora." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  O assistente de configuracao vai abrir." -ForegroundColor White
Write-Host "  Ele vai pedir sua chave de API (ex: Anthropic, Google, OpenAI)." -ForegroundColor White
Write-Host ""
Write-Host "  Pressione ENTER para comecar a configuracao."
Read-Host | Out-Null

& wsl -- bash -c "openclaw onboard --install-daemon"

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Green
Write-Host "    Pronto! OpenClaw esta funcionando." -ForegroundColor Green
Write-Host "  ================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Para usar o OpenClaw novamente, abra o Ubuntu" -ForegroundColor White
Write-Host "  pelo Menu Iniciar e digite: openclaw" -ForegroundColor Cyan
Write-Host ""
Pause-End
