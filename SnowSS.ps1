# =====================================================================
#  SnowFall SS v2.0 - outil de screenshare du staff SnowFall
#
#  CE QUE FAIT CE SCRIPT (lecture seule) :
#    - ouvre une fenetre qui affiche le resultat du scan par categorie
#    - Minecraft lance : version, dossier, agents Java, DLL chargees
#    - mods : SHA-1 de chaque jar compare a Modrinth, jars inconnus fouilles
#    - programmes : autoclickers / injecteurs ouverts ou lances recemment
#    - cles USB : branchees maintenant (contenu scanne) + historique Windows
#    - fichiers .jar / .exe recents et Corbeille
#    - rapport .txt enregistre sur le Bureau
#
#  CE QU'IL NE FAIT PAS :
#    - il ne modifie, ne supprime et ne lance AUCUN fichier
#    - il n'envoie RIEN, sauf les empreintes SHA-1 des jars a api.modrinth.com
#    - il ne lit ni mots de passe, ni tokens, ni cookies, ni comptes
#
#  Lancement (PowerShell, idealement en administrateur) :
#    powershell -ExecutionPolicy Bypass -Command "irm 'URL_RAW_DU_SCRIPT' | iex"
#  En local : double-clic sur SnowSS.bat
#
#  Le fichier est en UTF-8 SANS BOM (un BOM casse "irm | iex").
# =====================================================================

# ---------- Reglages ----------
$SS_Heures        = 48       # fenetre "recent" en heures
$SS_SeuilModrinth = 2000     # en dessous, le jar est fouille meme s'il est sur Modrinth
$SS_Reseau        = $true    # $false = pas d'appel a Modrinth
$SS_Version       = '2.0'

$ErrorActionPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:SS_UserAgent   = "SnowFall-SS/$SS_Version"
$script:SS_Depuis      = (Get-Date).AddHours(-$SS_Heures)
$script:SS_Admin       = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:SS_Resultats   = New-Object System.Collections.Generic.List[object]
$script:SS_LancementJeu = $null
$script:SS_Usb         = @()
$script:SS_Fichier     = $null
$script:VerdictTexte   = ''
$script:ScanEnCours    = $false
$script:Annule         = $false
$script:UI             = $null

$SS_Categories = [ordered]@{
    Resume     = 'Résumé'
    Systeme    = 'Système'
    Minecraft  = 'Minecraft'
    Mods       = 'Mods'
    Programmes = 'Programmes'
    Usb        = 'Clés USB'
    Fichiers   = 'Fichiers récents'
    Corbeille  = 'Corbeille'
}

# ---------- Signatures ----------
$SS_PaquetsCheat = @(
    'meteordevelopment/', 'net/wurstclient/', 'net/ccbluex/', 'org/rusherhack/',
    'thunder/hack/', 'bleach/hack/', 'org/bleachhack/', 'me/zeroeightsix/kami/',
    'com/lambda/client/', 'dev/boze/', 'me/earth/earthhack/', 'me/alpha432/oyvey/',
    'me/deftware/', 'dev/lvstrng/argon/', 'net/impactclient/'
)
$SS_RegexModule    = '(?i)(^|/)(KillAura|TriggerBot|AimAssist|AimBot|AutoClicker|CrystalAura|AutoCrystal|AnchorAura|AutoAnchor|AutoHitCrystal|AutoDoubleHand|AutoInventoryTotem|HoverTotem|Scaffold|Nuker|Reach|Velocity|AntiKnockback|NoFall|Flight|Criticals|Tracers|XRay|SelfDestruct|AutoPot|ShieldDisabler|AutoMace|ElytraFly|LegitTotem|AutoWeb)(Module|Hack|Feature|Mod)?\.class$'
$SS_RegexStructure = '(?i)/modules?/(combat|movement|render|player|misc|world|exploit|ghost|crystal)/'
$SS_RegexNom       = '(?i)(meteor|wurst|aristois|liquidbounce|rusherhack|thunderhack|bleachhack|kami|salhack|inertia|boze|doomsday|argon|prestige|vape|phobos|konas|earthhack|oyvey|shoreline|nullpoint|cornos|coffee.?client|auto.?click|killaura|trigger.?bot|aim.?assist|ghost.?client|cheat|hack|x-?ray|injector|self.?destruct)'
$SS_RegexInterdit  = '(?i)(x-?ray|baritone|freecam|seed-?cracker|auto-?click|meteor|wurst|elytra-?fly|auto-?totem)'
$SS_RegexProgramme = '(?i)(auto.?click|clicker|macro|cheat.?engine|injector|inject|process.?hacker|system.?informer|ghost.?client|jnativehook|xmouse|op.?auto|gs.?auto)'
$SS_RegexSouris    = '(?i)^(lghub|lghub_agent|lghub_updater|razer.*|rzsynapse.*|steelseriesgg|icue|bloody\d*|glorious.*|roccat.*|ngenuity.*)\.exe$'
$SS_RegexDllNormale = '(?i)(discord|nvidia|nvd3d|nvoglv|nvldumd|nvgpucomp|nvapi|graphics-hook|obs|steam|gameoverlay|overwolf|rtss|medal|amd|atio|atig|igd|intel|razer|mumble|vulkan|afterburner|lwjgl|glfw|openal|jemalloc|jna|jinput|sqlite|zstd|netty|lz4|natives?\\|\\bin\\|bandicam|fraps|tiktok live studio|(opus|rnnoise|speex|lame)4j)'
$SS_RegexJeu       = '(?i)minecraft|fabric|forge|quilt|lunar|feather|badlion|labymod'

# =====================================================================
#  Outils
# =====================================================================
function Add-Res {
    param([string]$Cat, [string]$Niveau, [string]$Titre, [string]$Detail = '', [string]$Chemin = '')
    $script:SS_Resultats.Add([pscustomobject]@{ Cat = $Cat; Niveau = $Niveau; Titre = $Titre; Detail = $Detail; Chemin = $Chemin })
    if (-not $script:UI) {
        $c = 'Gray'
        if ($Niveau -eq 'ROUGE') { $c = 'Red' } elseif ($Niveau -eq 'ORANGE') { $c = 'Yellow' } elseif ($Niveau -eq 'OK') { $c = 'DarkGreen' }
        Write-Host ("  [{0,-6}] {1}  {2}" -f $Niveau, $Titre, $Detail) -ForegroundColor $c
    }
}

function Set-Etape {
    param([int]$Pct, [string]$Texte)
    if ($script:Annule) { throw 'SCAN_ANNULE' }
    if ($script:UI) {
        $script:UI.Barre.Value = [Math]::Min(100, [Math]::Max(0, $Pct))
        $script:UI.Statut.Text = $Texte
        Update-Navigation
        [Windows.Forms.Application]::DoEvents()
    } elseif ($Texte -notmatch '\(\d+/\d+\)|^Analyse de la cl') {
        Write-Host ''
        Write-Host "=== $Texte ===" -ForegroundColor Cyan
    }
}

function Invoke-Pompe {
    if ($script:Annule) { throw 'SCAN_ANNULE' }
    if ($script:UI) { [Windows.Forms.Application]::DoEvents() }
}

function Format-Taille {
    param([double]$o)
    if ($o -ge 1GB) { return ('{0:N1} Go' -f ($o / 1GB)) }
    if ($o -ge 1MB) { return ('{0:N1} Mo' -f ($o / 1MB)) }
    return ('{0:N0} Ko' -f ($o / 1KB))
}

function Format-Date {
    param($d)
    if ($d) { return ('{0:dd/MM/yyyy HH:mm}' -f $d) }
    return '?'
}

function Format-Duree {
    param([TimeSpan]$t)
    if ($t.TotalHours -lt 1) { return ('{0} min' -f [int]$t.TotalMinutes) }
    if ($t.TotalDays -lt 1) { return ('{0} h {1} min' -f [int][Math]::Floor($t.TotalHours), $t.Minutes) }
    return ('{0} j {1} h' -f $t.Days, $t.Hours)
}

function Get-Chemin {
    param($Groupes)
    if ($Groupes[1].Value) { return $Groupes[1].Value }
    return $Groupes[2].Value
}

function Test-SurUsb {
    param([string]$Chemin)
    if (-not $Chemin -or $Chemin.Length -lt 2 -or $script:SS_Usb.Count -eq 0) { return $false }
    $l = $Chemin.Substring(0, 2).ToUpper()
    foreach ($u in $script:SS_Usb) { if ($u.Lettre -eq $l) { return $true } }
    return $false
}

# =====================================================================
#  Lecture des jars
# =====================================================================
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
                continue
            }
            if ($n -eq 'META-INF/mods.toml' -or $n -eq 'META-INF/neoforge.mods.toml') {
                $txt = Read-Entree $e
                $m = [regex]::Match($txt, 'modId\s*=\s*"([^"]+)"')
                if ($m.Success) { $Res.ModId = $m.Groups[1].Value }
                $m = [regex]::Match($txt, 'displayName\s*=\s*"([^"]+)"')
                if ($m.Success) { $Res.NomMod = $m.Groups[1].Value }
                continue
            }
            if ($n -eq 'mcmod.info' -or $n -eq 'litemod.json') {
                $txt = Read-Entree $e
                $m = [regex]::Match($txt, '"(?:modid|name)"\s*:\s*"([^"]+)"')
                if ($m.Success -and -not $Res.ModId) { $Res.ModId = $m.Groups[1].Value }
                continue
            }
            if ($n -eq 'META-INF/MANIFEST.MF') {
                $txt = Read-Entree $e
                if ($txt -match '(?im)^(Premain-Class|Agent-Class|Launcher-Agent-Class):') { $Res.Agent = $true }
                continue
            }
        }
        if ($n.EndsWith('.jar') -and $Profondeur -lt 2) {
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
        ModId = $null; NomMod = $null; Agent = $false; Erreur = $null
        Classes = 0; Obfusque = 0; Unicode = 0; Structure = 0
        Paquets = @(); Modules = @()
    }
    try { $zip = [IO.Compression.ZipFile]::OpenRead($Chemin) } catch { $res.Erreur = 'jar illisible ou corrompu'; return $res }
    try { Read-Archive $zip $res 0 } finally { $zip.Dispose() }
    return $res
}

# Renvoie Niveau (ROUGE / ORANGE / $null) + raisons
function Get-AnalyseJar {
    param([string]$Chemin, [string]$Nom)
    $a = Test-Jar $Chemin
    $niveau = $null
    $r = New-Object System.Collections.Generic.List[string]
    if ($a.Paquets.Count -gt 0) { $niveau = 'ROUGE'; $r.Add('code d''un client de triche connu (' + ($a.Paquets -join ', ') + ')') }
    if ($a.Modules.Count -ge 3 -or ($a.Modules.Count -ge 1 -and $a.Structure -ge 3)) {
        $niveau = 'ROUGE'; $r.Add('modules de triche : ' + ($a.Modules -join ', '))
    } elseif ($a.Modules.Count -ge 1) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add('nom de classe suspect : ' + ($a.Modules -join ', '))
    } elseif ($a.Structure -ge 3) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add('structure de client de triche (modules/combat...)')
    }
    if ($a.Classes -ge 30 -and ($a.Obfusque / $a.Classes) -ge 0.4) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add(('code obfusqué ({0:N0} % des classes)' -f (100 * $a.Obfusque / $a.Classes)))
    }
    if ($a.Unicode -gt 0) { if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add('noms de classes avec des caractères bizarres') }
    if ($a.Agent) { if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add('jar fait pour être injecté (agent Java)') }
    if ($a.Erreur) { if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add($a.Erreur) }
    elseif (-not $a.ModId) { if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add('aucun fichier de mod (ni fabric.mod.json ni mods.toml)') }
    if (('{0} {1} {2}' -f $Nom, $a.ModId, $a.NomMod) -match $SS_RegexNom) {
        if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add("nom suspect ('" + $Matches[1] + "')")
    }
    return [pscustomobject]@{ Niveau = $niveau; Raisons = ($r -join ' ; '); ModId = $a.ModId }
}

# =====================================================================
#  Modrinth
# =====================================================================
function Get-InfosModrinth {
    param([string[]]$Hashes)
    $resultat = @{}
    if (-not $SS_Reseau -or $Hashes.Count -eq 0) { return $resultat }
    $versions = @{}
    for ($i = 0; $i -lt $Hashes.Count; $i += 100) {
        $lot = @($Hashes[$i..([Math]::Min($i + 99, $Hashes.Count - 1))])
        $corps = @{ hashes = $lot; algorithm = 'sha1' } | ConvertTo-Json -Compress
        try {
            $r = Invoke-RestMethod -Method Post -Uri 'https://api.modrinth.com/v2/version_files' -Body $corps -ContentType 'application/json' -UserAgent $script:SS_UserAgent -TimeoutSec 30 -ErrorAction Stop
            foreach ($prop in $r.PSObject.Properties) { $versions[$prop.Name] = $prop.Value }
        } catch {
            Add-Res Mods ORANGE 'Modrinth injoignable' ('Les mods n''ont pas pu être comparés à Modrinth : ' + $_.Exception.Message)
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
            foreach ($pr in (Invoke-RestMethod -Uri $uri -UserAgent $script:SS_UserAgent -TimeoutSec 30 -ErrorAction Stop)) { $projets[$pr.id] = $pr }
        } catch { }
    }
    foreach ($h in @($versions.Keys)) {
        $v = $versions[$h]
        $resultat[$h] = [pscustomobject]@{ Projet = $projets[$v.project_id]; Version = $v.version_number }
    }
    return $resultat
}

# =====================================================================
#  Les scans
# =====================================================================
function Get-LecteursUsb {
    $liste = @()
    foreach ($d in @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.InterfaceType -eq 'USB' -or $_.PNPDeviceID -like 'USBSTOR*' })) {
        foreach ($p in @(Get-CimAssociatedInstance -InputObject $d -ResultClassName Win32_DiskPartition)) {
            foreach ($ld in @(Get-CimAssociatedInstance -InputObject $p -ResultClassName Win32_LogicalDisk)) {
                $liste += [pscustomobject]@{ Lettre = $ld.DeviceID.ToUpper(); Nom = $d.Model; Label = $ld.VolumeName; Taille = $ld.Size }
            }
        }
    }
    foreach ($ld in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2')) {
        $deja = $false
        foreach ($x in $liste) { if ($x.Lettre -eq $ld.DeviceID.ToUpper()) { $deja = $true } }
        if (-not $deja) { $liste += [pscustomobject]@{ Lettre = $ld.DeviceID.ToUpper(); Nom = 'Lecteur amovible'; Label = $ld.VolumeName; Taille = $ld.Size } }
    }
    return $liste
}

function Invoke-ScanSysteme {
    Set-Etape 3 'Informations système...'
    $os = Get-CimInstance Win32_OperatingSystem
    Add-Res Systeme INFO 'Date du scan' ('{0:dd/MM/yyyy HH:mm:ss}' -f (Get-Date))
    Add-Res Systeme INFO 'PC / session' "$env:COMPUTERNAME / $env:USERNAME"
    Add-Res Systeme INFO 'Windows' ('{0} ({1})' -f $os.Caption, $os.Version)
    if ($os.LastBootUpTime) {
        $t = (Get-Date) - $os.LastBootUpTime
        if ($t.TotalMinutes -lt 15) { Add-Res Systeme ORANGE 'PC redémarré il y a moins de 15 min' ('Démarré le {0} : un redémarrage efface certaines traces.' -f (Format-Date $os.LastBootUpTime)) }
        else { Add-Res Systeme INFO 'Démarrage du PC' ('{0} (il y a {1})' -f (Format-Date $os.LastBootUpTime), (Format-Duree $t)) }
    }
    if ($script:SS_Admin) { Add-Res Systeme OK 'Mode administrateur' 'Oui : scan complet.' }
    else { Add-Res Systeme INFO 'Mode administrateur' 'NON : l''historique des programmes (BAM / Prefetch) n''est pas vérifié. Relance PowerShell en administrateur pour un scan complet.' }
    Add-Res Systeme INFO 'Version de l''outil' "SnowFall SS v$SS_Version"
}

function Invoke-ScanMinecraft {
    Set-Etape 8 'Recherche de Minecraft...'
    $script:SS_DossiersMods = New-Object System.Collections.Generic.List[object]
    $script:SS_LancementJeu = $null
    $nb = 0
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'")) {
        $cmd = $p.CommandLine
        if ($cmd -and $cmd -notmatch $SS_RegexJeu) { continue }
        $nb++
        $version = '?'
        $m = [regex]::Match("$cmd", '--version\s+(\S+)')
        if ($m.Success) { $version = $m.Groups[1].Value }
        Add-Res Minecraft INFO ("Minecraft $version (PID $($p.ProcessId))") ('lancé le {0} avec {1}' -f (Format-Date $p.CreationDate), $p.ExecutablePath) $p.ExecutablePath
        if ($p.CreationDate -and (-not $script:SS_LancementJeu -or $p.CreationDate -lt $script:SS_LancementJeu)) { $script:SS_LancementJeu = $p.CreationDate }
        if (Test-SurUsb $p.ExecutablePath) { Add-Res Minecraft ROUGE 'Java lancé depuis une clé USB' $p.ExecutablePath $p.ExecutablePath }
        if (-not $cmd) {
            Add-Res Minecraft ORANGE 'Ligne de commande illisible' 'Relance le scan en administrateur pour voir comment le jeu a été lancé.'
            continue
        }
        $m = [regex]::Match($cmd, '--gameDir\s+(?:"([^"]+)"|(\S+))')
        if ($m.Success) {
            $gd = Get-Chemin $m.Groups
            Add-Res Minecraft INFO 'Dossier du jeu' $gd $gd
            if (Test-SurUsb $gd) { Add-Res Minecraft ROUGE 'Dossier du jeu sur une clé USB' $gd $gd }
            $script:SS_DossiersMods.Add([pscustomobject]@{ Chemin = (Join-Path $gd 'mods'); Jeu = $true })
            $script:SS_DossiersMods.Add([pscustomobject]@{ Chemin = (Join-Path $gd 'resourcepacks'); Jeu = $true })
        }
        foreach ($a in [regex]::Matches($cmd, '-javaagent:([^"\r\n]*?\.jar)')) {
            $chemin = $a.Groups[1].Value
            $fa = Get-Item -LiteralPath $chemin -Force
            if ((Split-Path $chemin -Leaf) -eq 'theseus.jar' -and $chemin -match '\\\.tmp\w+\\theseus\.jar$' -and $fa -and $fa.Length -lt 2MB) {
                Add-Res Minecraft OK 'Agent Java' 'theseus.jar : agent normal du Modrinth App' $chemin
                continue
            }
            $niv = 'ORANGE'
            if ($chemin -match '(?i)\\(temp|tmp|downloads|telechargements|t.l.chargements|desktop|bureau)\\' -or (Test-SurUsb $chemin)) { $niv = 'ROUGE' }
            Add-Res Minecraft $niv 'Agent Java chargé au lancement' $chemin $chemin
        }
        foreach ($a in [regex]::Matches($cmd, '(?i)-Dfabric\.addMods=(?:"([^"]+)"|(\S+))')) {
            $extra = Get-Chemin $a.Groups
            Add-Res Minecraft ORANGE 'Mods chargés depuis un autre dossier' $extra $extra
            foreach ($x in ($extra -split ';')) { if ($x) { $script:SS_DossiersMods.Add([pscustomobject]@{ Chemin = $x; Jeu = $true }) } }
        }
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
                if ($dlls.Count -eq 0) { Add-Res Minecraft OK 'DLL chargées dans le jeu' 'Rien d''anormal.' }
                foreach ($d in $dlls) { Add-Res Minecraft ORANGE 'DLL inhabituelle dans le jeu' $d.FileName $d.FileName }
            } else {
                Add-Res Minecraft INFO 'DLL chargées dans le jeu' 'Liste illisible : relance en administrateur.'
            }
        }
    }
    if ($nb -eq 0) { Add-Res Minecraft ORANGE 'Aucun Minecraft lancé' 'Demande au joueur de garder son jeu ouvert pendant le scan.' }
}

function Invoke-ScanMods {
    Set-Etape 15 'Recherche des dossiers mods...'
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
            $script:SS_DossiersMods.Add([pscustomobject]@{ Chemin = $it.FullName; Jeu = $false })
        }
    }
    $vus = @{}
    $dossiers = @()
    foreach ($d in $script:SS_DossiersMods) {
        if (-not (Test-Path -LiteralPath $d.Chemin)) { continue }
        $plein = (Resolve-Path -LiteralPath $d.Chemin).ProviderPath
        $cle = $plein.TrimEnd('\').ToLower()
        if ($vus.ContainsKey($cle)) { continue }
        $vus[$cle] = $true
        $dossiers += [pscustomobject]@{ Chemin = $plein; Jeu = $d.Jeu; Packs = ((Split-Path $plein -Leaf) -eq 'resourcepacks') }
    }
    if ($dossiers.Count -eq 0) { Add-Res Mods INFO 'Aucun dossier mods trouvé' 'Le joueur utilise peut-être un launcher non reconnu : demande-lui où sont ses mods.' }

    $jars = @()
    foreach ($d in $dossiers) {
        $tag = ''
        if ($d.Jeu) { $tag = ' (jeu lancé)' }
        if ($d.Packs) {
            $packs = @(Get-ChildItem -LiteralPath $d.Chemin -Force)
            Add-Res Mods INFO ("Packs de textures$tag : {0}" -f $packs.Count) $d.Chemin $d.Chemin
            foreach ($pk in $packs) { if ($pk.Name -match '(?i)x-?ray|ore.?(esp|finder)|see.?through') { Add-Res Mods ORANGE 'Pack de textures X-Ray' $pk.Name $pk.FullName } }
            continue
        }
        $fichiers = @(Get-ChildItem -LiteralPath $d.Chemin -Recurse -Depth 1 -File -Force)
        $lesJars = @($fichiers | Where-Object { $_.Extension -eq '.jar' })
        Add-Res Mods INFO ("Dossier mods$tag : {0} jar(s)" -f $lesJars.Count) $d.Chemin $d.Chemin
        foreach ($f in $fichiers) {
            if ($f.Extension -match '(?i)^\.(exe|dll|zip|rar|7z|class|bat|cmd|ps1|vbs)$') { Add-Res Mods ORANGE 'Fichier bizarre dans un dossier mods' $f.Name $f.FullName }
        }
        foreach ($f in $lesJars) {
            $jars += [pscustomobject]@{ Nom = $f.Name; Chemin = $f.FullName; Modif = $f.LastWriteTime; Jeu = $d.Jeu; Sha1 = $null }
        }
    }

    Set-Etape 22 ('Calcul des empreintes ({0} jars)...' -f $jars.Count)
    foreach ($j in $jars) { $j.Sha1 = (Get-FileHash -LiteralPath $j.Chemin -Algorithm SHA1).Hash.ToLower(); Invoke-Pompe }
    $hashes = @($jars | Where-Object { $_.Sha1 } | ForEach-Object { $_.Sha1 } | Sort-Object -Unique)
    Set-Etape 28 'Vérification auprès de Modrinth...'
    $modrinth = Get-InfosModrinth $hashes

    $n = $jars.Count; $i = 0
    foreach ($j in ($jars | Sort-Object Chemin)) {
        $i++
        Set-Etape (30 + [int](35 * $i / [Math]::Max(1, $n))) ('Analyse des mods ({0}/{1})...' -f $i, $n)
        $recent = ''
        if ($j.Modif -ge $script:SS_Depuis) { $recent = (' · modifié le {0:dd/MM HH:mm}' -f $j.Modif) }
        if ($j.Jeu -and $script:SS_LancementJeu -and $j.Modif -gt $script:SS_LancementJeu) {
            Add-Res Mods ORANGE ('Jar modifié APRÈS le lancement du jeu : ' + $j.Nom) ('modifié le {0}' -f (Format-Date $j.Modif)) $j.Chemin
        }
        $info = $null
        if ($j.Sha1 -and $modrinth.ContainsKey($j.Sha1)) { $info = $modrinth[$j.Sha1] }
        $connu = ($info -and $info.Projet)
        if ($connu -and $info.Projet.downloads -ge $SS_SeuilModrinth) {
            Add-Res Mods OK $j.Nom ('{0} {1} · {2:N0} téléchargements sur Modrinth{3}' -f $info.Projet.title, $info.Version, $info.Projet.downloads, $recent) $j.Chemin
            if ($info.Projet.slug -match $SS_RegexInterdit) { Add-Res Mods ORANGE ('Mod interdit sur la plupart des serveurs : ' + $info.Projet.title) $j.Nom $j.Chemin }
            continue
        }
        $an = Get-AnalyseJar $j.Chemin $j.Nom
        $source = 'pas sur Modrinth (peut venir de CurseForge ou d''ailleurs)'
        if ($connu) { $source = ('sur Modrinth mais peu téléchargé : {0} ({1:N0})' -f $info.Projet.title, $info.Projet.downloads) }
        $titre = $j.Nom
        if ($an.ModId) { $titre += "  [id: $($an.ModId)]" }
        if ($an.Niveau) { Add-Res Mods $an.Niveau $titre ($an.Raisons + ' · ' + $source + $recent) $j.Chemin }
        else { Add-Res Mods INFO $titre ($source + ', rien de suspect dedans' + $recent) $j.Chemin }
    }
}

function Invoke-ScanProgrammes {
    Set-Etape 68 'Programmes ouverts...'
    $rien = $true
    foreach ($pr in @(Get-CimInstance Win32_Process)) {
        if ($pr.Name -match $SS_RegexProgramme -or $pr.ExecutablePath -match $SS_RegexProgramme) {
            Add-Res Programmes ORANGE ('Programme suspect ouvert : ' + $pr.Name) ('PID {0} · {1}' -f $pr.ProcessId, $pr.ExecutablePath) $pr.ExecutablePath
            $rien = $false
        } elseif ($pr.Name -match $SS_RegexSouris) {
            Add-Res Programmes INFO ('Logiciel souris/clavier : ' + $pr.Name) 'Peut faire des macros : demande au joueur de l''ouvrir pour vérifier.' $pr.ExecutablePath
        }
    }
    foreach ($gp in @(Get-Process | Where-Object { $_.MainWindowTitle })) {
        if ($gp.MainWindowTitle -match $SS_RegexProgramme) {
            Add-Res Programmes ORANGE ('Fenêtre suspecte : ' + $gp.MainWindowTitle) ($gp.ProcessName + '.exe') $gp.Path
            $rien = $false
        }
    }
    if ($rien) { Add-Res Programmes OK 'Programmes ouverts' 'Aucun autoclicker / injecteur connu en cours.' }

    Set-Etape 72 'Historique des programmes...'
    if (-not $script:SS_Admin) {
        Add-Res Programmes INFO 'Historique BAM / Prefetch' 'Non vérifié : il faut lancer PowerShell en administrateur.'
        return
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings\$sid"
    if (-not (Test-Path $cle)) { $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings\$sid" }
    $entrees = @()
    $props = Get-ItemProperty -Path $cle
    if ($props) {
        foreach ($pp in $props.PSObject.Properties) {
            if ($pp.Value -is [byte[]] -and $pp.Value.Length -ge 8) {
                $date = [DateTime]::FromFileTime([BitConverter]::ToInt64($pp.Value, 0))
                if ($date -ge $script:SS_Depuis) { $entrees += [pscustomobject]@{ Date = $date; Exe = ($pp.Name -replace '^\\Device\\HarddiskVolume\d+', '') } }
            }
        }
    }
    foreach ($en in ($entrees | Sort-Object Date -Descending | Select-Object -First 50)) {
        $nom = Split-Path $en.Exe -Leaf
        if ($en.Exe -match $SS_RegexProgramme) { Add-Res Programmes ORANGE ('Lancé récemment : ' + $nom) ('{0} · {1}' -f (Format-Date $en.Date), $en.Exe) }
        else { Add-Res Programmes INFO ('Lancé : ' + $nom) ('{0} · {1}' -f (Format-Date $en.Date), $en.Exe) }
    }
    $pf = @(Get-ChildItem -Path "$env:windir\Prefetch" -Filter *.pf -Force | Where-Object { $_.LastWriteTime -ge $script:SS_Depuis -and $_.Name -match $SS_RegexProgramme })
    foreach ($f in $pf) { Add-Res Programmes ORANGE ('Prefetch : ' + $f.Name) ('lancé le ' + (Format-Date $f.LastWriteTime)) $f.FullName }
    if ($pf.Count -eq 0) { Add-Res Programmes OK 'Prefetch' 'Aucun programme suspect lancé récemment.' }
}

function Invoke-ScanUsb {
    Set-Etape 76 'Clés USB branchées...'
    if ($script:SS_Usb.Count -eq 0) { Add-Res Usb OK 'Clés USB branchées' 'Aucune clé USB branchée en ce moment.' }
    foreach ($u in $script:SS_Usb) {
        $racine = $u.Lettre + '\'
        $taille = ''
        if ($u.Taille) { $taille = ' · ' + (Format-Taille $u.Taille) }
        $fichiers = @(Get-ChildItem -LiteralPath $racine -Recurse -Depth 5 -Force | Select-Object -First 20000)
        $nbJar = 0; $nbExe = 0; $suspect = $false; $k = 0
        $avant = $script:SS_Resultats.Count
        foreach ($f in $fichiers) {
            $k++
            if ($k % 400 -eq 0) { Invoke-Pompe }
            if ($f.PSIsContainer) {
                if ($f.Name -match '(?i)^(\.minecraft|mods|versions|\.lunarclient|\.feather|\.tlauncher)$') { Add-Res Usb ORANGE ('Dossier Minecraft sur la clé : ' + $f.Name) $f.FullName $f.FullName; $suspect = $true }
                continue
            }
            $ext = $f.Extension.ToLower()
            if ($ext -eq '.jar') {
                $nbJar++
                if ($nbJar -le 60) {
                    Set-Etape 78 ('Analyse de la clé {0} : {1}' -f $u.Lettre, $f.Name)
                    $an = Get-AnalyseJar $f.FullName $f.Name
                    $niv = 'ORANGE'
                    if ($an.Niveau) { $niv = $an.Niveau }
                    $det = $an.Raisons
                    if (-not $det) { $det = 'rien de suspect dedans, mais un jar sur une clé mérite d''être regardé' }
                    Add-Res Usb $niv ('Jar sur la clé : ' + $f.Name) ($det + ' · modifié le ' + (Format-Date $f.LastWriteTime)) $f.FullName
                    $suspect = $true
                }
            } elseif ($ext -match '^\.(exe|dll|bat|cmd|ps1|vbs)$') {
                if ($f.Name -match $SS_RegexNom -or $f.Name -match $SS_RegexProgramme) {
                    Add-Res Usb ORANGE ('Programme suspect sur la clé : ' + $f.Name) ('modifié le ' + (Format-Date $f.LastWriteTime)) $f.FullName
                    $suspect = $true
                } elseif ($nbExe -lt 30) {
                    $nbExe++
                    Add-Res Usb INFO ('Programme sur la clé : ' + $f.Name) ('modifié le ' + (Format-Date $f.LastWriteTime)) $f.FullName
                }
            }
        }
        $niv = 'INFO'
        if ($suspect) { $niv = 'ORANGE' }
        $resume = ('{0} {1}{2} · {3} fichier(s), {4} jar(s)' -f $u.Nom, $u.Label, $taille, $fichiers.Count, $nbJar)
        $script:SS_Resultats.Insert($avant, [pscustomobject]@{ Cat = 'Usb'; Niveau = $niv; Titre = ('Clé USB branchée : ' + $u.Lettre); Detail = $resume; Chemin = $racine })
    }

    Set-Etape 82 'Historique des clés USB...'
    $devs = @(Get-PnpDevice | Where-Object { $_.InstanceId -like 'USBSTOR\*' })
    foreach ($dv in @(Get-PnpDevice -Class DiskDrive | Where-Object { $_.InstanceId -like 'SCSI\*' })) {
        $parent = (Get-PnpDeviceProperty -InstanceId $dv.InstanceId -KeyName 'DEVPKEY_Device_Parent').Data
        if ("$parent" -like 'USB\*') { $devs += $dv }
    }
    if ($devs.Count -eq 0) { Add-Res Usb OK 'Historique des clés USB' 'Aucune clé USB n''a été branchée sur ce PC (selon Windows).'; return }
    $hist = @()
    foreach ($dv in $devs) {
        $pr = @(Get-PnpDeviceProperty -InstanceId $dv.InstanceId -KeyName 'DEVPKEY_Device_LastArrivalDate', 'DEVPKEY_Device_LastRemovalDate', 'DEVPKEY_Device_FirstInstallDate')
        $h = [pscustomobject]@{ Nom = $dv.FriendlyName; Branchee = ($dv.Status -eq 'OK'); Arrivee = $null; Retrait = $null; Premiere = $null }
        foreach ($x in $pr) {
            if ($x.KeyName -eq 'DEVPKEY_Device_LastArrivalDate') { $h.Arrivee = $x.Data }
            elseif ($x.KeyName -eq 'DEVPKEY_Device_LastRemovalDate') { $h.Retrait = $x.Data }
            elseif ($x.KeyName -eq 'DEVPKEY_Device_FirstInstallDate') { $h.Premiere = $x.Data }
        }
        $hist += $h
    }
    foreach ($h in ($hist | Sort-Object { if ($_.Arrivee) { $_.Arrivee } else { [DateTime]::MinValue } } -Descending)) {
        $det = 'première fois : {0} · dernier branchement : {1} · dernier retrait : {2}' -f (Format-Date $h.Premiere), (Format-Date $h.Arrivee), (Format-Date $h.Retrait)
        if ($h.Branchee) { Add-Res Usb INFO ('Historique : ' + $h.Nom + ' (branchée)') $det; continue }
        if ($h.Retrait -and $h.Retrait -ge $script:SS_Depuis) {
            if ($script:SS_LancementJeu -and $h.Retrait -gt $script:SS_LancementJeu) { $det += ' · retirée PENDANT que Minecraft tournait' }
            Add-Res Usb ORANGE ('Clé retirée récemment : ' + $h.Nom) $det
        } else {
            Add-Res Usb INFO ('Historique : ' + $h.Nom) $det
        }
    }
}

function Invoke-ScanFichiers {
    Set-Etape 88 'Fichiers récents...'
    $telech = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}'
    if (-not $telech) { $telech = "$env:USERPROFILE\Downloads" }
    $lieux = @($telech, [Environment]::GetFolderPath('Desktop'), $env:TEMP, [Environment]::GetFolderPath('MyDocuments')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique
    $rien = $true
    foreach ($l in $lieux) {
        Invoke-Pompe
        $rec = @(Get-ChildItem -LiteralPath $l -Recurse -Depth 2 -File -Force | Where-Object { ($_.Extension -eq '.jar' -or $_.Extension -eq '.exe') -and $_.LastWriteTime -ge $script:SS_Depuis -and $_.FullName -notmatch '(?i)\\(lwjgl|jna|minecraft|modrinth|curseforge|prismlauncher)' -and $_.FullName -notmatch '\\\.tmp\w+\\theseus\.jar$' })
        foreach ($f in ($rec | Sort-Object LastWriteTime -Descending | Select-Object -First 25)) {
            $rien = $false
            $det = '{0} · {1} · {2}' -f (Format-Date $f.LastWriteTime), (Format-Taille $f.Length), $f.DirectoryName
            if ($f.Name -match $SS_RegexNom -or $f.Name -match $SS_RegexProgramme) { Add-Res Fichiers ORANGE ('Nom suspect : ' + $f.Name) $det $f.FullName }
            else { Add-Res Fichiers INFO $f.Name $det $f.FullName }
        }
    }
    if ($rien) { Add-Res Fichiers OK 'Fichiers récents' "Aucun .jar / .exe récent (moins de $SS_Heures h)." }
}

function Invoke-ScanCorbeille {
    Set-Etape 95 'Corbeille...'
    $rien = $true
    try {
        $sh = New-Object -ComObject Shell.Application
        $rb = $sh.Namespace(10)
        foreach ($it in @($rb.Items())) {
            $ext = [IO.Path]::GetExtension($it.Path).ToLower()
            if ($ext -ne '.jar' -and $ext -ne '.exe' -and $ext -ne '.dll') { continue }
            $quand = $it.ExtendedProperty('System.Recycle.DateDeleted')
            $origine = $it.ExtendedProperty('System.Recycle.DeletedFrom')
            if ($quand -and ([DateTime]$quand) -lt $script:SS_Depuis) { continue }
            $rien = $false
            $det = 'supprimé le {0} · venait de {1}' -f (Format-Date $quand), $origine
            if ("$origine" -match '(?i)\\mods' -or $it.Name -match $SS_RegexNom -or $it.Name -match $SS_RegexProgramme) { Add-Res Corbeille ORANGE ('Supprimé récemment : ' + $it.Name) $det }
            else { Add-Res Corbeille INFO $it.Name $det }
        }
    } catch { Add-Res Corbeille INFO 'Corbeille' 'Illisible.' }
    if ($rien) { Add-Res Corbeille OK 'Corbeille' "Aucun .jar / .exe / .dll supprimé depuis $SS_Heures h." }
}

# =====================================================================
#  Verdict, rapport
# =====================================================================
function Get-Compte {
    param([string]$Cat, [string]$Niveau)
    $n = 0
    foreach ($r in $script:SS_Resultats) { if ($r.Niveau -eq $Niveau -and ($Cat -eq 'Resume' -or $r.Cat -eq $Cat)) { $n++ } }
    return $n
}

function Update-Verdict {
    $r = Get-Compte Resume ROUGE
    $o = Get-Compte Resume ORANGE
    if ($script:ScanEnCours) { $txt = 'Scan en cours...'; $niv = 'ACCENT' }
    elseif ($r -gt 0) { $txt = "SUSPECT  ·  $r rouge(s), $o orange(s)"; $niv = 'ROUGE' }
    elseif ($o -gt 0) { $txt = "À VÉRIFIER  ·  $o point(s) orange à regarder avec le joueur"; $niv = 'ORANGE' }
    else { $txt = 'RIEN DE SUSPECT TROUVÉ'; $niv = 'OK' }
    $script:VerdictTexte = 'VERDICT : ' + $txt
    if ($script:UI) {
        $c = $script:Couleurs[$niv]
        $script:UI.Verdict.Text = $txt
        $script:UI.Verdict.ForeColor = $c
        $script:UI.Bande.BackColor = $c
    }
}

function Get-TexteRapport {
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("SnowFall SS v$SS_Version - rapport de screenshare")
    [void]$sb.AppendLine(('Date : {0:dd/MM/yyyy HH:mm:ss}  ·  PC : {1}  ·  session : {2}' -f (Get-Date), $env:COMPUTERNAME, $env:USERNAME))
    [void]$sb.AppendLine($script:VerdictTexte)
    foreach ($cle in $SS_Categories.Keys) {
        if ($cle -eq 'Resume') { continue }
        $rows = @($script:SS_Resultats | Where-Object { $_.Cat -eq $cle })
        if ($rows.Count -eq 0) { continue }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('=== ' + $SS_Categories[$cle] + ' ===')
        foreach ($r in $rows) {
            [void]$sb.AppendLine(('[{0}] {1} : {2}' -f $r.Niveau, $r.Titre, $r.Detail))
            if ($r.Chemin -and $r.Detail -notlike "*$($r.Chemin)*") { [void]$sb.AppendLine('        -> ' + $r.Chemin) }
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Un scan propre ne prouve pas à 100 % que le joueur est clean : regarde aussi son écran.')
    return $sb.ToString()
}

function Save-Rapport {
    $script:SS_Fichier = Join-Path ([Environment]::GetFolderPath('Desktop')) ('SnowSS_{0:yyyy-MM-dd_HH-mm}.txt' -f (Get-Date))
    try { [IO.File]::WriteAllText($script:SS_Fichier, (Get-TexteRapport), (New-Object Text.UTF8Encoding $true)) } catch { $script:SS_Fichier = $null }
}

function Start-Scan {
    if ($script:ScanEnCours) { return }
    $script:ScanEnCours = $true
    $script:Annule = $false
    $script:SS_Resultats.Clear()
    $script:SS_Depuis = (Get-Date).AddHours(-$SS_Heures)
    if ($script:UI) {
        foreach ($b in $script:UI.Actions) { $b.Enabled = $false }
        Update-Verdict
        Show-Categorie 'Resume'
    }
    try {
        $script:SS_Usb = @(Get-LecteursUsb)
        Invoke-ScanSysteme
        Invoke-ScanMinecraft
        Invoke-ScanMods
        Invoke-ScanProgrammes
        Invoke-ScanUsb
        Invoke-ScanFichiers
        Invoke-ScanCorbeille
    } catch {
        if ("$_" -eq 'SCAN_ANNULE') { $script:ScanEnCours = $false; return }
        Add-Res Systeme ORANGE 'Erreur pendant le scan' $_.Exception.Message
    }
    $script:ScanEnCours = $false
    Update-Verdict
    Save-Rapport
    if ($script:UI) {
        $script:UI.Barre.Value = 100
        if ($script:SS_Fichier) { $script:UI.Statut.Text = 'Scan terminé · rapport enregistré sur le Bureau' }
        else { $script:UI.Statut.Text = 'Scan terminé' }
        foreach ($b in $script:UI.Actions) { $b.Enabled = $true }
        Update-Navigation
        Show-Categorie 'Resume'
    }
}

# =====================================================================
#  Interface
# =====================================================================
function Update-Navigation {
    if (-not $script:UI) { return }
    foreach ($cle in $SS_Categories.Keys) {
        $b = $script:UI.Boutons[$cle]
        $nom = $SS_Categories[$cle]
        $r = Get-Compte $cle ROUGE
        $o = Get-Compte $cle ORANGE
        if ($r -gt 0) { $b.Text = "     $nom   ($($r + $o))"; $b.ForeColor = $script:Couleurs.ROUGE }
        elseif ($o -gt 0) { $b.Text = "     $nom   ($o)"; $b.ForeColor = $script:Couleurs.ORANGE }
        else { $b.Text = "     $nom"; $b.ForeColor = $script:Couleurs.Texte }
    }
}

function Show-Categorie {
    param([string]$Cle)
    if (-not $script:UI) { return }
    $script:CatActive = $Cle
    $lv = $script:UI.Liste
    $rouges = New-Object System.Collections.Generic.List[object]
    $oranges = New-Object System.Collections.Generic.List[object]
    $autres = New-Object System.Collections.Generic.List[object]
    foreach ($x in $script:SS_Resultats) {
        if ($Cle -ne 'Resume' -and $x.Cat -ne $Cle) { continue }
        if ($x.Niveau -eq 'ROUGE') { $rouges.Add($x) }
        elseif ($x.Niveau -eq 'ORANGE') { $oranges.Add($x) }
        elseif ($Cle -ne 'Resume') { $autres.Add($x) }
    }
    $rows = @($rouges.ToArray()) + @($oranges.ToArray()) + @($autres.ToArray())
    if ($Cle -eq 'Resume' -and $rows.Count -eq 0 -and -not $script:ScanEnCours) {
        $rows = @([pscustomobject]@{ Cat = 'Resume'; Niveau = 'OK'; Titre = 'Aucune alerte'; Detail = 'Aucun élément rouge ou orange. Regarde quand même les autres catégories.'; Chemin = '' })
    }
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($r in $rows) {
        $titre = $r.Titre
        if ($Cle -eq 'Resume' -and $r.Cat -ne 'Resume') { $titre = $SS_Categories[$r.Cat] + '  ›  ' + $titre }
        $it = New-Object Windows.Forms.ListViewItem(('●  ' + $r.Niveau))
        [void]$it.SubItems.Add($titre)
        [void]$it.SubItems.Add($r.Detail)
        $it.ForeColor = $script:Couleurs[$r.Niveau]
        $it.Tag = $r
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
    foreach ($k in $script:UI.Boutons.Keys) { $script:UI.Boutons[$k].BackColor = $script:Couleurs.Panneau }
    $script:UI.Boutons[$Cle].BackColor = $script:Couleurs.Actif
    $script:UI.TitreListe.Text = $SS_Categories[$Cle]
    $script:UI.Detail.Text = 'Clique sur une ligne pour voir le détail. Double-clic : ouvrir l''emplacement du fichier.'
    Set-Colonnes
}

function Set-Colonnes {
    if (-not $script:UI) { return }
    $lv = $script:UI.Liste
    if ($script:DansColonnes) { return }
    $script:DansColonnes = $true
    try {
        $w = $lv.Width - $lv.Columns[0].Width - $lv.Columns[1].Width - 2
        $hauteurLigne = 30
        if ($lv.Items.Count -gt 0) { $hauteurLigne = $lv.GetItemRect(0).Height }
        if (($lv.Items.Count + 1) * $hauteurLigne -gt $lv.Height) { $w -= [Windows.Forms.SystemInformation]::VerticalScrollBarWidth + 6 }
        if ($w -gt 100 -and $lv.Columns[2].Width -ne $w) { $lv.Columns[2].Width = $w }
    } finally { $script:DansColonnes = $false }
}

function Open-Emplacement {
    if ($script:UI.Liste.SelectedItems.Count -eq 0) { return }
    $c = $script:UI.Liste.SelectedItems[0].Tag.Chemin
    if (-not $c -or -not (Test-Path -LiteralPath $c)) { return }
    if ((Get-Item -LiteralPath $c -Force).PSIsContainer) { Start-Process explorer.exe -ArgumentList ('"' + $c + '"') }
    else { Start-Process explorer.exe -ArgumentList ('/select,"' + $c + '"') }
}

function New-Bouton {
    param([string]$Texte, [bool]$Principal = $false)
    $b = New-Object Windows.Forms.Button
    $b.Text = $Texte
    $b.AutoSize = $true
    $b.AutoSizeMode = 'GrowAndShrink'
    $b.Padding = New-Object Windows.Forms.Padding(14, 6, 14, 6)
    $b.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 0)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $script:Couleurs.Bord
    $b.Cursor = 'Hand'
    if ($Principal) {
        $b.BackColor = $script:Couleurs.ACCENT
        $b.ForeColor = $script:Couleurs.Fond
        $b.FlatAppearance.BorderSize = 0
        $b.Font = New-Object Drawing.Font('Segoe UI Semibold', 10)
    } else {
        $b.BackColor = $script:Couleurs.Carte
        $b.ForeColor = $script:Couleurs.Texte
        $b.FlatAppearance.BorderSize = 1
    }
    return $b
}

function New-Interface {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $script:Couleurs = @{
        Fond    = [Drawing.Color]::FromArgb(11, 16, 26)
        Panneau = [Drawing.Color]::FromArgb(17, 24, 38)
        Carte   = [Drawing.Color]::FromArgb(23, 32, 50)
        Actif   = [Drawing.Color]::FromArgb(31, 44, 68)
        Survol  = [Drawing.Color]::FromArgb(27, 38, 59)
        Bord    = [Drawing.Color]::FromArgb(45, 59, 86)
        Entete  = [Drawing.Color]::FromArgb(19, 27, 42)
        Texte   = [Drawing.Color]::FromArgb(228, 236, 247)
        Gris    = [Drawing.Color]::FromArgb(134, 150, 176)
        ACCENT  = [Drawing.Color]::FromArgb(116, 196, 255)
        ROUGE   = [Drawing.Color]::FromArgb(255, 99, 99)
        ORANGE  = [Drawing.Color]::FromArgb(255, 188, 84)
        OK      = [Drawing.Color]::FromArgb(98, 216, 146)
        INFO    = [Drawing.Color]::FromArgb(172, 184, 206)
    }
    $K = $script:Couleurs
    $script:PoliceEntete = New-Object Drawing.Font('Segoe UI Semibold', 9)
    $script:PinceauEntete = New-Object Drawing.SolidBrush($K.Entete)
    $script:PinceauLigne = New-Object Drawing.SolidBrush($K.Bord)

    $f = New-Object Windows.Forms.Form
    $f.Text = "SnowFall SS v$SS_Version"
    $f.Size = New-Object Drawing.Size(1240, 800)
    $f.MinimumSize = New-Object Drawing.Size(960, 600)
    $f.StartPosition = 'CenterScreen'
    $f.BackColor = $K.Fond
    $f.ForeColor = $K.Texte
    $f.Font = New-Object Drawing.Font('Segoe UI', 10)
    $f.KeyPreview = $true

    # --- En-tete ---
    $entete = New-Object Windows.Forms.Panel
    $entete.Dock = 'Top'; $entete.Height = 84; $entete.BackColor = $K.Panneau
    $logo = New-Object Windows.Forms.Label
    $logo.Text = '❄'; $logo.Font = New-Object Drawing.Font('Segoe UI Symbol', 28); $logo.ForeColor = $K.ACCENT
    $logo.AutoSize = $true; $logo.Location = New-Object Drawing.Point(18, 12)
    $titre = New-Object Windows.Forms.Label
    $titre.Text = 'SnowFall SS'; $titre.Font = New-Object Drawing.Font('Segoe UI Semibold', 20); $titre.ForeColor = $K.Texte
    $titre.AutoSize = $true; $titre.Location = New-Object Drawing.Point(74, 10)
    $sous = New-Object Windows.Forms.Label
    $sous.Text = "Outil de screenshare du staff SnowFall  ·  lecture seule  ·  v$SS_Version"
    $sous.ForeColor = $K.Gris; $sous.AutoSize = $true; $sous.Location = New-Object Drawing.Point(78, 50)
    $infos = New-Object Windows.Forms.Label
    $infos.Dock = 'Right'; $infos.Width = 420; $infos.TextAlign = 'MiddleRight'; $infos.Padding = New-Object Windows.Forms.Padding(0, 0, 22, 0)
    if ($script:SS_Admin) { $adm = 'Administrateur : oui' ; $infos.ForeColor = $K.OK }
    else { $adm = 'Administrateur : NON (scan incomplet)'; $infos.ForeColor = $K.ORANGE }
    $infos.Text = "$env:COMPUTERNAME  ·  $env:USERNAME`n$adm"
    $entete.Controls.AddRange(@($infos, $logo, $titre, $sous))
    $ligneEntete = New-Object Windows.Forms.Panel
    $ligneEntete.Dock = 'Top'; $ligneEntete.Height = 1; $ligneEntete.BackColor = $K.Bord

    # --- Pied ---
    $pied = New-Object Windows.Forms.Panel
    $pied.Dock = 'Bottom'; $pied.Height = 62; $pied.BackColor = $K.Panneau
    $pied.Padding = New-Object Windows.Forms.Padding(18, 14, 18, 14)
    $barre = New-Object Windows.Forms.ProgressBar
    $barre.Width = 260; $barre.Height = 10; $barre.Location = New-Object Drawing.Point(20, 18); $barre.Style = 'Continuous'
    $statut = New-Object Windows.Forms.Label
    $statut.AutoSize = $true; $statut.ForeColor = $K.Gris; $statut.Location = New-Object Drawing.Point(18, 34)
    $statut.Text = 'Préparation...'
    $actions = New-Object Windows.Forms.FlowLayoutPanel
    $actions.Dock = 'Right'; $actions.AutoSize = $true; $actions.FlowDirection = 'RightToLeft'; $actions.WrapContents = $false
    $actions.BackColor = $K.Panneau
    $bRelancer = New-Bouton 'Relancer le scan' $true
    $bOuvrir = New-Bouton 'Ouvrir le rapport'
    $bCopier = New-Bouton 'Copier le rapport'
    $actions.Controls.AddRange(@($bRelancer, $bOuvrir, $bCopier))
    $pied.Controls.AddRange(@($actions, $barre, $statut))
    $lignePied = New-Object Windows.Forms.Panel
    $lignePied.Dock = 'Bottom'; $lignePied.Height = 1; $lignePied.BackColor = $K.Bord

    # --- Navigation ---
    $nav = New-Object Windows.Forms.Panel
    $nav.Dock = 'Left'; $nav.Width = 236; $nav.BackColor = $K.Panneau
    $nav.Padding = New-Object Windows.Forms.Padding(10, 12, 10, 12)
    $boutons = @{}
    $cles = @($SS_Categories.Keys)
    [array]::Reverse($cles)
    foreach ($cle in $cles) {
        $b = New-Object Windows.Forms.Button
        $b.Dock = 'Top'; $b.Height = 44
        $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = $K.Survol
        $b.FlatAppearance.MouseDownBackColor = $K.Actif
        $b.BackColor = $K.Panneau; $b.ForeColor = $K.Texte
        $b.TextAlign = 'MiddleLeft'; $b.Cursor = 'Hand'
        $b.Text = '     ' + $SS_Categories[$cle]
        $b.Tag = $cle
        $b.Add_Click({ Show-Categorie $this.Tag })
        if ($cle -eq 'Resume') {
            $sep = New-Object Windows.Forms.Panel
            $sep.Dock = 'Top'; $sep.Height = 10
            $nav.Controls.Add($sep)
        }
        $nav.Controls.Add($b)
        $boutons[$cle] = $b
    }
    $lblNav = New-Object Windows.Forms.Label
    $lblNav.Text = 'CATÉGORIES'; $lblNav.Dock = 'Top'; $lblNav.Height = 28; $lblNav.ForeColor = $K.Gris
    $lblNav.Font = New-Object Drawing.Font('Segoe UI Semibold', 8.5); $lblNav.Padding = New-Object Windows.Forms.Padding(14, 0, 0, 0)
    $nav.Controls.Add($lblNav)
    $ligneNav = New-Object Windows.Forms.Panel
    $ligneNav.Dock = 'Left'; $ligneNav.Width = 1; $ligneNav.BackColor = $K.Bord

    # --- Zone principale ---
    $main = New-Object Windows.Forms.Panel
    $main.Dock = 'Fill'; $main.Padding = New-Object Windows.Forms.Padding(20, 18, 20, 16); $main.BackColor = $K.Fond

    $carteVerdict = New-Object Windows.Forms.Panel
    $carteVerdict.Dock = 'Top'; $carteVerdict.Height = 76; $carteVerdict.BackColor = $K.Carte
    $bande = New-Object Windows.Forms.Panel
    $bande.Dock = 'Left'; $bande.Width = 6; $bande.BackColor = $K.ACCENT
    $lblV1 = New-Object Windows.Forms.Label
    $lblV1.Text = 'VERDICT'; $lblV1.ForeColor = $K.Gris; $lblV1.Font = New-Object Drawing.Font('Segoe UI Semibold', 8.5)
    $lblV1.AutoSize = $true; $lblV1.Location = New-Object Drawing.Point(24, 10)
    $verdict = New-Object Windows.Forms.Label
    $verdict.Text = 'Scan en cours...'; $verdict.Font = New-Object Drawing.Font('Segoe UI Semibold', 17); $verdict.ForeColor = $K.ACCENT
    $verdict.AutoSize = $true; $verdict.Location = New-Object Drawing.Point(22, 30)
    $carteVerdict.Controls.AddRange(@($lblV1, $verdict, $bande))

    $espace1 = New-Object Windows.Forms.Panel; $espace1.Dock = 'Top'; $espace1.Height = 16
    $titreListe = New-Object Windows.Forms.Label
    $titreListe.Dock = 'Top'; $titreListe.Height = 30; $titreListe.Font = New-Object Drawing.Font('Segoe UI Semibold', 12)
    $titreListe.ForeColor = $K.Texte; $titreListe.Text = 'Résumé'

    $lv = New-Object Windows.Forms.ListView
    $lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HideSelection = $false; $lv.MultiSelect = $false
    $lv.BorderStyle = 'None'; $lv.BackColor = $K.Carte; $lv.ForeColor = $K.Texte; $lv.HeaderStyle = 'Nonclickable'
    $lv.Font = New-Object Drawing.Font('Segoe UI', 9.75)
    [void]$lv.Columns.Add('STATUT', 120)
    [void]$lv.Columns.Add('ÉLÉMENT', 380)
    [void]$lv.Columns.Add('DÉTAIL', 500)
    $il = New-Object Windows.Forms.ImageList
    $il.ImageSize = New-Object Drawing.Size(1, 30)
    $lv.SmallImageList = $il
    $lv.OwnerDraw = $true
    $lv.Add_DrawColumnHeader({
        param($s, $e)
        $e.Graphics.FillRectangle($script:PinceauEntete, $e.Bounds)
        $e.Graphics.FillRectangle($script:PinceauLigne, $e.Bounds.X, ($e.Bounds.Bottom - 1), $e.Bounds.Width, 1)
        $rect = New-Object Drawing.Rectangle(($e.Bounds.X + 10), $e.Bounds.Y, ($e.Bounds.Width - 10), $e.Bounds.Height)
        [Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $script:PoliceEntete, $rect, $script:Couleurs.Gris, [Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis')
    })
    $lv.Add_DrawItem({ param($s, $e) $e.DrawDefault = $true })
    $lv.Add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true })
    $lv.Add_Resize({ Set-Colonnes })
    $lv.Add_SelectedIndexChanged({
        if ($script:UI.Liste.SelectedItems.Count -eq 0) { return }
        $r = $script:UI.Liste.SelectedItems[0].Tag
        $t = $r.Titre + "`r`n" + $r.Detail
        if ($r.Chemin) { $t += "`r`nEmplacement : " + $r.Chemin }
        $script:UI.Detail.Text = $t
    })
    $lv.Add_DoubleClick({ Open-Emplacement })

    $menu = New-Object Windows.Forms.ContextMenuStrip
    $mCopier = $menu.Items.Add('Copier la ligne')
    $mCopier.Add_Click({
        if ($script:UI.Liste.SelectedItems.Count -eq 0) { return }
        $r = $script:UI.Liste.SelectedItems[0].Tag
        [Windows.Forms.Clipboard]::SetText(('[{0}] {1} : {2} {3}' -f $r.Niveau, $r.Titre, $r.Detail, $r.Chemin).Trim())
    })
    $mOuvrir = $menu.Items.Add('Ouvrir l''emplacement')
    $mOuvrir.Add_Click({ Open-Emplacement })
    $lv.ContextMenuStrip = $menu

    $espace2 = New-Object Windows.Forms.Panel; $espace2.Dock = 'Bottom'; $espace2.Height = 12
    $detail = New-Object Windows.Forms.TextBox
    $detail.Dock = 'Bottom'; $detail.Height = 92; $detail.Multiline = $true; $detail.ReadOnly = $true; $detail.ScrollBars = 'Vertical'
    $detail.BorderStyle = 'None'; $detail.BackColor = $K.Carte; $detail.ForeColor = $K.Texte
    $detail.Font = New-Object Drawing.Font('Consolas', 9.75)
    $cadreDetail = New-Object Windows.Forms.Panel
    $cadreDetail.Dock = 'Bottom'; $cadreDetail.Height = 108; $cadreDetail.BackColor = $K.Carte
    $cadreDetail.Padding = New-Object Windows.Forms.Padding(12, 8, 12, 8)
    $detail.Dock = 'Fill'
    $cadreDetail.Controls.Add($detail)

    $main.Controls.Add($lv)
    $main.Controls.Add($espace2)
    $main.Controls.Add($cadreDetail)
    $main.Controls.Add($titreListe)
    $main.Controls.Add($espace1)
    $main.Controls.Add($carteVerdict)

    $f.Controls.Add($main)
    $f.Controls.Add($ligneNav)
    $f.Controls.Add($nav)
    $f.Controls.Add($lignePied)
    $f.Controls.Add($pied)
    $f.Controls.Add($ligneEntete)
    $f.Controls.Add($entete)
    $main.BringToFront()

    $script:UI = @{
        Form = $f; Liste = $lv; Detail = $detail; Barre = $barre; Statut = $statut
        Verdict = $verdict; Bande = $bande; TitreListe = $titreListe
        Boutons = $boutons; Actions = @($bRelancer, $bOuvrir, $bCopier)
    }

    $bRelancer.Add_Click({ Start-Scan })
    $bOuvrir.Add_Click({ if ($script:SS_Fichier -and (Test-Path -LiteralPath $script:SS_Fichier)) { Start-Process notepad.exe -ArgumentList ('"' + $script:SS_Fichier + '"') } })
    $bCopier.Add_Click({
        [Windows.Forms.Clipboard]::SetText((Get-TexteRapport))
        $script:UI.Statut.Text = 'Rapport copié dans le presse-papiers'
    })
    $f.Add_FormClosing({ $script:Annule = $true })
    $f.Add_Shown({
        $script:UI.Form.Activate()
        Set-Colonnes
        Start-Scan
        if ($env:SNOWSS_CAPTURE) {
            Show-Categorie $env:SNOWSS_CAPTURE_CAT
            [Windows.Forms.Application]::DoEvents()
            $bmp = New-Object Drawing.Bitmap($script:UI.Form.Width, $script:UI.Form.Height)
            $script:UI.Form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)))
            $bmp.Save($env:SNOWSS_CAPTURE)
            $bmp.Dispose()
            $script:UI.Form.Close()
        }
    })
    Update-Navigation
}

# =====================================================================
#  Lancement
# =====================================================================
$modeConsole = [bool]$env:SNOWSS_CONSOLE
if (-not $modeConsole) {
    try { New-Interface }
    catch {
        $modeConsole = $true
        $script:UI = $null
        Write-Host ("Interface impossible ({0}) : passage en mode console." -f $_.Exception.Message) -ForegroundColor Yellow
    }
}
if ($modeConsole) {
    Start-Scan
    Write-Host ''
    Write-Host ('  ' + $script:VerdictTexte) -ForegroundColor Cyan
    if ($script:SS_Fichier) { Write-Host ('  Rapport : ' + $script:SS_Fichier) -ForegroundColor Cyan }
    if (-not $env:SNOWSS_NOPAUSE) { try { [void](Read-Host '  Appuie sur Entrée pour fermer') } catch { } }
} else {
    Write-Host '  SnowFall SS : la fenêtre du scan est ouverte.' -ForegroundColor Cyan
    [void]$script:UI.Form.ShowDialog()
    $script:UI.Form.Dispose()
    $script:UI = $null
}
