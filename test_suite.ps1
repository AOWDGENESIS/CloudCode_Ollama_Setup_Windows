[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$scriptPath = Join-Path $PSScriptRoot "CloudCode_Ollama_Setup.ps1"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cloudcode-ollama-test-" + [guid]::NewGuid())
$fakeOllama = Join-Path $tempRoot "ollama.exe"
$logFile = Join-Path $tempRoot "setup.log"
$originalUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$total = 0
$passed = 0

function Assert-Condition {
    param([string]$Name, [bool]$Condition, [string]$Details = "")
    $script:total++
    if ($Condition) {
        $script:passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Name $Details" -ForegroundColor Red
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Set-Content -LiteralPath $fakeOllama -Value "mock" -Encoding ASCII

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-Condition "PowerShell-Syntax ist gueltig" ($parseErrors.Count -eq 0)

    . $scriptPath -OnlyFunctions -LogFile $logFile
    Assert-Condition "Test-IsWindows liefert einen Boolean" (
        (Test-IsWindows) -is [bool])

    $pathDir = Join-Path $tempRoot "bin"
    New-Item -ItemType Directory -Path $pathDir -Force | Out-Null
    $first = Add-DirectoryToPathSafe -TargetDirectory $pathDir -Scope User
    $second = Add-DirectoryToPathSafe -TargetDirectory $pathDir -Scope User
    $normalized = $pathDir.TrimEnd("\", "/")
    $count = @($env:Path -split ";" | Where-Object {
        $_.TrimEnd("\", "/") -ieq $normalized
    }).Count
    Assert-Condition "PATH-Verwaltung funktioniert ohne Duplikat" (
        $first -and $second -and $count -eq 1)
    Assert-Condition "Fehlender Ordner wird sauber abgelehnt" (
        -not (Add-DirectoryToPathSafe -TargetDirectory (
            Join-Path $tempRoot "missing") -Scope User))

    Assert-Condition "Ollama-API offline wird erkannt" (
        -not (Test-OllamaApiReady -BaseUrl "http://127.0.0.1:1"))
    Assert-Condition "Expliziter CLI-Pfad wird gefunden" (
        (Find-CodingCli -ExplicitPath $fakeOllama) -eq $fakeOllama)
    Assert-Condition "Ungültiger CLI-Pfad wird abgelehnt" (
        [string]::IsNullOrWhiteSpace(
            (Find-CodingCli -ExplicitPath (Join-Path $tempRoot "missing.exe"))))

    $output = & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
        -OllamaPath $fakeOllama -ModelsPath (Join-Path $tempRoot "models") `
        -Model "llama3.1" -LogFile $logFile -SkipAdminCheck `
        -SkipModelPull -DryRun 2>&1
    Assert-Condition "DryRun beendet erfolgreich" ($LASTEXITCODE -eq 0)
    Assert-Condition "DryRun schreibt ein Protokoll" (
        (Test-Path $logFile) -and ((Get-Content $logFile -Raw) -like "*Setup erfolgreich beendet*"))
} finally {
    [Environment]::SetEnvironmentVariable("Path", $originalUserPath, "User")
    if (Test-Path $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($passed -eq $total) {
    $resultColor = "Green"
} else {
    $resultColor = "Red"
}
Write-Host "`n$passed von $total Tests bestanden." -ForegroundColor $resultColor
if ($passed -ne $total) { exit 1 }
