[CmdletBinding()]
param(
    [switch]$SkipOnboard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarnMessage {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[ERRO] $Message" -ForegroundColor Red
}

# --- helpers --------------------------------------------------------------------

function Test-Wsl2Available {
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $wsl) { return $false }
    try {
        $out = & wsl --list --verbose 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
        # pelo menos uma distro listada
        return ($out | Where-Object { $_ -match "\S" } | Measure-Object).Count -gt 1
    }
    catch { return $false }
}

function Get-DefaultWslDistro {
    try {
        $lines = & wsl --list --verbose 2>&1
        $default = $lines | Where-Object { $_ -match "^\s*\*" } | Select-Object -First 1
        if ($default -match "^\s*\*\s+(\S+)") { return $Matches[1] }
    }
    catch {}
    return ""
}

function Enable-WslSystemd {
    param([string]$DistroArg)
    $wslConf = & wsl $DistroArg -- cat /etc/wsl.conf 2>&1
    if ($wslConf -notmatch "systemd=true") {
        Write-WarnMessage "Habilitando systemd no WSL2 (necessario para o daemon)..."
        & wsl $DistroArg -- bash -c "printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf > /dev/null"
        wsl --shutdown
        Write-Step "WSL reiniciado. Aguarde alguns segundos..."
        Start-Sleep -Seconds 5
    }
}

# --- instalar WSL2 --------------------------------------------------------------

function Show-WslNextSteps {
    Write-Host ""
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  Apos reiniciar o Windows:                                       |" -ForegroundColor Green
    Write-Host "|                                                                  |" -ForegroundColor Green
    Write-Host "|  1. Abra o Ubuntu pelo Menu Iniciar e conclua o cadastro.        |" -ForegroundColor Green
    Write-Host "|  2. No terminal Ubuntu, execute:                                 |" -ForegroundColor Green
    Write-Host "|                                                                  |" -ForegroundColor Green
    Write-Host "|     curl -fsSL https://openclaw.ai/install.sh | bash             |" -ForegroundColor Green
    Write-Host "|     openclaw onboard --install-daemon                            |" -ForegroundColor Green
    Write-Host "|                                                                  |" -ForegroundColor Green
    Write-Host "|  Guia: https://docs.openclaw.ai/platforms/windows                |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host ""
}

function Show-VirtualizationHelp {
    Write-Host ""
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "|  VIRTUALIZACAO NAO ESTA HABILITADA NESTE COMPUTADOR              |" -ForegroundColor Yellow
    Write-Host "|                                                                  |" -ForegroundColor Yellow
    Write-Host "|  Para usar WSL2, siga estes passos:                              |" -ForegroundColor Yellow
    Write-Host "|                                                                  |" -ForegroundColor Yellow
    Write-Host "|  PASSO 1 - Habilitar componentes Windows (requer Admin):         |" -ForegroundColor Yellow
    Write-Host "|    Execute no PowerShell como Administrador:                     |" -ForegroundColor Yellow
    Write-Host "|    dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart" -ForegroundColor Cyan
    Write-Host "|    dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart" -ForegroundColor Cyan
    Write-Host "|                                                                  |" -ForegroundColor Yellow
    Write-Host "|  PASSO 2 - Habilitar virtualizacao no BIOS/UEFI:                 |" -ForegroundColor Yellow
    Write-Host "|    Reinicie o PC e entre no BIOS (geralmente F2, F10, Del        |" -ForegroundColor Yellow
    Write-Host "|    ou Esc durante o boot).                                       |" -ForegroundColor Yellow
    Write-Host "|    Procure por: Intel VT-x, AMD-V, SVM Mode ou Virtualization    |" -ForegroundColor Yellow
    Write-Host "|    Habilite e salve (F10).                                       |" -ForegroundColor Yellow
    Write-Host "|                                                                  |" -ForegroundColor Yellow
    Write-Host "|  PASSO 3 - Apos reiniciar, rode este script novamente.           |" -ForegroundColor Yellow
    Write-Host "|                                                                  |" -ForegroundColor Yellow
    Write-Host "|  Ref: https://aka.ms/enablevirtualization                        |" -ForegroundColor Yellow
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
}

function Install-Wsl2AndExit {
    Write-Step "Habilitando componentes do WSL2..."

    # Habilita os componentes Windows necessarios sem instalar distro ainda
    $featureOut = & dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>&1
    $wslFeature = & dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>&1

    Write-Step "Instalando WSL2 + Ubuntu..."
    $installOut = & wsl --install 2>&1
    $installStr = $installOut -join "`n"

    # Detecta erro de virtualizacao/Hyper-V
    if ($installStr -match "HCS_E_HYPERV_NOT_INSTALLED|virtualizacao|virtualization|VirtualMachinePlatform|HYPERV_NOT") {
        Write-Fail "Virtualizacao nao esta habilitada neste computador."
        Show-VirtualizationHelp
        exit 1
    }

    # Verifica outros erros fatais
    if ($LASTEXITCODE -ne 0 -and $installStr -match "erro|error|failed|falha") {
        Write-WarnMessage "wsl --install retornou avisos. Verifique se e necessario reiniciar."
        Write-Host $installStr
    }

    Show-WslNextSteps
    Write-Host "REINICIE o Windows agora para concluir a instalacao do WSL2." -ForegroundColor Yellow
    exit 0
}

# --- instalar OpenClaw no WSL2 --------------------------------------------------

function Install-OpenClawInWsl {
    $distro = Get-DefaultWslDistro
    $distroArg = if ($distro) { @("-d", $distro) } else { @() }

    Write-Step "Verificando systemd no WSL2..."
    Enable-WslSystemd $distroArg

    Write-Step "Instalando OpenClaw dentro do WSL2..."
    & wsl @distroArg -- bash -c "curl -fsSL https://openclaw.ai/install.sh | bash"
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao instalar OpenClaw no WSL2 (exit code $LASTEXITCODE)."
    }
    Write-Ok "OpenClaw instalado no WSL2."

    if (-not $SkipOnboard) {
        Write-Step "Executando onboarding no WSL2..."
        & wsl @distroArg -- bash -c "openclaw onboard --install-daemon"
    }
}

# --- main -----------------------------------------------------------------------

Write-Host ""
Write-Host "  OpenClaw Installer para Windows via WSL2" -ForegroundColor Magenta
Write-Host "  Guia oficial: https://docs.openclaw.ai/platforms/windows" -ForegroundColor DarkGray
Write-Host ""

if (Test-Wsl2Available) {
    Write-Ok "WSL2 encontrado com distro instalada."
    Install-OpenClawInWsl
    Write-Ok "Concluido."
}
else {
    Write-WarnMessage "WSL2 nao encontrado ou nenhuma distro instalada."
    Write-Host ""
    Write-Host "O OpenClaw requer WSL2 no Windows (o modo nativo tem um bug" -ForegroundColor Yellow
    Write-Host "irrecuperavel do Node.js ESM: ERR_UNSUPPORTED_ESM_URL_SCHEME)." -ForegroundColor Yellow
    Write-Host ""

    $resp = Read-Host "Instalar WSL2 + Ubuntu agora? (s/n)"
    if ($resp -match "^[sSyY]") {
        Install-Wsl2AndExit
    }
    else {
        Write-Fail "Instalacao cancelada. Instale o WSL2 manualmente e rode o script novamente."
        Write-Host "  wsl --install" -ForegroundColor Cyan
        Write-Host "  https://docs.openclaw.ai/platforms/windows" -ForegroundColor Cyan
        exit 1
    }
}
Write-Ok "Finalizado."
