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

function Ensure-Winget {
	if (Get-Command winget -ErrorAction SilentlyContinue) {
		return $true
	}
	Write-WarnMessage "winget não encontrado. Se faltar Node.js, instale manualmente: https://nodejs.org"
	return $false
}

function Ensure-Node {
	if (Get-Command node -ErrorAction SilentlyContinue) {
		$nodeVersion = node --version
		Write-Ok "Node.js já instalado: $nodeVersion"
		return
	}

	Write-Step "Node.js não encontrado. Instalando Node LTS..."
	$hasWinget = Ensure-Winget
	if (-not $hasWinget) {
		throw "Node.js ausente e winget indisponível. Instale Node.js LTS e rode o script novamente."
	}

	winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements

	if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
		throw "Node.js não foi encontrado após instalação. Feche e reabra o PowerShell e rode novamente."
	}

	$nodeVersion = node --version
	Write-Ok "Node.js instalado: $nodeVersion"
}

function Install-OpenClawViaOfficialScript {
	$installerUrl = "https://openclaw.ai/install.ps1"
	Write-Step "Tentando instalador oficial: $installerUrl"

	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$scriptContent = Invoke-RestMethod -Uri $installerUrl -Method Get
	if (-not $scriptContent) {
		throw "Não foi possível baixar o conteúdo do instalador oficial."
	}

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
	Write-Step "Validando instalação"

	if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
		throw "Comando 'openclaw' não encontrado no PATH."
	}

	$version = openclaw --version
	Write-Ok "OpenClaw disponível: $version"
}

Write-Host "OpenClaw installer para Windows" -ForegroundColor Magenta
Write-WarnMessage "A documentação recomenda WSL2 para melhor estabilidade no Windows."

try {
	Install-OpenClawViaOfficialScript
}
catch {
	Write-WarnMessage "Falha no instalador oficial: $($_.Exception.Message)"
	Install-OpenClawViaNpm
}

Validate-Install

if (-not $SkipOnboard) {
	Write-Step "Iniciando onboarding"
	Write-Host "Se quiser pular nesta execução, rode com: -SkipOnboard"
	openclaw onboard --install-daemon
}

Write-Ok "Finalizado."
