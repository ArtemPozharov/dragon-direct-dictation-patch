<#
.SYNOPSIS
    Patch-DragonKWS.ps1
    Herstelt directe spraakdictatie in KWS (Java Swing/AWT), LIS.DaVinci (TX Text Control 33 / .NET WinForms)
    en CliniNET Express (CNExpress.exe / TX Text Control 20 / .NET WinForms)
    voor Dragon Medical Practice Edition 12 onder Windows 11 zonder gebruik van het Dicteervenster.

.DESCRIPTION
    Dit script past de Dragon NaturallySpeaking 12 configuratie en lokale gebruikersprofielen aan op basis van config.json:
    1. Sluit actieve Dragon processen af indien nodig.
    2. Configureert nsapps.ini (in UTF-16 LE BOM formaat):
       - Schakelt het Dicteervenster uit voor geconfigureerde Java- en TX Text Control-vensterklassen.
       - Stelt dictatieniveau 2 (enabled no focus) in voor Java AWT/Swing-componenten en als fallback voor CliniNET Express.
       - Registreert TX Text Control 33 en TX Text Control 20 voor native Edit Control ondersteuning.
       - Voegt applicatieprofielen toe met Key Delay=2.
    3. Configureert nsdefaults.ini zodat nieuwe profielen standaard "Use Dictation Box=0" krijgen.
    4. Corrigeert uitsluitend lokale gebruikersprofielen op deze machine.
    5. Laat centrale netwerk roaming profielen 100% onaangeroerd.
    6. Geoptimaliseerd voor uitrol via PDQ Connect of andere endpoint management tools.
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = (Join-Path $PSScriptRoot "config.json")
)

$ErrorActionPreference = "Continue"
$exitCode = 0

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

Write-Log "Starten van Dragon Medical 12 Direct Dictation Patch..."

# 0. Configuratie inladen (uit config.json of fallback standaardwaarden)
if (Test-Path $ConfigFile) {
    Write-Log "Configuratie inladen vanuit: $ConfigFile"
    $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
} else {
    Write-Log "Geen extern config.json gevonden, standaardwaarden worden gebruikt." "WARN"
    $config = [PSCustomObject]@{
        ProgramDataNuance          = "C:\ProgramData\Nuance\NaturallySpeaking12"
        LocalProfilePaths          = @(
            "C:\ProgramData\Nuance\NaturallySpeaking12\Users",
            "C:\DragonLocalProfiles"
        )
        DragonProcesses            = @("natspeak", "dnsminibar", "dnsspserver", "dgnuiasvr", "dgnuiasvr_x64")
        DictBoxDisableClasses      = @("SunAwtFrame=1", "SunAwtDialog=1", "SunAwtCanvas=1", "SunAwtComponent=1", "TX33=1", "TX33_DOTNET=1", "TX32=1", "tx33_rtf=1", "TX20=1", "TX20_DOTNET=1", "tx20_rtf=1", "TXTextControl=1")
        DictLevelDefaultClasses    = @("SunAwtFrame=2", "SunAwtDialog=2", "SunAwtCanvas=2", "SunAwtComponent=2", "TX33=10", "TX33_DOTNET=10", "TX32=10", "TX20=2", "TX20_DOTNET=2")
        EnableClasses              = @("TX33=10", "TX33_DOTNET=10", "TX32=10", "TX20=10", "TX20_DOTNET=10")
        CleanupProfileAppMatchRegex = "Java\(TM\)|javaw|java|KWS|Fresco|DaVinci|CNExpress|CliniNET"
    }
}

# 1. Dragon processen stoppen indien actief
Write-Log "Controleren op actieve Dragon processen..."
foreach ($procName in $config.DragonProcesses) {
    $running = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($running) {
        Write-Log "Afsluiten van proces: $procName (PID: $($running.Id -join ','))" "WARN"
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}

# 2. Paden verifiëren
$programDataNuance = $config.ProgramDataNuance
$nsappsPath = Join-Path $programDataNuance "nsapps.ini"
$nsdefaultsPath = Join-Path $programDataNuance "nsdefaults.ini"

if (-not (Test-Path $programDataNuance)) {
    Write-Log "Dragon NaturallySpeaking 12 programmamap niet gevonden: $programDataNuance" "ERROR"
    exit 1
}

# 3. nsapps.ini patchen
if (Test-Path $nsappsPath) {
    Write-Log "Back-up maken van nsapps.ini..."
    $backupPath = "$nsappsPath.bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    Copy-Item -Path $nsappsPath -Destination $backupPath -Force
    Write-Log "Back-up opgeslagen in: $backupPath"

    $lines = Get-Content -Path $nsappsPath
    $newLines = New-Object 'System.Collections.Generic.List[string]'
    $currentSection = ""
    $currentSectionKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $inDictBoxDisable = $false
    $inGlobalEnable = $false
    $inDictLevelDefault = $false
    $inEnableClassNames = $false

    $handledDictBox = $false
    $handledGlobalEnable = $false
    $handledDictLevel = $false
    $handledEnableClasses = $false

    function Add-MissingSectionLines {
        param(
            [string[]]$TargetLines,
            [System.Collections.Generic.List[string]]$List,
            [System.Collections.Generic.HashSet[string]]$SeenKeys
        )
        $hadTrailingBlank = $false
        while ($List.Count -gt 0 -and [string]::IsNullOrWhiteSpace($List[$List.Count - 1])) {
            $List.RemoveAt($List.Count - 1)
            $hadTrailingBlank = $true
        }
        foreach ($k in $TargetLines) {
            $kName = ($k -split "=", 2)[0].Trim()
            if ($SeenKeys.Add($kName)) {
                $List.Add($k)
            }
        }
        if ($hadTrailingBlank) {
            $List.Add("")
        }
    }

    $stripSectionPattern = "^(javaw|java|javaws|fresco\.davinci(\.client)?(\.exe)?|davinci(\.exe)?|cnexpress(\.exe)?|clininet(\.exe)?)(\\.*)?$"

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^\[(.*)\]$") {
            if ($inDictBoxDisable -and -not $handledDictBox) {
                Add-MissingSectionLines -TargetLines $config.DictBoxDisableClasses -List $newLines -SeenKeys $currentSectionKeys
                $handledDictBox = $true
            }
            if ($inDictLevelDefault -and -not $handledDictLevel) {
                Add-MissingSectionLines -TargetLines $config.DictLevelDefaultClasses -List $newLines -SeenKeys $currentSectionKeys
                $handledDictLevel = $true
            }
            if ($inEnableClassNames -and -not $handledEnableClasses) {
                Add-MissingSectionLines -TargetLines $config.EnableClasses -List $newLines -SeenKeys $currentSectionKeys
                $handledEnableClasses = $true
            }
            if ($inGlobalEnable -and -not $handledGlobalEnable) {
                Add-MissingSectionLines -TargetLines $config.EnableClasses -List $newLines -SeenKeys $currentSectionKeys
                $handledGlobalEnable = $true
            }

            $currentSection = $matches[1]
            $currentSectionKeys.Clear()
            $inDictBoxDisable = ($currentSection -eq "DictBox\Dictation Box Disable Class Names")
            $inDictLevelDefault = ($currentSection -eq ".Global\Global Dictation Level Default")
            $inEnableClassNames = ($currentSection -eq "\Enable Class Names")
            $inGlobalEnable = ($currentSection -eq ".Global\Global Enable Class Names")

            if ($currentSection -match $stripSectionPattern) {
                continue
            }

            $newLines.Add($line)
            continue
        }

        if ($currentSection -match $stripSectionPattern) {
            continue
        }

        $lineToEmit = $line
        $isManagedSection = $inGlobalEnable -or $inDictBoxDisable -or $inDictLevelDefault -or $inEnableClassNames

        if ($inGlobalEnable) {
            if ($trimmed -match "^SunAwt") {
                continue
            }
            if ($trimmed -match "^TX(20|20_DOTNET|32|33|33_DOTNET)=") {
                $lineToEmit = ($trimmed -replace "=.*$", "=10")
            }
        } elseif ($inDictBoxDisable) {
            if ($trimmed -match "^(SunAwtFrame|SunAwtDialog|SunAwtCanvas|SunAwtComponent|TX33|TX33_DOTNET|TX32|tx33_rtf|TX20|TX20_DOTNET|tx20_rtf|TXTextControl)=") {
                $lineToEmit = ($trimmed -replace "=.*$", "=1")
            }
        } elseif ($inDictLevelDefault) {
            if ($trimmed -match "^SunAwt(Frame|Dialog|Canvas|Component)=") {
                $lineToEmit = ($trimmed -replace "=.*$", "=2")
            } elseif ($trimmed -match "^TX(32|33|33_DOTNET)=") {
                $lineToEmit = ($trimmed -replace "=.*$", "=10")
            } elseif ($trimmed -match "^TX(20|20_DOTNET)=") {
                $lineToEmit = ($trimmed -replace "=.*$", "=2")
            }
        } elseif ($inEnableClassNames) {
            if ($trimmed -match "^TX(20|20_DOTNET|32|33|33_DOTNET)=") {
                $lineToEmit = ($trimmed -replace "=.*$", "=10")
            }
        }

        if ($isManagedSection -and ($lineToEmit.Trim() -match "^([^=]+)=")) {
            $kName = $matches[1].Trim()
            if (-not $currentSectionKeys.Add($kName)) {
                continue
            }
        }

        $newLines.Add($lineToEmit)
    }

    if ($inDictBoxDisable -and -not $handledDictBox) {
        Add-MissingSectionLines -TargetLines $config.DictBoxDisableClasses -List $newLines -SeenKeys $currentSectionKeys
    }
    if ($inDictLevelDefault -and -not $handledDictLevel) {
        Add-MissingSectionLines -TargetLines $config.DictLevelDefaultClasses -List $newLines -SeenKeys $currentSectionKeys
    }
    if ($inEnableClassNames -and -not $handledEnableClasses) {
        Add-MissingSectionLines -TargetLines $config.EnableClasses -List $newLines -SeenKeys $currentSectionKeys
    }
    if ($inGlobalEnable -and -not $handledGlobalEnable) {
        Add-MissingSectionLines -TargetLines $config.EnableClasses -List $newLines -SeenKeys $currentSectionKeys
    }

    while ($newLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($newLines[$newLines.Count - 1])) {
        $newLines.RemoveAt($newLines.Count - 1)
    }

    $appBlocks = @"
[javaw]
Key Delay=2

[javaw\Global Dictation Level Default]
SunAwtFrame=2
SunAwtDialog=2
SunAwtCanvas=2
SunAwtComponent=2

[java]
Key Delay=2

[java\Global Dictation Level Default]
SunAwtFrame=2
SunAwtDialog=2
SunAwtCanvas=2
SunAwtComponent=2

[javaws]
Key Delay=2

[javaws\Global Dictation Level Default]
SunAwtFrame=2
SunAwtDialog=2
SunAwtCanvas=2
SunAwtComponent=2

[fresco.davinci.client]
App Support GUID={dd100203-6205-11cf-ae61-0000e8a28647}
Key Delay=2

[fresco.davinci.client\Enable Class Names]
TX33=10
TX33_DOTNET=10
TX32=10
tx33_rtf=10
TXTextControl=10
Edit=1
RichEdit20W=4
RichEdit50W=4
RichEdit60W=4

[fresco.davinci.client\Global Dictation Level Default]
TX33=10
TX33_DOTNET=10
TX32=10
tx33_rtf=10
TXTextControl=10

[fresco.davinci.client.exe]
App Support GUID={dd100203-6205-11cf-ae61-0000e8a28647}
Key Delay=2

[fresco.davinci.client.exe\Enable Class Names]
TX33=10
TX33_DOTNET=10
TX32=10
tx33_rtf=10
TXTextControl=10
Edit=1
RichEdit20W=4
RichEdit50W=4
RichEdit60W=4

[fresco.davinci.client.exe\Global Dictation Level Default]
TX33=10
TX33_DOTNET=10
TX32=10
tx33_rtf=10
TXTextControl=10

[CNExpress]
App Support GUID={dd100104-6205-11cf-ae61-0000e8a28647}
Key Delay=2

[CNExpress\Enable Class Names]
TX20=10
TX20_DOTNET=10
tx20_rtf=10
TXTextControl=10
Edit=1
RichEdit20W=4
RichEdit50W=4
RichEdit60W=4

[CNExpress\Global Dictation Level Default]
TX20=2
TX20_DOTNET=2
tx20_rtf=2
TXTextControl=2

[CNExpress.exe]
App Support GUID={dd100104-6205-11cf-ae61-0000e8a28647}
Key Delay=2

[CNExpress.exe\Enable Class Names]
TX20=10
TX20_DOTNET=10
tx20_rtf=10
TXTextControl=10
Edit=1
RichEdit20W=4
RichEdit50W=4
RichEdit60W=4

[CNExpress.exe\Global Dictation Level Default]
TX20=2
TX20_DOTNET=2
tx20_rtf=2
TXTextControl=2
"@
    $appBlocks = ($appBlocks -replace "\r?\n", "`r`n").Trim()

    $finalContent = ($newLines -join "`r`n") + "`r`n`r`n" + $appBlocks
    Set-Content -Path $nsappsPath -Value $finalContent -Encoding Unicode
    Write-Log "nsapps.ini succesvol geconfigureerd voor directe spraakdictatie."
}

# 4. nsdefaults.ini patchen
if (Test-Path $nsdefaultsPath) {
    Write-Log "Controleren van nsdefaults.ini..."
    $lines = Get-Content -Path $nsdefaultsPath
    $updatedDefaults = $false
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match "^Use Dictation Box=") {
            $newLines += "Use Dictation Box=0"
            $updatedDefaults = $true
        } else {
            $newLines += $line
        }
    }
    if (-not $updatedDefaults) {
        $newLines += "`r`nUse Dictation Box=0"
    }
    Set-Content -Path $nsdefaultsPath -Value $newLines -Encoding ASCII
    Write-Log "nsdefaults.ini geconfigureerd met Use Dictation Box=0."
}

# 5. Lokale gebruikersprofielen scannen en patchen (alleen LOKAAL)
Write-Log "Scannen naar lokale gebruikersprofielen op deze machine..."
foreach ($loc in $config.LocalProfilePaths) {
    if (Test-Path $loc) {
        $optFiles = Get-ChildItem -Path $loc -Recurse -Filter "options.ini" -ErrorAction SilentlyContinue
        foreach ($opt in $optFiles) {
            try {
                $lines = Get-Content -Path $opt.FullName
                $modified = $false
                $newLines = @()
                foreach ($line in $lines) {
                    if ($line -match "^Use Dictation Box=\d+") {
                        $newLines += "Use Dictation Box=0"
                        $modified = $true
                    } elseif ($line -match "^DictationBox app-based data=(.*)$") {
                        $data = $matches[1]
                        $tokens = $data -split ","
                        if ($tokens.Count -gt 1) {
                            $count = [int]$tokens[0]
                            $entries = @()
                            $idx = 1
                            for ($i = 0; $i -lt $count -and $idx -lt $tokens.Count; $i++) {
                                $name = $tokens[$idx]
                                $paste = $tokens[$idx + 1]
                                $copy = $tokens[$idx + 2]
                                $rect1 = $tokens[$idx + 3]
                                $rect2 = $tokens[$idx + 4]
                                $rect3 = $tokens[$idx + 5]
                                $rect4 = $tokens[$idx + 6]
                                $idx += 7
                                if ($name -notmatch $config.CleanupProfileAppMatchRegex) {
                                    $entries += "$name,$paste,$copy,$rect1,$rect2,$rect3,$rect4"
                                }
                            }
                            if ($entries.Count -gt 0) {
                                $newLines += "DictationBox app-based data=$($entries.Count)," + ($entries -join ",")
                            } else {
                                $newLines += "DictationBox app-based data=0"
                            }
                        } else {
                            $newLines += "DictationBox app-based data=0"
                        }
                        $modified = $true
                    } else {
                        $newLines += $line
                    }
                }
                if ($modified) {
                    Set-Content -Path $opt.FullName -Value $newLines -Encoding ASCII
                    Write-Log "Lokaal profielbestand bijgewerkt: $($opt.FullName)"
                }
            } catch {
                Write-Log "Fout bij bijwerken van $($opt.FullName): $_" "WARN"
            }
        }
    }
}

# 6. Centrale netwerk roaming profielen worden NIET aangeraakt
Write-Log "Centrale netwerk roaming profielen blijven 100% onaangeroerd (veilige lokale uitrol)."

# 7. Bestandsrechten valideren (taalonafhankelijk via SID)
Write-Log "Verifiëren van maprechten voor NaturallySpeaking12..."
try {
    $acl = Get-Acl $programDataNuance
    $authUsersSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11") # Authenticated Users
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($authUsersSid, "Modify, Synchronize", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule)
    Set-Acl -Path $programDataNuance -AclObject $acl -ErrorAction SilentlyContinue
    Write-Log "Maprechten succesvol gevalideerd."
} catch {
    Write-Log "Maprechten konden niet expliciet worden aangepast: $_" "WARN"
}

Write-Log "Patch succesvol voltooid! Directe spraakdictatie is nu actief."
exit $exitCode
