# Dragon Medical Practice Edition 12 - Direct Dictation Patch (KWS, LIS.DaVinci & CliniNET Express)

## Doel van deze patch
Onder recente updates van Windows 11 forceert Dragon Medical Practice Edition 12 (DMPE 12) automatisch het Dicteervenster (Dictation Box) zodra een gebruiker probeert te dicteren in:
1. **KWS (Klinisch Werkstation)**: Java AWT/Swing elektronisch patiëntendossier.
2. **LIS.DaVinci**: Laboratorium Informatie Systeem (gebaseerd op TX Text Control 33 en .NET WinForms).
3. **CliniNET Express (`CNExpress.exe`)**: Elektronisch medisch dossier (gebaseerd op TX Text Control 20 en .NET WinForms).

Gebruikers moeten hierdoor steeds via een pop-upvenster werken en handmatig op "Tekst overzetten" klikken.

Deze patch herstelt directe spraakdictatie voor **alle drie de systemen**: artsen en medewerkers kunnen hun cursor direct in elk tekstveld plaatsen en meteen vloeiend dicteren via de microfoon, zonder tussentijds pop-upvenster.

---

## Bestanden in deze repository
* **`config.json`**: Bevat alle configureerbare paden, procesnamen en vensterklassen. Pas `LocalProfilePaths` aan naar de mappenstructuur van uw eigen organisatie.
* **`Patch-DragonKWS.ps1`**: Het PowerShell-hoofdscript dat de INI-configuraties en lokale profielen bijwerkt.
* **`Install-Patch.bat`**: Batch-wrapper voor handmatige uitvoering of uitrol via softwaredeployment-tools.

---

## Wat deze patch veilig aanpast (puur lokaal op de endpoint PC)
1. **`C:\ProgramData\Nuance\NaturallySpeaking12\nsapps.ini`** (opgeslagen in UTF-16 LE BOM formaat):
   - Maakt automatisch een back-up met tijdstempel: `nsapps.ini.bak_YYYYMMDD_HHMMSS`.
   - Schakelt het Dicteervenster uit voor Java-vensterklassen (`SunAwtFrame`, `SunAwtDialog`, `SunAwtCanvas`, `SunAwtComponent`) én TX Text Control-vensterklassen (`TX33`, `TX33_DOTNET`, `TX32`, `tx33_rtf`, `TX20`, `TX20_DOTNET`, `tx20_rtf`, `TXTextControl`).
   - Stelt dictatieniveau **2** (`enabled no focus`) in voor Java-applicaties en als fallback voor CliniNET Express (`TX20=2`, `TX20_DOTNET=2`).
   - Registreert **TX Text Control 33** (`TX33=10`, `TX33_DOTNET=10`) en **TX Text Control 20** (`TX20=10`, `TX20_DOTNET=10`) onder `[\Enable Class Names]` en `[.Global\Global Enable Class Names]`, waardoor Dragon native Edit Control (`txtext.dll`) ondersteuning gebruikt.
   - Configureert applicatiesecties voor `[javaw]`, `[java]`, `[javaws]`, `[fresco.davinci.client]` / `[fresco.davinci.client.exe]` en `[CNExpress]` / `[CNExpress.exe]` (met `App Support GUID={dd100104-6205-11cf-ae61-0000e8a28647}` en `Key Delay=2`).
2. **`C:\ProgramData\Nuance\NaturallySpeaking12\nsdefaults.ini`**:
   - Stelt `Use Dictation Box=0` in voor toekomstige nieuw aangemaakte profielen.
3. **Lokale gebruikersprofielen (configureerbaar in `config.json`)**:
   - Zet lokaal `Use Dictation Box=0` en schoont eventuele eerdere Java/DaVinci/CliniNET-vermeldingen in `DictationBox app-based data` op.
4. **Centrale netwerk roaming profielen**:
   - Blijven **100% onaangeroerd** voor maximale veiligheid en profielintegriteit.

---

## Veilig uitrollen via PDQ Connect (`app.pdq.com`)

### Aanbevolen stappenplan:
1. **Fase 1: Pilottest op 1 werkstation:**
   - Rol het pakket eerst uit naar een test-pc.
   - Verifieer dat direct dicteren in KWS, DaVinci en CliniNET Express zonder Dicteervenster werkt.
2. **Fase 2: Kleine pilotgroep (3-5 gebruikers):**
   - Rol uit naar een kleine groep gebruikers en verzamel feedback.
3. **Fase 3: Volledige uitrol:**
   - Rol uit naar alle overige werkstations via PDQ Connect.

### Pakket aanmaken in PDQ Connect:
1. Ga in **PDQ Connect** naar **Packages** en klik op **Create Package**.
2. **Package Name**: `Dragon Medical 12 - Direct Dictation Patch`
3. Voeg een **PowerShell Step** toe:
   - Upload `Patch-DragonKWS.ps1` en `config.json` (als extra bestand) of plak de inhoud van `Patch-DragonKWS.ps1` rechtstreeks in **Script Content** (het script gebruikt automatisch veilige fallback-waarden als `config.json` niet aanwezig is).
   - **Run as**: `Local System`
   - **Success Codes**: `0`
4. Klik op **Save & Deploy**.

---

## Terugrolprocedure (Rollback)
Mocht u willen terugkeren naar de vorige situatie op een werkstation:
In de map `C:\ProgramData\Nuance\NaturallySpeaking12\` staat bij elke uitvoering een back-upbestand genaamd `nsapps.ini.bak_YYYYMMDD_HHMMSS`. Hernoem dat bestand terug naar `nsapps.ini`.

---

## Disclaimer & Licentie
Dit project is een onafhankelijke open-source community-oplossing en is op geen enkele wijze gelieerd aan, ondersteund door of geassocieerd met Nuance Communications (Microsoft), nexuzhealth, CliniSys/MIPS, CompuSoft/Corilus of enige specifieke zorginstelling. Deze software wordt geleverd "AS-IS", zonder enige vorm van garantie (zie de bijgevoegde MIT-licentie).
