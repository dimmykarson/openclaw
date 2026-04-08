[CmdletBinding()]
param(
    [switch]$SkipOnboard,
    [switch]$ForceNative
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

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERRO] $Message" -ForegroundColor Red
}

# --- WSL2 -----------------------------------------------------------------------

function Test-Wsl2Available {
    $wsl = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $wsl) { return $false }
    $list = wsl --list --verbose 2>&1
    return ($list -match "Running|Stopped")
}

function Install-Wsl2 {
    Write-Step "Instalando WSL2 + Ubuntu..."
    wsl --install
    Write-Host @"

+--------------------------------------------------------------+
|  WSL2 instalado. Siga estes passos:                          |
|                                                              |
|  1. REINICIE o Windows quando solicitado.                    |
|  2. Abra o Ubuntu pelo Menu Iniciar e crie seu usuario.      |
|  3. No terminal Ubuntu, rode:                                |
|                                                              |
|     curl -fsSL https://openclaw.ai/install.sh | bash         |
|     openclaw onboard --install-daemon                        |
|                                                              |
|  Guia: https://docs.openclaw.ai/platforms/windows            |
+--------------------------------------------------------------+
"@ -ForegroundColor Green
}

function Invoke-OpenClawInWsl {
    param([string]$Distro = "")

    $distroArg = if ($Distro) { "-d $Distro" } else { "" }

    Write-Step "Instalando OpenClaw dentro do WSL2..."

    # Habilita systemd se necessario
    $wslConf = wsl $distroArg -- cat /etc/wsl.conf 2>&1
    if ($wslConf -notmatch "systemd=true") {
        Write-WarnMessage "Habilitando systemd no WSL2 (necessario para o daemon)..."
        wsl $distroArg -- bash -c "echo -e '[boot]\nsystemd=true' | sudo tee /etc/wsl.conf > /dev/null"
        wsl --shutdown
        Start-Sleep -Seconds 3
    }

    # Instala dentro do WSL
    wsl $distroArg -- bash -c "curl -fsSL https://openclaw.ai/install.sh | bash"

    Write-Ok "OpenClaw instalado no WSL2."

    if (-not $SkipOnboard) {
        Write-Step "Executando onboarding dentro do WSL2..."
        wsl $distroArg -- bash -c "openclaw onboard --install-daemon"
    }
}

# --- Windows nativo -------------------------------------------------------------

function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Write-WarnMessage "winget nao encontrado. Instale Node.js manualmente: https://nodejs.org"
    return $false
}

function Ensure-Node {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Ok "Node.js ja instalado: $(node --version)"
        return
    }

    Write-Step "Node.js nao encontrado. Instalando Node LTS..."
    if (-not (Ensure-Winget)) {
        throw "Node.js ausente e winget indisponivel. Instale Node.js LTS manualmente e reexecute."
    }

    winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements

    # Atualiza PATH da sessao atual
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "Node.js nao encontrado apos instalacao. Feche e reabra o PowerShell e rode novamente."
    }

    Write-Ok "Node.js instalado: $(node --version)"
}

function Install-OpenClawViaOfficialScript {
    $installerUrl = "https://openclaw.ai/install.ps1"
    Write-Step "Tentando instalador oficial: $installerUrl"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $scriptContent = Invoke-RestMethod -Uri $installerUrl -Method Get
    if (-not $scriptContent) { throw "Falha ao baixar o instalador oficial." }

    $tempScript = Join-Path $env:TEMP "openclaw-install.ps1"
    Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tempScript
    Write-Ok "Instalador oficial executado."
}

function Install-OpenClawViaNpm {
    Write-Step "Fallback: instalando via npm"
    Ensure-Node
    npm install -g openclaw@latest
    Write-Ok "OpenClaw instalado via npm."
}

function Validate-Install {
    Write-Step "Validando instalacao"
    if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
        throw "Comando 'openclaw' nao encontrado no PATH."
    }
    Write-Ok "OpenClaw disponivel: $(openclaw --version)"
}

function Invoke-NativeOnboard {
    Write-Step "Executando onboarding (Windows nativo)"
    Write-WarnMessage "AVISO: o Windows nativo tem um bug conhecido do Node.js ESM:"
    Write-WarnMessage "  ERR_UNSUPPORTED_ESM_URL_SCHEME  caminhos 'C:\' nao sao URLs ESM validas."
    Write-WarnMessage "Se ocorrer, use WSL2: https://docs.openclaw.ai/platforms/windows"
    Write-Host ""

    # Workaround: NODE_PATH normalizado como file:// nao resolve o bug do loader,
    # mas NODE_OPTIONS com --experimental-vm-modules pode ajudar em alguns casos.
    $env:NODE_OPTIONS = "--experimental-vm-modules"

    try {
        openclaw onboard --install-daemon
    }
    catch {
        Write-ErrorMessage "Onboarding falhou: $($_.Exception.Message)"
        Write-Host @"

+------------------------------------------------------------------------+
|  Erro ESM no Windows nativo - solucao recomendada: use WSL2           |
|                                                                        |
|  1. No PowerShell (Admin): wsl --install                               |
|  2. Reinicie o Windows.                                                |
|  3. Abra o Ubuntu e rode:                                              |
|     curl -fsSL https://openclaw.ai/install.sh | bash                   |
|     openclaw onboard --install-daemon                                  |
|                                                                        |
|  Guia: https://docs.openclaw.ai/platforms/windows                      |
+------------------------------------------------------------------------+
"@ -ForegroundColor Yellow
    }
}

# --- Main -----------------------------------------------------------------------

Write-Host ""
Write-Host "    OpenClaw Installer para Windows" -ForegroundColor Magenta
Write-Host ""

# Se nao forcar nativo, tenta via WSL2 primeiro
if (-not $ForceNative) {
    if (Test-Wsl2Available) {
        Write-Ok "WSL2 detectado  instalando via WSL2 (caminho recomendado)."
        Invoke-OpenClawInWsl
        Write-Ok "Concluido via WSL2."
        exit 0
    }
    else {
        Write-Host ""
        Write-Host "WSL2 nao encontrado. O que deseja fazer?" -ForegroundColor Yellow
        Write-Host "  [1] Instalar WSL2 agora (recomendado  evita bugs ESM do Node.js)" -ForegroundColor White
        Write-Host "  [2] Continuar com Windows nativo (pode ter problemas)" -ForegroundColor White
        Write-Host ""
        $choice = Read-Host "Escolha (1 ou 2)"

        if ($choice -eq "1") {
            Install-Wsl2
            exit 0
        }
        else {
            Write-WarnMessage "Prosseguindo com instalacao no Windows nativo."
        }
    }
}
else {
    Write-WarnMessage "Modo Windows nativo forcado via -ForceNative."
}

# Instalacao no Windows nativo
try {
    Install-OpenClawViaOfficialScript
}
catch {
    Write-WarnMessage "Falha no instalador oficial: $($_.Exception.Message)"
    Install-OpenClawViaNpm
}

Validate-Install

if (-not $SkipOnboard) {
    Invoke-NativeOnboard
}

Write-Ok "Finalizado."
