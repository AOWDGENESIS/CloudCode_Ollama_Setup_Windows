# Cloud Code / Claude Code + Ollama (Windows)

Dieses Paket richtet Ollama für lokale Coding-Agenten ein. Es verwendet
standardmäßig nur Benutzerrechte, verändert den System-PATH nicht und lädt
keine CLI ungefragt aus dem Internet.

## Schnellstart

1. Ollama von [ollama.com/download/windows](https://ollama.com/download/windows)
   installieren und einmal starten.
2. `Setup-Launcher.bat` doppelklicken oder PowerShell öffnen:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\CloudCode_Ollama_Setup.ps1 -Model llama3.1
```

Das Skript erkennt Ollama im PATH und unter
`%LOCALAPPDATA%\Programs\Ollama\ollama.exe`. Modelle werden standardmäßig in
`F:\Ollama\models` gespeichert; ein anderer Ort kann mit `-ModelsPath`
angegeben werden. Falls das Laufwerk F: nicht existiert, wird der Ordner
angelegt oder der Lauf mit einer klaren Fehlermeldung beendet.

## Optionen

```powershell
.\CloudCode_Ollama_Setup.ps1 `
  -OllamaPath "C:\Users\Public\Ollama\ollama.exe" `
  -ModelsPath "D:\Ollama\models" `
  -Model "llama3.1" `
  -InstallCli
```

`-InstallCli` ist ausdrücklich erforderlich, bevor Claude Code installiert
wird. Ohne diesen Schalter bleibt die Einrichtung vollständig lokal und legt
nur die `cloudcode.cmd`-Bridge an. `-SkipModelPull` überspringt den Pull,
`-DryRun` simuliert Änderungen und `-LogFile` ändert den Logpfad.

Nach erfolgreichem Setup stehen diese Umgebungsvariablen für neue Terminals
bereit:

- `ANTHROPIC_BASE_URL=http://127.0.0.1:11434`
- `ANTHROPIC_AUTH_TOKEN=ollama`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
- `CLAUDE_CODE_ATTRIBUTION_HEADER=0`

Starte danach ein neues Terminal und verwende `cloudcode`, `claude` oder
direkt `ollama`. Der Wrapper liegt unter
`%USERPROFILE%\.cloudcode\bin\cloudcode.cmd`.

## Tests

```powershell
.\test_suite.ps1
```

Die Tests prüfen AST-Syntax, PATH-Deduplizierung, CLI-Erkennung, Offline-
Fehlerbehandlung und einen vollständigen DryRun. Sie verwenden nur temporäre
Ordner und funktionieren in Windows PowerShell 5.1 sowie PowerShell 7.

## Dateien

| Datei | Zweck |
| --- | --- |
| `CloudCode_Ollama_Setup.ps1` | Hauptsetup mit Logging, Ollama-Healthcheck und Konfiguration |
| `Setup-Launcher.bat` | Doppelklick-Starter |
| `test_suite.ps1` | Portable automatisierte Tests |
| `mock_ollama_server.py` | Optionaler lokaler API-Mock für eigene Erweiterungstests |
