# =====================================================================
#  SnowFall SS - outil de screenshare du staff SnowFall
#  Version 1.0
#
#  CE QUE FAIT CE SCRIPT (lecture seule) :
#    - liste les Minecraft lances (java/javaw) et lit leur ligne de commande
#    - repere les agents Java (-javaagent) et les DLL chargees dans le jeu
#    - trouve les dossiers mods (jeu lance + launchers connus)
#    - calcule le SHA-1 de chaque .jar et demande a Modrinth s'il est connu
#    - ouvre les jars inconnus et cherche des signatures de cheat
#    - cherche les autoclickers / injecteurs lances ou lances recemment
#    - liste les .jar recents (Telechargements, Bureau, Temp, Corbeille)
#    - ecrit un rapport .txt sur le Bureau
#
#  CE QU'IL NE FAIT PAS :
#    - il ne modifie, ne supprime et ne lance AUCUN fichier
#    - il n'envoie RIEN, sauf les empreintes SHA-1 des jars a api.modrinth.com
#    - il ne lit ni mots de passe, ni tokens, ni cookies, ni comptes
#
#  Lancement en une ligne (PowerShell, idealement en administrateur) :
#    powershell -ExecutionPolicy Bypass -Command "irm 'URL_RAW_DU_SCRIPT' | iex"
#  Ou en local : clic droit sur SnowSS.bat > Executer en tant qu'administrateur
#
#  Le texte est volontairement sans accents : ca evite les caracteres casses
#  quand le script est telecharge avec irm sur Windows PowerShell 5.1.
# =====================================================================

# ---------- Reglages ----------
$SS_Heures        = 48       # fenetre "recent" en heures
$SS_SeuilModrinth = 2000     # en dessous de ce nombre de telechargements, le jar est analyse quand meme
$SS_Reseau        = $true    # $false = pas d'appel a Modrinth
$SS_Version       = '1.0'

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$SS_UserAgent = "SnowFall-SS/$SS_Version"
$SS_Depuis    = (Get-Date).AddHours(-$SS_Heures)
$SS_Admin     = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$SS_Rapport   = New-Object System.Collections.Generic.List[string]
$SS_Alertes   = New-Object System.Collections.Generic.List[object]

# ---------- Signatures ----------
# Paquets Java de clients de triche connus (chemin des .class dans le jar)
$SS_PaquetsCheat = @(
    'meteordevelopment/', 'net/wurstclient/', 'net/ccbluex/', 'org/rusherhack/',
    'thunder/hack/', 'bleach/hack/', 'org/bleachhack/', 'me/zeroeightsix/kami/',
    'com/lambda/client/', 'dev/boze/', 'me/earth/earthhack/', 'me/alpha432/oyvey/',
    'me/deftware/', 'dev/lvstrng/argon/', 'net/impactclient/'
)
# Noms de classes typiques des modules d'un client de triche
$SS_RegexModule = '(?i)(^|/)(KillAura|TriggerBot|AimAssist|AimBot|AutoClicker|CrystalAura|AutoCrystal|AnchorAura|AutoAnchor|AutoHitCrystal|AutoDoubleHand|AutoInventoryTotem|HoverTotem|Scaffold|Nuker|Reach|Velocity|AntiKnockback|NoFall|Flight|Criticals|Tracers|XRay|SelfDestruct|AutoPot|ShieldDisabler|AutoMace|ElytraFly|LegitTotem|AutoWeb)(Module|Hack|Feature|Mod)?\.class$'
# Structure de dossiers typique d'un client de triche
$SS_RegexStructure = '(?i)/modules?/(combat|movement|render|player|misc|world|exploit|ghost|crystal)/'
# Noms de fichiers / mods suspects
$SS_RegexNom = '(?i)(meteor|wurst|aristois|liquidbounce|rusherhack|thunderhack|bleachhack|kami|salhack|inertia|boze|doomsday|argon|prestige|vape|phobos|konas|earthhack|oyvey|shoreline|nullpoint|cornos|coffee.?client|auto.?click|killaura|trigger.?bot|aim.?assist|ghost.?client|cheat|hack|x-?ray|injector|self.?destruct)'
# Mods publics sur Modrinth mais interdits sur la plupart des serveurs
$SS_RegexInterdit = '(?i)(x-?ray|baritone|freecam|seed-?cracker|auto-?click|meteor|wurst|elytra-?fly|auto-?totem)'
# Programmes suspects (autoclickers, injecteurs, outils memoire)
$SS_RegexProgramme = '(?i)(auto.?click|clicker|macro|cheat.?engine|injector|inject|process.?hacker|system.?informer|ghost.?client|jnativehook|xmouse|op.?auto|gs.?auto)'
# Logiciels souris/clavier (peuvent faire des macros)
$SS_RegexSouris = '(?i)^(lghub|lghub_agent|lghub_updater|razer.*|rzsynapse.*|steelseriesgg|icue|bloody\d*|glorious.*|roccat.*|ngenuity.*)\.exe$'
# DLL normales dans le jeu (overlays, pilotes graphiques, natives Minecraft)
$SS_RegexDllNormale = '(?i)(discord|nvidia|nvd3d|nvoglv|nvldumd|nvgpucomp|nvapi|graphics-hook|obs|steam|gameoverlay|overwolf|rtss|medal|amd|atio|atig|igd|intel|razer|mumble|vulkan|afterburner|lwjgl|glfw|openal|jemalloc|jna|jinput|sqlite|zstd|netty|lz4|natives?\\|\\bin\\|bandicam|fraps|tiktok live studio|(opus|rnnoise|speex|lame)4j)'

# ---------- Affichage ----------
function Write-Ligne {
    param([string]$Texte = '', [ConsoleColor]$Couleur = 'Gray')
    Write-Host $Texte -ForegroundColor $Couleur
    $SS_Rapport.Add($Texte)
}
function Write-Titre {
    param([string]$Texte)
    Write-Ligne ''
    Write-Ligne ("=== $Texte ===") Cyan
}
function Add-Alerte {
    param([string]$Niveau, [string]$Quoi, [string]$Detail)
    $SS_Alertes.Add([pscustomobject]@{ Niveau = $Niveau; Quoi = $Quoi; Detail = $Detail })
    $c = 'Yellow'
    if ($Niveau -eq 'ROUGE') { $c = 'Red' }
    Write-Ligne ("  [$Niveau] $Quoi : $Detail") $c
}
function Get-Chemin {
    param($Groupes)
    if ($Groupes[1].Value) { return $Groupes[1].Value }
    return $Groupes[2].Value
}

# ---------- Lecture des jars ----------
function Read-Entree {
    param($Entree)
    $r = New-Object IO.StreamReader($Entree.Open())
    try { return $r.ReadToEnd() } finally { $r.Dispose() }
}

function Read-Archive {
    param($Zip, $Res, [int]$Profondeur)
    foreach ($e in $Zip.Entries) {
        $n = $e.FullName
        if ($n.EndsWith('.class')) {
            $Res.Classes++
            $simple = ($n -split '/')[-1]
            $simple = $simple.Substring(0, $simple.Length - 6).Split('$')[0]
            if ($simple.Length -le 2 -or $simple -cmatch '^[Il1]+$' -or $simple -cmatch '^[O0o]+$') { $Res.Obfusque++ }
            if ($n -match '[^\x20-\x7E]') { $Res.Unicode++ }
            foreach ($pq in $SS_PaquetsCheat) {
                if ($n.StartsWith($pq, [StringComparison]::OrdinalIgnoreCase) -and $Res.Paquets -notcontains $pq) { $Res.Paquets += $pq }
            }
            if ($n -match $SS_RegexModule) {
                $nom = $Matches[2]
                if ($Res.Modules -notcontains $nom) { $Res.Modules += $nom }
            }
            if ($n -match $SS_RegexStructure) { $Res.Structure++ }
            continue
        }
        if ($Profondeur -eq 0) {
            if ($n -eq 'fabric.mod.json' -or $n -eq 'quilt.mod.json') {
                $txt = Read-Entree $e
                $m = [regex]::Match($txt, '"id"\s*:\s*"([^"]+)"')
                if ($m.Success) { $Res.ModId = $m.Groups[1].Value }
                $m = [regex]::Match($txt, '"name"\s*:\s*"([^"]+)"')
                if ($m.Success) { $Res.NomMod = $m.Groups[1].Value }
                $Res.Loader = 'Fabric/Quilt'
                continue
            }
            if ($n -eq 'META-INF/mods.toml' -or $n -eq 'META-INF/neoforge.mods.toml') {
                $txt = Read-Entree $e
                $m = [regex]::Match($txt, 'modId\s*=\s*"([^"]+)"')
                if ($m.Success) { $Res.ModId = $m.Groups[1].Value }
                $m = [regex]::Match($txt, 'displayName\s*=\s*"([^"]+)"')
                if ($m.Success) { $Res.NomMod = $m.Groups[1].Value }
                $Res.Loader = 'Forge/NeoForge'
                continue
            }
            if ($n -eq 'mcmod.info' -or $n -eq 'litemod.json') {
                $txt = Read-Entree $e
                $m = [regex]::Match($txt, '"(?:modid|name)"\s*:\s*"([^"]+)"')
                if ($m.Success -and -not $Res.ModId) { $Res.ModId = $m.Groups[1].Value }
                if (-not $Res.Loader) { $Res.Loader = 'Forge ancien / LiteLoader' }
                continue
            }
            if ($n -eq 'META-INF/MANIFEST.MF') {
                $txt = Read-Entree $e
                if ($txt -match '(?im)^(Premain-Class|Agent-Class|Launcher-Agent-Class):') { $Res.Agent = $true }
                continue
            }
        }
        if ($n.EndsWith('.jar') -and $Profondeur -lt 2) {
            $Res.JarsInclus++
            try {
                $ms = New-Object IO.MemoryStream
                $s = $e.Open(); $s.CopyTo($ms); $s.Dispose()
                $ms.Position = 0
                $sub = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Read)
                Read-Archive $sub $Res ($Profondeur + 1)
                $sub.Dispose(); $ms.Dispose()
            } catch { }
        }
    }
}

function Test-Jar {
    param([string]$Chemin)
    $res = [pscustomobject]@{
        ModId = $null; NomMod = $null; Loader = $null; Agent = $false; Erreur = $null
        Classes = 0; Obfusque = 0; Unicode = 0; Structure = 0; JarsInclus = 0
        Paquets = @(); Modules = @()
    }
    try { $zip = [IO.Compression.ZipFile]::OpenRead($Chemin) } catch { $res.Erreur = 'jar illisible ou corrompu'; return $res }
    try { Read-Archive $zip $res 0 } finally { $zip.Dispose() }
    return $res
}

# ---------- Modrinth ----------
function Get-InfosModrinth {
    param([string[]]$Hashes)
    $resultat = @{}
    if (-not $SS_Reseau -or $Hashes.Count -eq 0) { return $resultat }
    $versions = @{}
    for ($i = 0; $i -lt $Hashes.Count; $i += 100) {
        $lot = @($Hashes[$i..([Math]::Min($i + 99, $Hashes.Count - 1))])
        $corps = @{ hashes = $lot; algorithm = 'sha1' } | ConvertTo-Json -Compress
        try {
            $r = Invoke-RestMethod -Method Post -Uri 'https://api.modrinth.com/v2/version_files' -Body $corps -ContentType 'application/json' -UserAgent $SS_UserAgent -TimeoutSec 30 -ErrorAction Stop
            foreach ($prop in $r.PSObject.Properties) { $versions[$prop.Name] = $prop.Value }
        } catch {
            Write-Ligne ("  Modrinth injoignable : " + $_.Exception.Message) Yellow
            return $resultat
        }
    }
    $ids = @($versions.Values | ForEach-Object { $_.project_id } | Sort-Object -Unique)
    $projets = @{}
    for ($i = 0; $i -lt $ids.Count; $i += 100) {
        $lot = @($ids[$i..([Math]::Min($i + 99, $ids.Count - 1))])
        $json = '["' + ($lot -join '","') + '"]'
        $uri = 'https://api.modrinth.com/v2/projects?ids=' + [Uri]::EscapeDataString($json)
        try {
            foreach ($pr in (Invoke-RestMethod -Uri $uri -UserAgent $SS_UserAgent -TimeoutSec 30 -ErrorAction Stop)) { $projets[$pr.id] = $pr }
        } catch { }
    }
    foreach ($h in @($versions.Keys)) {
        $v = $versions[$h]
        $resultat[$h] = [pscustomobject]@{ Projet = $projets[$v.project_id]; Version = $v.version_number }
    }
    return $resultat
}

# =====================================================================
Clear-Host
Write-Ligne '  ____                      ____ ____  ' Cyan
Write-Ligne ' / ___| _ __   _____      _/ ___/ ___| ' Cyan
Write-Ligne ' \___ \| ''_ \ / _ \ \ /\ / \___ \___ \ ' Cyan
Write-Ligne '  ___) | | | | (_) \ V  V / ___) |__) |' Cyan
Write-Ligne ' |____/|_| |_|\___/ \_/\_/ |____/____/ ' Cyan
Write-Ligne ("  SnowFall SS v$SS_Version - outil de screenshare (lecture seule)") White
Write-Ligne ''
Write-Ligne ("  Date      : {0:dd/MM/yyyy HH:mm:ss}" -f (Get-Date))
Write-Ligne ("  PC        : $env:COMPUTERNAME  /  session : $env:USERNAME")
$os = Get-CimInstance Win32_OperatingSystem
Write-Ligne ("  Windows   : {0} ({1})" -f $os.Caption, $os.Version)
if ($os.LastBootUpTime) { Write-Ligne ("  Demarrage : {0:dd/MM/yyyy HH:mm}" -f $os.LastBootUpTime) }
if ($SS_Admin) { Write-Ligne '  Admin     : oui' Green }
else { Write-Ligne '  Admin     : NON (relance en administrateur pour les verifications BAM / Prefetch)' Yellow }

# ---------- 1. Processus Minecraft ----------
Write-Titre 'Minecraft lance'
$SS_DossiersMods = New-Object System.Collections.Generic.List[object]
$SS_LancementJeu = $null
$procs = @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'")
$nbJeu = 0
foreach ($p in $procs) {
    $cmd = $p.CommandLine
    if ($cmd -and $cmd -notmatch '(?i)minecraft|fabric|forge|quilt|lunar|feather|badlion|labymod') {
        Write-Ligne ("  PID {0} : programme Java qui n'est pas Minecraft, ignore" -f $p.ProcessId) DarkGray
        continue
    }
    $nbJeu++
    Write-Ligne ("  PID {0}  {1}" -f $p.ProcessId, $p.ExecutablePath) White
    if ($p.CreationDate) {
        Write-Ligne ("    Lance le {0:dd/MM/yyyy HH:mm:ss}" -f $p.CreationDate)
        if (-not $SS_LancementJeu -or $p.CreationDate -lt $SS_LancementJeu) { $SS_LancementJeu = $p.CreationDate }
    }
    if (-not $cmd) {
        Write-Ligne '    Ligne de commande illisible : relance le scan en administrateur.' Yellow
        continue
    }
    $m = [regex]::Match($cmd, '--version\s+(\S+)')
    if ($m.Success) { Write-Ligne ("    Version   : " + $m.Groups[1].Value) }
    $m = [regex]::Match($cmd, '--gameDir\s+(?:"([^"]+)"|(\S+))')
    if ($m.Success) {
        $gd = Get-Chemin $m.Groups
        Write-Ligne "    Dossier   : $gd"
        $SS_DossiersMods.Add([pscustomobject]@{ Chemin = (Join-Path $gd 'mods'); Jeu = $true })
        $SS_DossiersMods.Add([pscustomobject]@{ Chemin = (Join-Path $gd 'resourcepacks'); Jeu = $true; Packs = $true })
    }
    foreach ($a in [regex]::Matches($cmd, '-javaagent:([^"\r\n]*?\.jar)')) {
        $chemin = $a.Groups[1].Value
        $fa = Get-Item -LiteralPath $chemin -Force
        if ((Split-Path $chemin -Leaf) -eq 'theseus.jar' -and $chemin -match '\\\.tmp\w+\\theseus\.jar$' -and $fa -and $fa.Length -lt 2MB) {
            Write-Ligne "    Agent     : $chemin (agent normal du Modrinth App)" DarkGreen
            continue
        }
        $niv = 'ORANGE'
        if ($chemin -match '(?i)\\(temp|tmp|downloads|telechargements|t.l.chargements|desktop|bureau)\\') { $niv = 'ROUGE' }
        Add-Alerte $niv 'Agent Java charge au lancement' $chemin
    }
    foreach ($a in [regex]::Matches($cmd, '(?i)-Dfabric\.addMods=(?:"([^"]+)"|(\S+))')) {
        $extra = Get-Chemin $a.Groups
        Add-Alerte 'ORANGE' 'Mods charges depuis un autre dossier' $extra
        foreach ($x in ($extra -split ';')) { if ($x) { $SS_DossiersMods.Add([pscustomobject]@{ Chemin = $x; Jeu = $true }) } }
    }
    # DLL chargees dans le jeu
    if ($p.ExecutablePath) {
        $javaDir = Split-Path (Split-Path $p.ExecutablePath -Parent) -Parent
        $gp = Get-Process -Id $p.ProcessId
        if ($gp -and $gp.Modules) {
            $dlls = @($gp.Modules | Where-Object {
                $_.FileName -and
                -not $_.FileName.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase) -and
                -not $_.FileName.StartsWith($javaDir, [StringComparison]::OrdinalIgnoreCase) -and
                $_.FileName -notmatch $SS_RegexDllNormale
            })
            if ($dlls.Count -eq 0) { Write-Ligne '    DLL       : rien d''anormal' DarkGreen }
            foreach ($d in $dlls) { Add-Alerte 'ORANGE' 'DLL inhabituelle dans le jeu' $d.FileName }
        } else {
            Write-Ligne '    DLL       : liste illisible (relance en administrateur)' Yellow
        }
    }
}
if ($nbJeu -eq 0) { Write-Ligne '  Aucun Minecraft lance. Demande au joueur de garder son jeu ouvert pendant le scan.' Yellow }

# ---------- 2. Dossiers mods ----------
$motifs = @(
    "$env:APPDATA\.minecraft\mods",
    "$env:APPDATA\.minecraft\resourcepacks",
    "$env:APPDATA\ModrinthApp\profiles\*\mods",
    "$env:APPDATA\com.modrinth.theseus\profiles\*\mods",
    "$env:APPDATA\PrismLauncher\instances\*\.minecraft\mods",
    "$env:APPDATA\PrismLauncher\instances\*\minecraft\mods",
    "$env:APPDATA\.tlauncher\legacy\Minecraft\game\mods",
    "$env:APPDATA\.feather\user-mods\*",
    "$env:USERPROFILE\curseforge\minecraft\Instances\*\mods",
    "$env:USERPROFILE\.lunarclient\profiles\*\*\mods"
)
foreach ($mo in $motifs) {
    foreach ($it in @(Get-Item -Path $mo -Force | Where-Object { $_.PSIsContainer })) {
        $SS_DossiersMods.Add([pscustomobject]@{ Chemin = $it.FullName; Jeu = $false; Packs = ($it.Name -eq 'resourcepacks') })
    }
}
$vus = @{}
$dossiers = @()
foreach ($d in $SS_DossiersMods) {
    if (-not (Test-Path -LiteralPath $d.Chemin)) { continue }
    $cle = (Resolve-Path -LiteralPath $d.Chemin).ProviderPath.TrimEnd('\').ToLower()
    if ($vus.ContainsKey($cle)) { continue }
    $vus[$cle] = $true
    $dossiers += [pscustomobject]@{ Chemin = (Resolve-Path -LiteralPath $d.Chemin).ProviderPath; Jeu = $d.Jeu; Packs = [bool]$d.Packs }
}

Write-Titre 'Dossiers scannes'
if ($dossiers.Count -eq 0) { Write-Ligne '  Aucun dossier mods trouve.' Yellow }
$jars = @()
foreach ($d in $dossiers) {
    $tag = ''
    if ($d.Jeu) { $tag = '  (jeu lance)' }
    if ($d.Packs) {
        $packs = @(Get-ChildItem -LiteralPath $d.Chemin -Force)
        Write-Ligne ("  {0}  [{1} pack(s)]{2}" -f $d.Chemin, $packs.Count, $tag)
        foreach ($pk in $packs) { if ($pk.Name -match '(?i)x-?ray|ore.?(esp|finder)|see.?through') { Add-Alerte 'ORANGE' 'Pack de textures X-Ray' $pk.FullName } }
        continue
    }
    $fichiers = @(Get-ChildItem -LiteralPath $d.Chemin -Recurse -Depth 1 -File -Force)
    $lesJars = @($fichiers | Where-Object { $_.Extension -eq '.jar' })
    Write-Ligne ("  {0}  [{1} jar(s)]{2}" -f $d.Chemin, $lesJars.Count, $tag)
    foreach ($f in $fichiers) {
        if ($f.Extension -match '(?i)^\.(exe|dll|zip|rar|7z|class|bat|cmd|ps1|vbs)$') { Add-Alerte 'ORANGE' 'Fichier bizarre dans un dossier mods' $f.FullName }
    }
    foreach ($f in $lesJars) {
        $jars += [pscustomobject]@{ Nom = $f.Name; Chemin = $f.FullName; Taille = $f.Length; Modif = $f.LastWriteTime; Jeu = $d.Jeu; Sha1 = $null }
    }
}

# ---------- 3. Analyse des jars ----------
Write-Titre ("Analyse des mods ({0} jar(s))" -f $jars.Count)
foreach ($j in $jars) { $j.Sha1 = (Get-FileHash -LiteralPath $j.Chemin -Algorithm SHA1).Hash.ToLower() }
$hashes = @($jars | Where-Object { $_.Sha1 } | ForEach-Object { $_.Sha1 } | Sort-Object -Unique)
if ($SS_Reseau -and $hashes.Count -gt 0) { Write-Ligne '  Verification aupres de Modrinth...' DarkGray }
$modrinth = Get-InfosModrinth $hashes

$dossierCourant = $null
foreach ($j in ($jars | Sort-Object Chemin)) {
    $dossierJar = Split-Path $j.Chemin -Parent
    if ($dossierJar -ne $dossierCourant) { Write-Ligne ''; Write-Ligne ("  -- $dossierJar") White; $dossierCourant = $dossierJar }

    $recent = ''
    if ($j.Modif -ge $SS_Depuis) { $recent = ("  [modifie le {0:dd/MM HH:mm}]" -f $j.Modif) }
    if ($j.Jeu -and $SS_LancementJeu -and $j.Modif -gt $SS_LancementJeu) {
        Add-Alerte 'ORANGE' 'Jar modifie APRES le lancement du jeu' $j.Chemin
    }

    $info = $null
    if ($j.Sha1 -and $modrinth.ContainsKey($j.Sha1)) { $info = $modrinth[$j.Sha1] }
    $connu = ($info -and $info.Projet)
    if ($connu -and $info.Projet.downloads -ge $SS_SeuilModrinth) {
        Write-Ligne ("  OK       {0}  ->  {1} {2} ({3:N0} telechargements){4}" -f $j.Nom, $info.Projet.title, $info.Version, $info.Projet.downloads, $recent) DarkGreen
        if ($info.Projet.slug -match $SS_RegexInterdit) { Add-Alerte 'ORANGE' 'Mod public mais interdit sur la plupart des serveurs' ("{0} ({1})" -f $j.Nom, $info.Projet.title) }
        continue
    }

    $a = Test-Jar $j.Chemin
    $niveau = $null
    $raisons = New-Object System.Collections.Generic.List[string]

    if ($a.Paquets.Count -gt 0) { $niveau = 'ROUGE'; $raisons.Add('code d''un client de triche connu (' + ($a.Paquets -join ', ') + ')') }
    if ($a.Modules.Count -ge 3 -or ($a.Modules.Count -ge 1 -and $a.Structure -ge 3)) {
        $niveau = 'ROUGE'; $raisons.Add('modules de triche (' + ($a.Modules -join ', ') + ')')
    } elseif ($a.Modules.Count -ge 1) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add('nom de classe suspect (' + ($a.Modules -join ', ') + ')')
    } elseif ($a.Structure -ge 3) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add('structure de client de triche (modules/combat...)')
    }
    if ($a.Classes -ge 30 -and ($a.Obfusque / $a.Classes) -ge 0.4) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add(("code obfusque ({0:N0} % des classes)" -f (100 * $a.Obfusque / $a.Classes)))
    }
    if ($a.Unicode -gt 0) { if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add('noms de classes avec des caracteres bizarres') }
    if ($a.Agent) { if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add('jar fait pour etre injecte (agent Java)') }
    if ($a.Erreur) { if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add($a.Erreur) }
    elseif (-not $a.ModId) { if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add('aucun fichier de mod (ni fabric.mod.json ni mods.toml)') }
    if (("{0} {1} {2}" -f $j.Nom, $a.ModId, $a.NomMod) -match $SS_RegexNom) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $raisons.Add("nom suspect ('" + $Matches[1] + "')")
    }

    $source = 'pas sur Modrinth (peut venir de CurseForge ou d''ailleurs)'
    if ($connu) { $source = ("sur Modrinth mais peu telecharge : {0} ({1:N0})" -f $info.Projet.title, $info.Projet.downloads) }
    $ident = ''
    if ($a.ModId) { $ident = " [id: $($a.ModId)]" }

    if ($niveau) {
        Add-Alerte $niveau ($j.Nom + $ident) (($raisons -join ' ; ') + ' - ' + $source + $recent)
    } else {
        Write-Ligne ("  ?        {0}{1}  ->  {2}, rien de suspect dedans{3}" -f $j.Nom, $ident, $source, $recent) Gray
    }
}

# ---------- 4. Programmes ----------
Write-Titre 'Programmes lances'
$rienProg = $true
foreach ($pr in @(Get-CimInstance Win32_Process)) {
    if ($pr.Name -match $SS_RegexProgramme -or $pr.ExecutablePath -match $SS_RegexProgramme) {
        Add-Alerte 'ORANGE' 'Programme suspect lance' ("{0} (PID {1}) {2}" -f $pr.Name, $pr.ProcessId, $pr.ExecutablePath)
        $rienProg = $false
    } elseif ($pr.Name -match $SS_RegexSouris) {
        Write-Ligne ("  Info : logiciel souris/clavier (macros possibles) : {0}" -f $pr.Name) DarkYellow
    }
}
foreach ($gp in @(Get-Process | Where-Object { $_.MainWindowTitle })) {
    if ($gp.MainWindowTitle -match $SS_RegexProgramme) {
        Add-Alerte 'ORANGE' 'Fenetre suspecte ouverte' ("'{0}' ({1}.exe)" -f $gp.MainWindowTitle, $gp.ProcessName)
        $rienProg = $false
    }
}
if ($rienProg) { Write-Ligne '  Aucun autoclicker / injecteur connu en cours.' DarkGreen }

# ---------- 5. Programmes lances recemment (admin) ----------
Write-Titre ("Programmes lances ces $SS_Heures dernieres heures")
if (-not $SS_Admin) {
    Write-Ligne '  Saute : il faut lancer le scan en administrateur.' Yellow
} else {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings\$sid"
    if (-not (Test-Path $cle)) { $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings\$sid" }
    $entrees = @()
    $props = Get-ItemProperty -Path $cle
    if ($props) {
        foreach ($pp in $props.PSObject.Properties) {
            if ($pp.Value -is [byte[]] -and $pp.Value.Length -ge 8) {
                $date = [DateTime]::FromFileTime([BitConverter]::ToInt64($pp.Value, 0))
                if ($date -ge $SS_Depuis) { $entrees += [pscustomobject]@{ Date = $date; Exe = ($pp.Name -replace '^\\Device\\HarddiskVolume\d+', '') } }
            }
        }
    }
    Write-Ligne ("  BAM (registre Windows) : {0} programme(s)" -f $entrees.Count)
    foreach ($en in ($entrees | Sort-Object Date -Descending | Select-Object -First 40)) {
        if ($en.Exe -match $SS_RegexProgramme) { Add-Alerte 'ORANGE' 'Programme suspect lance recemment' ("{0:dd/MM HH:mm}  {1}" -f $en.Date, $en.Exe) }
        else { Write-Ligne ("    {0:dd/MM HH:mm}  {1}" -f $en.Date, $en.Exe) DarkGray }
    }
    $pf = @(Get-ChildItem -Path "$env:windir\Prefetch" -Filter *.pf -Force | Where-Object { $_.LastWriteTime -ge $SS_Depuis -and $_.Name -match $SS_RegexProgramme })
    foreach ($f in $pf) { Add-Alerte 'ORANGE' 'Prefetch : programme suspect lance' ("{0:dd/MM HH:mm}  {1}" -f $f.LastWriteTime, $f.Name) }
    if ($pf.Count -eq 0) { Write-Ligne '  Prefetch : rien de suspect.' DarkGreen }
}

# ---------- 6. Jars recents ----------
Write-Titre ("Fichiers .jar / .exe recents (moins de $SS_Heures h)")
$telech = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}'
if (-not $telech) { $telech = "$env:USERPROFILE\Downloads" }
$lieux = @($telech, [Environment]::GetFolderPath('Desktop'), $env:TEMP, [Environment]::GetFolderPath('MyDocuments')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique
$rienRecent = $true
foreach ($l in $lieux) {
    $rec = @(Get-ChildItem -LiteralPath $l -Recurse -Depth 2 -File -Force | Where-Object { ($_.Extension -eq '.jar' -or $_.Extension -eq '.exe') -and $_.LastWriteTime -ge $SS_Depuis -and $_.FullName -notmatch '(?i)\\(lwjgl|jna|minecraft|modrinth|curseforge|prismlauncher)' })
    foreach ($f in ($rec | Sort-Object LastWriteTime -Descending | Select-Object -First 25)) {
        $rienRecent = $false
        $txt = "{0:dd/MM HH:mm}  {1}  ({2:N0} Ko)" -f $f.LastWriteTime, $f.FullName, ($f.Length / 1KB)
        if ($f.Name -match $SS_RegexNom -or $f.Name -match $SS_RegexProgramme) { Add-Alerte 'ORANGE' 'Fichier recent au nom suspect' $txt }
        else { Write-Ligne "  $txt" DarkGray }
    }
}
if ($rienRecent) { Write-Ligne '  Rien.' DarkGreen }

# ---------- 7. Corbeille ----------
Write-Titre ("Corbeille (.jar / .exe / .dll supprimes depuis $SS_Heures h)")
$rienCorb = $true
try {
    $sh = New-Object -ComObject Shell.Application
    $rb = $sh.Namespace(10)
    foreach ($it in @($rb.Items())) {
        $ext = [IO.Path]::GetExtension($it.Path).ToLower()
        if ($ext -ne '.jar' -and $ext -ne '.exe' -and $ext -ne '.dll') { continue }
        $quand = $it.ExtendedProperty('System.Recycle.DateDeleted')
        $origine = $it.ExtendedProperty('System.Recycle.DeletedFrom')
        if ($quand -and ([DateTime]$quand) -lt $SS_Depuis) { continue }
        $rienCorb = $false
        $txt = "{0}  {1}  (venait de {2})" -f $quand, $it.Name, $origine
        if ("$origine" -match '(?i)\\mods' -or $it.Name -match $SS_RegexNom -or $it.Name -match $SS_RegexProgramme) { Add-Alerte 'ORANGE' 'Fichier supprime recemment' $txt }
        else { Write-Ligne "  $txt" DarkGray }
    }
} catch { Write-Ligne '  Corbeille illisible.' Yellow }
if ($rienCorb) { Write-Ligne '  Rien.' DarkGreen }

# ---------- Resume ----------
Write-Titre 'Resume'
$rouges = @($SS_Alertes | Where-Object { $_.Niveau -eq 'ROUGE' })
$oranges = @($SS_Alertes | Where-Object { $_.Niveau -eq 'ORANGE' })
foreach ($al in $rouges)  { Write-Ligne ("  [ROUGE]  {0} : {1}" -f $al.Quoi, $al.Detail) Red }
foreach ($al in $oranges) { Write-Ligne ("  [ORANGE] {0} : {1}" -f $al.Quoi, $al.Detail) Yellow }
Write-Ligne ''
if ($rouges.Count -gt 0)      { Write-Ligne ("  VERDICT : SUSPECT  ({0} rouge(s), {1} orange(s))" -f $rouges.Count, $oranges.Count) Red }
elseif ($oranges.Count -gt 0) { Write-Ligne ("  VERDICT : A VERIFIER  ({0} orange(s)) - regarde chaque ligne orange avec le joueur" -f $oranges.Count) Yellow }
else                          { Write-Ligne '  VERDICT : RIEN DE SUSPECT TROUVE' Green }
Write-Ligne '  Un scan propre ne prouve pas a 100 % que le joueur est clean : regarde aussi son ecran.' DarkGray

$SS_Fichier = Join-Path ([Environment]::GetFolderPath('Desktop')) ("SnowSS_{0:yyyy-MM-dd_HH-mm}.txt" -f (Get-Date))
try {
    [IO.File]::WriteAllLines($SS_Fichier, $SS_Rapport, (New-Object Text.UTF8Encoding $true))
    Write-Host ''
    Write-Host "  Rapport enregistre : $SS_Fichier" -ForegroundColor Cyan
} catch { }

if (-not $env:SNOWSS_NOPAUSE) { try { [void](Read-Host '  Appuie sur Entree pour fermer') } catch { } }
