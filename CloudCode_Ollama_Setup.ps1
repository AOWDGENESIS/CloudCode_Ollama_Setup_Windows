<#
.SYNOPSIS
    Cloud Code / Claude Code + Ollama Setup Script fuer Windows.

.DESCRIPTION
    Richtet Ollama (Standard: F:\Ollama\ollama.exe) und Claude / Cloud Code ein:
    - arbeitet standardmaessig ohne erzwungene Administrator-Berechtigungen
    - Richtet Modell-Speicherort auf F:\Ollama\models ein (schont Systemlaufwerk C:)
    - Fuegt Pfade sicher zur PATH-Umgebungsvariable hinzu (ohne 1024-Zeichen setx-Limit)
    - Prueft den Ollama-Dienst und startet ihn bei Bedarf
    - Prueft und laedt das gewuenschte LLM-Modell (Standard: llama3.1)
    - Ermittelt die Coding-Agent-CLI (cloudcode / claude) gezielt in Standardpfaden
    - Erstellt Kompatibilitaets-Wrapper fuer nahtlose Ausfuehrung ('cloudcode' und 'claude')
    - Konfiguriert die Umgebungsvariablen fuer die lokale Anbindung
    - Fuehrt automatisierte Verbindungs- und Funktionstests durch

.PARAMETER OllamaPath
    Pfad zur ollama.exe (Standard: F:\Ollama\ollama.exe).

.PARAMETER ModelsPath
    Zielverzeichnis fuer Modelle (Standard: F:\Ollama\models).

.PARAMETER Model
    Name des zu ladenden Ollama-Modells (Standard: llama3.1).

.PARAMETER CustomCliPath
    Optionaler expliziter Pfad zur CLI (cloudcode.exe oder claude.exe).

.PARAMETER LogFile
    Pfad zur Protokolldatei.

.PARAMETER ServiceWaitTimeoutSec
    Maximale Wartezeit auf den Ollama-Dienst in Sekunden (Standard: 20).

.PARAMETER ApiPort
    Port des Ollama-Dienstes (Standard: 11434).

.PARAMETER SkipAdminCheck
    Ueberspringt die informative Administrator-Pruefung.

.PARAMETER SkipModelPull
    Ueberspringt das Herunterladen des Modells.

.PARAMETER DryRun
    Simulationsmodus ohne permanente Systemaenderungen.

.PARAMETER InstallCli
    Installiert Claude Code nur nach ausdruecklicher Freigabe per offiziellem
    Installer oder npm. Ohne diesen Schalter wird nichts aus dem Internet
    heruntergeladen.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification = "Interaktives Konsolen-Setup erfordert farbige Direktausgabe fuer Benutzer")]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OllamaPath = "F:\Ollama\ollama.exe",

    [Parameter(Mandatory = $false)]
    [string]$ModelsPath = "F:\Ollama\models",

    [Parameter(Mandatory = $false)]
    [string]$Model = "llama3.1",

    [Parameter(Mandatory = $false)]
    [string]$CustomCliPath = "",

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "$env:USERPROFILE\cloudcode_ollama_setup.log",

    [Parameter(Mandatory = $false)]
    [int]$ServiceWaitTimeoutSec = 20,

    [Parameter(Mandatory = $false)]
    [int]$ApiPort = 11434,

    [Parameter(Mandatory = $false)]
    [switch]$SkipAdminCheck,

    [Parameter(Mandatory = $false)]
    [switch]$SkipModelPull,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$InstallCli,

    [Parameter(Mandatory = $false)]
    [switch]$OnlyFunctions
)

# Setze strikte Fehlerbehandlung
$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# 1. LOGGING & KONSOLENAUSGABE
# -----------------------------------------------------------------------------

function Write-SetupLog {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification = "Konsolenausgabe fuer Statusmeldungen")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timeStamp] [$Level] $Message"

    # In Logdatei schreiben
    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        try {
            $logDir = Split-Path -Path $LogFile -Parent
            if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -Path $logDir)) {
                $null = New-Item -ItemType Directory -Path $logDir -Force
            }
            $logLine | Out-File -FilePath $LogFile -Append -Encoding UTF8
        }
        catch {
            $null = $_
        }
    }

    # Farbige Konsolenausgabe
    switch ($Level) {
        "Success" { Write-Host "  [OK]  $Message" -ForegroundColor Green }
        "Warning" { Write-Host " [WARN] $Message" -ForegroundColor Yellow }
        "Error"   { Write-Host "[FEHLER] $Message" -ForegroundColor Red }
        Default   { Write-Host " [INFO] $Message" -ForegroundColor Cyan }
    }
}

# -----------------------------------------------------------------------------
# 2. PLATTFORM- & ADMIN-PRUEFUNG
# -----------------------------------------------------------------------------

function Test-IsWindows {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # In PowerShell Core (6/7+) ist $IsWindows eine eingebaute Variable
    $isWinVar = Get-Variable -Name "IsWindows" -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $isWinVar) {
        return [bool]$isWinVar
    }

    # In Windows PowerShell 5.1 und aelter laeuft PowerShell ausschliesslich auf Windows
    if ($PSVersionTable.PSVersion.Major -le 5) {
        return $true
    }

    return ($env:OS -like "*Windows*")
}

function Test-IsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (Test-IsWindows) {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]$identity
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch {
            return $false
        }
    }
    return $true
}

# -----------------------------------------------------------------------------
# 3. SICHERE PATH-VERWALTUNG (Verhindert 1024-Zeichen setx-Datenverlust)
# -----------------------------------------------------------------------------

function Add-DirectoryToPathSafe {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDirectory,

        [Parameter(Mandatory = $false)]
        [ValidateSet("User", "Machine")]
        [string]$Scope = "User"
    )

    if (-not (Test-Path -Path $TargetDirectory)) {
        return $false
    }

    $normalizedTarget = $TargetDirectory.TrimEnd('\', '/')

    # 1. Im aktuellen PowerShell-Prozess ergaenzen
    $currentProcessPaths = ($env:Path -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $alreadyInProcess = $currentProcessPaths | Where-Object { $_.TrimEnd('\', '/') -ieq $normalizedTarget }

    if (-not $alreadyInProcess) {
        $env:Path = "$($env:Path);$normalizedTarget"
    }

    # 2. Dauerhaft in Windows Benutzer-/Maschinen-Umgebung eintragen
    if (Test-IsWindows) {
        try {
            $currentEnvPath = [Environment]::GetEnvironmentVariable("Path", $Scope)
            $envPaths = if ($currentEnvPath) {
                ($currentEnvPath -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            } else {
                @()
            }

            $alreadyInScope = $envPaths | Where-Object { $_.TrimEnd('\', '/') -ieq $normalizedTarget }
            if (-not $alreadyInScope) {
                $newEnvPath = ($envPaths + $normalizedTarget) -join ';'
                [Environment]::SetEnvironmentVariable("Path", $newEnvPath, $Scope)
                Write-SetupLog "Pfad '$normalizedTarget' dauerhaft zu $Scope-PATH hinzugefuegt." -Level "Success"
                return $true
            }
        }
        catch {
            Write-SetupLog "Konnte PATH in Scope '$Scope' nicht dauerhaft anpassen: $_" -Level "Warning"
            return $false
        }
    }

    return $true
}

# -----------------------------------------------------------------------------
# 4. OLLAMA API HELFER
# -----------------------------------------------------------------------------

function Test-OllamaApiReady {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$BaseUrl = "http://127.0.0.1:11434"
    )

    try {
        $uri = "$BaseUrl/api/version"
        $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 2 -ErrorAction Stop
        if ($response -and $response.version) {
            return $true
        }
    }
    catch {
        $null = $_
    }
    return $false
}

function Test-OllamaModel {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetModel,

        [Parameter(Mandatory = $false)]
        [string]$BaseUrl = "http://127.0.0.1:11434"
    )

    try {
        $uri = "$BaseUrl/api/tags"
        $tags = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 5 -ErrorAction Stop
        if ($tags -and $tags.models) {
            foreach ($m in $tags.models) {
                $targetPattern = "$($TargetModel):*"
                if ($m.name -eq $TargetModel -or $m.name -like $targetPattern) {
                    return $true
                }
            }
        }
    }
    catch {
        $null = $_
    }
    return $false
}

# -----------------------------------------------------------------------------
# 5. CODING-CLI SUCHE
# -----------------------------------------------------------------------------

function Find-CodingCli {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ExplicitPath
    )

    # 1. Explizit konfigurierter Pfad
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -Path $ExplicitPath)) {
        return (Get-Item -Path $ExplicitPath).FullName
    }

    # 2. Suche im PATH ueber Get-Command
    $candidateCommands = @("cloudcode.exe", "cloudcode.cmd", "cloudcode", "claude.exe", "claude.cmd", "claude")
    foreach ($cmd in $candidateCommands) {
        $found = Get-Command -Name $cmd -ErrorAction SilentlyContinue
        if ($found -and $found.Source -and (Test-Path -Path $found.Source)) {
            return $found.Source
        }
    }

    # 3. Gezielte Suche in typischen Installationsverzeichnissen
    $userProf = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath("UserProfile") }
    $localApp = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath("LocalApplicationData") }
    $appData = if ($env:APPDATA) { $env:APPDATA } else { [Environment]::GetFolderPath("ApplicationData") }
    $progFiles = if ($env:ProgramFiles) { $env:ProgramFiles } else { "C:\Program Files" }

    $searchDirectories = @(
        "$userProf\.cloudcode\bin",
        "$userProf\.claude\bin",
        "$userProf\.claude",
        "$localApp\Programs\cloudcode",
        "$localApp\Programs\claude",
        "$appData\npm",
        "$localApp\Microsoft\WinGet\Links",
        "F:\CloudCode",
        "F:\Claude",
        "F:\Ollama",
        "$progFiles\Claude",
        "$progFiles\CloudCode"
    )

    foreach ($dir in $searchDirectories) {
        if (Test-Path -Path $dir) {
            foreach ($binary in @("cloudcode.exe", "cloudcode.cmd", "claude.exe", "claude.cmd")) {
                $candidate = Join-Path -Path $dir -ChildPath $binary
                if (Test-Path -Path $candidate) {
                    return (Get-Item -Path $candidate).FullName
                }
            }
        }
    }

    return [string]::Empty
}

# -----------------------------------------------------------------------------
# HAUPTPROGRAMM
# -----------------------------------------------------------------------------

if ($OnlyFunctions) {
    return
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Cloud Code / Claude Code + Ollama Windows Setup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-SetupLog "Setup gestartet. Logdatei: $LogFile" -Level "Info"

# --- SCHRITT 1: ADMINISTRATOR-PRUEFUNG ---
if (-not $SkipAdminCheck) {
    if (Test-IsAdministrator) {
        Write-SetupLog "Administrator-Rechte bestaetigt." -Level "Success"
    } else {
        Write-SetupLog "Keine Administrator-Rechte. Es werden nur Benutzer-Umgebungsvariablen und Benutzerpfade verwendet." -Level "Warning"
    }
} else {
    Write-SetupLog "Admin-Check uebersprungen (-SkipAdminCheck aktiv)." -Level "Warning"
}

# --- SCHRITT 2: OLLAMA PFAD & SPEICHERORT PRUEFEN ---
Write-SetupLog "Pruefe Ollama-Installation..." -Level "Info"
$resolvedOllama = $null

if (Test-Path -Path $OllamaPath) {
    $resolvedOllama = (Get-Item -Path $OllamaPath).FullName
    Write-SetupLog "Ollama unter '$resolvedOllama' gefunden." -Level "Success"
} else {
    Write-SetupLog "Ollama nicht direkt unter '$OllamaPath' gefunden. Suche Alternativen..." -Level "Warning"

    # Fallback A: PATH
    $cmdOllama = Get-Command "ollama.exe" -ErrorAction SilentlyContinue
    if ($cmdOllama -and $cmdOllama.Source) {
        $resolvedOllama = $cmdOllama.Source
        Write-SetupLog "Ollama im PATH gefunden: $resolvedOllama" -Level "Success"
    } else {
        # Fallback B: Lokaler Standardpfad
        $defaultOllama = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
        if (Test-Path -Path $defaultOllama) {
            $resolvedOllama = $defaultOllama
            Write-SetupLog "Ollama im Standardordner gefunden: $resolvedOllama" -Level "Success"
        }
    }
}

if (-not $resolvedOllama) {
    Write-SetupLog "Ollama wurde weder unter '$OllamaPath' noch im System gefunden!" -Level "Error"
    Write-Host "`nBitte stelle sicher, dass Ollama auf Laufwerk F:\ liegt oder uebergib -OllamaPath <Pfad>." -ForegroundColor Red
    Exit 1
}

$ollamaDir = Split-Path -Path $resolvedOllama -Parent
$null = Add-DirectoryToPathSafe -TargetDirectory $ollamaDir -Scope "User"

# Konfiguriere Modell-Speicherort auf F:\ (verhindert C:-Festplattenueberlauf)
$modelsPathChanged = $false
if (-not [string]::IsNullOrWhiteSpace($ModelsPath)) {
    $existingModelsVar = [Environment]::GetEnvironmentVariable("OLLAMA_MODELS", "User")
    $modelsPathChanged = ($existingModelsVar -ne $ModelsPath)

    if (-not $DryRun) {
        try {
            if (-not (Test-Path -Path $ModelsPath)) {
                $null = New-Item -ItemType Directory -Path $ModelsPath -Force
            }
            if ((Test-IsWindows)) {
                try {
                    [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $ModelsPath, [System.EnvironmentVariableTarget]::Machine)
                }
                catch {
                    # Machine-Scope erfordert erhoehte Rechte; falls eingeschraenkt, weiter mit User
                    $null = $_
                }
                [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $ModelsPath, [System.EnvironmentVariableTarget]::User)
            }
            [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $ModelsPath, [System.EnvironmentVariableTarget]::Process)
            Write-SetupLog "Ollama-Modellverzeichnis auf '$ModelsPath' gesetzt." -Level "Success"
        }
        catch {
            Write-SetupLog "Hinweis zu Modellverzeichnis '$ModelsPath': $_" -Level "Warning"
        }
    } else {
        Write-SetupLog "Simulation: Ollama-Modellverzeichnis waere '$ModelsPath'." -Level "Info"
    }
}

# --- SCHRITT 3: OLLAMA DIENST PRUEFEN & STARTEN ---
$baseUrl = "http://127.0.0.1:$ApiPort"
Write-SetupLog "Pruefe Erreichbarkeit des Ollama-Dienstes ($baseUrl)..." -Level "Info"

# Falls der Modellpfad neu geaendert wurde und Ollama bereits lief, Dienst neu starten
# (Ollama-Daemon uebernimmt Umgebungsvariablen wie OLLAMA_MODELS nur bei Prozessneustart)
if ($modelsPathChanged -and (Test-OllamaApiReady -BaseUrl $baseUrl) -and (-not $DryRun)) {
    Write-SetupLog "Ollama lief bereits vor Aenderung von OLLAMA_MODELS. Starte Dienst neu, damit Modelle auf '$ModelsPath' abgelegt werden..." -Level "Info"
    if ((Test-IsWindows)) {
        Get-Process -Name "ollama*", "ollama app*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}

$serviceReady = Test-OllamaApiReady -BaseUrl $baseUrl

if ($serviceReady) {
    Write-SetupLog "Ollama-Dienst laeuft bereits und antwortet auf Anfragen." -Level "Success"
} else {
    Write-SetupLog "Ollama antwortet noch nicht. Starte Dienst im Hintergrund..." -Level "Info"
    if (-not $DryRun) {
        try {
            if (Test-IsWindows) {
                $null = Start-Process -FilePath $resolvedOllama -ArgumentList "serve" -WindowStyle Hidden
            } else {
                $null = Start-Process -FilePath $resolvedOllama -ArgumentList "serve" -RedirectStandardOutput "/dev/null" -RedirectStandardError "/tmp/ollama_err.log"
            }
        }
        catch {
            Write-SetupLog "Konnte '$resolvedOllama serve' nicht starten: $_" -Level "Error"
            Exit 1
        }

        # Warte mit Polling auf Bereitschaft
        $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        while ($stopWatch.Elapsed.TotalSeconds -lt $ServiceWaitTimeoutSec) {
            Start-Sleep -Seconds 1
            if (Test-OllamaApiReady -BaseUrl $baseUrl) {
                $serviceReady = $true
                break
            }
        }
        $stopWatch.Stop()
    } else {
        $serviceReady = $true
    }
}

if (-not $serviceReady) {
    Write-SetupLog "Der Ollama-Dienst konnte nach $ServiceWaitTimeoutSec Sekunden nicht erreicht werden (Port $ApiPort blockiert?)." -Level "Error"
    Exit 1
}
Write-SetupLog "Ollama-Dienst ist einsatzbereit." -Level "Success"

# --- SCHRITT 4: MODELL PRUEFEN, HERUNTERLADEN & ALIASE EINRICHTEN ---
if (-not $SkipModelPull) {
    Write-SetupLog "Pruefe Status von Modell '$Model'..." -Level "Info"
    $modelExists = Test-OllamaModel -TargetModel $Model -BaseUrl $baseUrl

    if ($modelExists) {
        Write-SetupLog "Modell '$Model' ist bereits lokal vorhanden." -Level "Success"
    } else {
        Write-SetupLog "Lade Modell '$Model' herunter (dies kann je nach Internetverbindung dauern)..." -Level "Info"
        if (-not $DryRun) {
            & $resolvedOllama pull $Model
            if ($LASTEXITCODE -ne 0) {
                Write-SetupLog "Fehler beim Herunterladen des Modells '$Model' (Code: $LASTEXITCODE)." -Level "Error"
                Exit 1
            }
            Write-SetupLog "Modell '$Model' erfolgreich heruntergeladen." -Level "Success"
        } else {
            Write-SetupLog "Simulation: Modell-Download uebersprungen (-DryRun)." -Level "Info"
        }
    }

    # Erstelle Modell-Aliase fuer Claude Code (verhindert 'model not found' bei Standardaufrufen wie 'claude')
    if (-not $DryRun) {
        $claudeAliases = @("claude-3-5-sonnet", "claude-3-7-sonnet")
        foreach ($aliasName in $claudeAliases) {
            try {
                & $resolvedOllama cp $Model $aliasName 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-SetupLog "Modell-Alias '$aliasName' -> '$Model' erfolgreich registriert." -Level "Success"
                }
            }
            catch {
                $null = $_
            }
        }
    }
} else {
    Write-SetupLog "Modell-Download uebersprungen (-SkipModelPull aktiv)." -Level "Info"
}

# --- SCHRITT 5: CODING-CLI (CLOUD CODE / CLAUDE CODE) FINDEN / INSTALLIEREN ---
Write-SetupLog "Ermittle Coding-Agent CLI (cloudcode / claude)..." -Level "Info"
$cliPath = Find-CodingCli -ExplicitPath $CustomCliPath

if ([string]::IsNullOrWhiteSpace($cliPath) -and $InstallCli) {
    Write-SetupLog "Keine vorhandene CLI-Installation gefunden. Pruefe Installationsoptionen..." -Level "Warning"

    $installSuccessful = $false
    if (-not $DryRun) {
        # Option 1: Offizieller Claude Code PowerShell-Installer
        try {
            Write-SetupLog "Lade offiziellen Claude Code Installer herunter..." -Level "Info"
            $tempScript = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "install-claude.ps1"
            $installerContent = Invoke-RestMethod -Uri "https://claude.ai/install.ps1" -Method Get -TimeoutSec 15
            $installerContent | Out-File -FilePath $tempScript -Encoding UTF8 -Force

            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript
            $installSuccessful = ($LASTEXITCODE -eq 0)
            if (Test-Path -Path $tempScript) {
                Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-SetupLog "Offizieller Installer fehlgeschlagen. Versuche Installation ueber npm..." -Level "Warning"
            $npm = Get-Command "npm" -ErrorAction SilentlyContinue
            if ($npm) {
                & npm install -g @anthropic-ai/claude-code
                if ($LASTEXITCODE -eq 0) {
                    $installSuccessful = $true
                }
            }
        }

        if ($installSuccessful) {
            $cliPath = Find-CodingCli
        }
    }
}

# Zielverzeichnis fuer Wrapper: falls CLI gefunden, dessen Ordner; sonst Ollama-Verzeichnis
$wrapperDir = Join-Path -Path $env:USERPROFILE -ChildPath ".cloudcode\bin"
if (-not $DryRun) {
    $null = New-Item -ItemType Directory -Path $wrapperDir -Force
}
if (-not [string]::IsNullOrWhiteSpace($cliPath)) {
    $null = Add-DirectoryToPathSafe -TargetDirectory (Split-Path -Path $cliPath -Parent) -Scope "User"
}

if (-not [string]::IsNullOrWhiteSpace($cliPath)) {
    Write-SetupLog "CLI erfolgreich erkannt: $cliPath" -Level "Success"
    $null = Add-DirectoryToPathSafe -TargetDirectory $wrapperDir -Scope "User"
} else {
    Write-SetupLog "CLI nicht als eigenstaendige Binärdatei gefunden. Verwende Ollama-Bridge." -Level "Warning"
}

# Universeller Kompatibilitaets-Wrapper 'cloudcode.cmd':
# Leitet 'cloudcode' intelligent an 'claude' weiter oder faellt auf 'ollama launch claude' zurueck
if ((Test-IsWindows) -and (-not $DryRun)) {
    $wrapperTarget = Join-Path -Path $wrapperDir -ChildPath "cloudcode.cmd"
    try {
        $wrapperContent = "@echo off`r`nwhere claude >nul 2>&1`r`nif %errorlevel% equ 0 (`r`n    claude %*`r`n    exit /b %errorlevel%`r`n)`r`nwhere ollama >nul 2>&1`r`nif %errorlevel% equ 0 (`r`n    ollama launch claude %*`r`n    exit /b %errorlevel%`r`n)`r`necho [FEHLER] Weder 'claude' noch 'ollama' im PATH gefunden.`r`nexit /b 1"
        $wrapperContent | Out-File -FilePath $wrapperTarget -Encoding ASCII -Force
        Write-SetupLog "Universeller Befehl 'cloudcode' eingerichtet -> $wrapperTarget" -Level "Success"
    }
    catch {
        $null = $_
    }
}

# --- SCHRITT 6: UMGEBUNGSVARIABLEN FUER OLLAMA-ANBINDUNG KONFIGURIEREN ---
Write-SetupLog "Setze Umgebungsvariablen fuer die Ollama-Anbindung..." -Level "Info"

$envSettings = @{
    "ANTHROPIC_BASE_URL"                     = $baseUrl
    "ANTHROPIC_AUTH_TOKEN"                    = "ollama"
    "ANTHROPIC_API_KEY"                       = ""
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" = "1"
    "CLAUDE_CODE_ATTRIBUTION_HEADER"          = "0"
}

foreach ($item in $envSettings.GetEnumerator()) {
    $varKey = $item.Key
    $varVal = $item.Value

    [Environment]::SetEnvironmentVariable($varKey, $varVal, [System.EnvironmentVariableTarget]::Process)
    if ((Test-IsWindows) -and (-not $DryRun)) {
        try {
            [Environment]::SetEnvironmentVariable($varKey, $varVal, [System.EnvironmentVariableTarget]::User)
        }
        catch {
            Write-SetupLog "Konnte '$varKey' nicht dauerhaft im Benutzer-Scope sichern: $_" -Level "Warning"
        }
    }
}
Write-SetupLog "Umgebungsvariablen konfiguriert (ANTHROPIC_BASE_URL=$baseUrl)." -Level "Success"

# --- SCHRITT 7: INTEGRATIONS- & VERBINDUNGSTEST ---
Write-SetupLog "Fuehre Verbindungstests durch..." -Level "Info"

# Test A: Direkte Ollama REST-API Abfrage
try {
    $testPayload = @{
        model  = $Model
        prompt = "Antworte ausschliesslich mit dem Wort 'VERBUNDEN'."
        stream = $false
    } | ConvertTo-Json

    $generateUri = "$baseUrl/api/generate"
    $apiResult = Invoke-RestMethod -Uri $generateUri -Method Post -Body $testPayload -ContentType "application/json" -TimeoutSec 30
    if ($apiResult -and $apiResult.response) {
        $cleanResponse = $apiResult.response.Trim()
        Write-SetupLog "Ollama-Generierungstest erfolgreich! Antwort: '$cleanResponse'" -Level "Success"
    } else {
        Write-SetupLog "Ollama-Test ergab keine gueltige Textantwort." -Level "Warning"
    }
}
catch {
    Write-SetupLog "Ollama-Generierungstest fehlgeschlagen: $_" -Level "Warning"
}

# Test B: CLI Aufruf-Pruefung
if (-not [string]::IsNullOrWhiteSpace($cliPath)) {
    try {
        $cliVersion = & $cliPath --version
        Write-SetupLog "CLI-Versionstest erfolgreich: $cliVersion" -Level "Success"
    }
    catch {
        Write-SetupLog "CLI-Versionstest nicht moeglich: $_" -Level "Warning"
    }
}

# --- SCHRITT 8: ABSCHLUSS-UEBERSICHT ---
Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "                SETUP ERFOLGREICH ABGESCHLOSSEN             " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Ollama-Pfad:      $resolvedOllama" -ForegroundColor White
Write-Host " Modell-Speicher:  $ModelsPath" -ForegroundColor White
Write-Host " Aktives Modell:   $Model" -ForegroundColor White
Write-Host " CLI-Agent:        $(if (-not [string]::IsNullOrWhiteSpace($cliPath)) { $cliPath } else { 'Manuell zu installieren (npm i -g @anthropic-ai/claude-code)' })" -ForegroundColor White
Write-Host " API-Endpunkt:     $baseUrl" -ForegroundColor White
Write-Host " Logdatei:         $LogFile" -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor Green
Write-Host "Starten des Coding-Assistenten mit lokalem Modell:" -ForegroundColor Yellow
if (-not [string]::IsNullOrWhiteSpace($cliPath)) {
    Write-Host "  > claude --model $Model" -ForegroundColor Cyan
    Write-Host "  > cloudcode --model $Model" -ForegroundColor Cyan
} else {
    Write-Host "  > ollama launch claude --model $Model" -ForegroundColor Cyan
}
Write-Host "============================================================`n" -ForegroundColor Green

Write-SetupLog "Setup erfolgreich beendet." -Level "Success"
return
