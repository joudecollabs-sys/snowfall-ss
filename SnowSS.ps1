# =====================================================================
#  SnowFall SS v3.5 - outil de screenshare du staff SnowFall
#
#  CE QUE FAIT CE SCRIPT (lecture seule) :
#    - ouvre une fenetre qui affiche le resultat du scan par categorie
#    - Minecraft lance : version, dossier
#    - injection : agents Java, DLL et threads injectes, mods supprimes apres lancement
#    - stream-proof : fenetres cachees a la capture, overlays transparents
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
$SS_MinutesAvantScan = 30    # appareil debranche moins de X min avant le scan = alerte rouge
$SS_Version       = '3.5'

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
$script:FiltreLauncher = ''

$SS_Categories = [ordered]@{
    Resume     = 'Résumé'
    Systeme    = 'Système'
    Minecraft  = 'Minecraft'
    Logs       = 'Logs du jeu'
    Injection  = 'Injection / stream-proof'
    Mods       = 'Mods'
    Programmes = 'Programmes'
    Macros     = 'Macros / autoclick'
    Usb        = 'USB'
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
$SS_RegexChargeur  = '(?i)(^|/)(PayloadLoader|PayloadSignature|PayloadUpdater|PayloadCache|PayloadDownloader|MemoryFs|MemoryFileSystem|MemoryClassLoader|InMemoryClassLoader|InMemoryJar\w*|RemoteLoader|RemoteClassLoader|Stage2\w*)(\$[^/]*)?\.class$'
$SS_RegexDescChargeur = '(?i)(payload|fetch(es)? and loads?|downloads? (and loads? )?(the )?client|loads? the client|client itself lives|inject(s|ed|or)?\b)'
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
    param([string]$Cat, [string]$Niveau, [string]$Titre, [string]$Detail = '', [string]$Chemin = '', [string]$Groupe = '')
    $script:SS_Resultats.Add([pscustomobject]@{ Cat = $Cat; Niveau = $Niveau; Titre = $Titre; Detail = $Detail; Chemin = $Chemin; Groupe = $Groupe })
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
        $script:UI.Barre.Width = [Math]::Max(0, $script:UI.BarreFond.ActualWidth * [Math]::Min(100, $Pct) / 100)
        $script:UI.Statut.Text = $Texte
        Update-Navigation
        if ($script:SS_Resultats.Count -ne $script:NbAffiche) { Show-Categorie $script:CatActive }
        Invoke-PompeUi
    } elseif ($Texte -notmatch '\(\d+/\d+\)|^Analyse de la cl') {
        Write-Host ''
        Write-Host "=== $Texte ===" -ForegroundColor Cyan
    }
}

function Invoke-Pompe {
    if ($script:Annule) { throw 'SCAN_ANNULE' }
    if ($script:UI) { Invoke-PompeUi }
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
            if ($n -match $SS_RegexChargeur) { $c = ($Matches[2]); if ($Res.Chargeur -notcontains $c) { $Res.Chargeur += $c } }
            if ($n.StartsWith('imgui/')) { $Res.ImGui = $true }
            continue
        }
        if ($Profondeur -eq 0) {
            if ($n -eq 'fabric.mod.json' -or $n -eq 'quilt.mod.json') {
                $txt = Read-Entree $e
                $m = [regex]::Match($txt, '"id"\s*:\s*"([^"]+)"')
                if ($m.Success) { $Res.ModId = $m.Groups[1].Value }
                $m = [regex]::Match($txt, '"name"\s*:\s*"([^"]+)"')
                if ($m.Success) { $Res.NomMod = $m.Groups[1].Value }
                $m = [regex]::Match($txt, '"description"\s*:\s*"([^"]*)"')
                if ($m.Success -and $m.Groups[1].Value -match $SS_RegexDescChargeur) { $Res.DescChargeur = $m.Groups[1].Value }
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
        if ($n.EndsWith('.jar') -and $n -match '(?i)imgui-java') { $Res.ImGui = $true }
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
        Paquets = @(); Modules = @(); Chargeur = @(); ImGui = $false; DescChargeur = $null
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
    if ($a.Chargeur.Count -gt 0 -or $a.DescChargeur) {
        $preuves = @()
        if ($a.Chargeur.Count) { $preuves += ('classes ' + ($a.Chargeur -join ', ')) }
        if ($a.DescChargeur) { $preuves += ('sa description : « ' + $(if ($a.DescChargeur.Length -gt 120) { $a.DescChargeur.Substring(0, 120) + '…' } else { $a.DescChargeur }) + ' »') }
        if ($a.ImGui) { $preuves += 'contient ImGui' }
        if (($a.Chargeur.Count -and $a.DescChargeur) -or $a.ImGui -or ($a.Classes -ge 30 -and ($a.Obfusque / $a.Classes) -ge 0.4)) { $niveau = 'ROUGE' } elseif (-not $niveau) { $niveau = 'ORANGE' }
        $r.Add('CHARGEUR DE CLIENT CACHÉ : le vrai code est téléchargé au lancement et chargé en mémoire, il n''est pas dans ce jar (' + ($preuves -join ' ; ') + ')')
    } elseif ($a.ImGui) { if (-not $niveau) { $niveau = 'ORANGE' }; $r.Add('contient ImGui : menu en surimpression utilisé par beaucoup de clients de triche') }
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

$SS_CodeNatif = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class SnowNatif {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetWindowDisplayAffinity(IntPtr h, out uint a);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public class Fenetre { public long Hwnd; public uint Pid; public string Titre; public string Classe; public uint Affinite; public long ExStyle; public bool Visible; public int Largeur; public int Hauteur; }
    public static List<Fenetre> Fenetres() {
        var l = new List<Fenetre>();
        EnumProc cb = (h, p) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            uint a = 0; GetWindowDisplayAffinity(h, out a);
            var t = new StringBuilder(256); GetWindowText(h, t, 256);
            var c = new StringBuilder(256); GetClassName(h, c, 256);
            RECT r; GetWindowRect(h, out r);
            l.Add(new Fenetre { Hwnd = h.ToInt64(), Pid = pid, Titre = t.ToString(), Classe = c.ToString(), Affinite = a,
                                ExStyle = GetWindowLongPtr(h, -20).ToInt64(), Visible = IsWindowVisible(h), Largeur = r.R - r.L, Hauteur = r.B - r.T });
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        GC.KeepAlive(cb);
        return l;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint QueryDosDevice(string nom, StringBuilder cible, int max);
    public static string Peripherique(string lettre) {
        var s = new StringBuilder(512);
        return QueryDosDevice(lettre, s, 512) > 0 ? s.ToString() : null;
    }
    [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint acc, bool inh, uint id);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationThread(IntPtr h, int cls, out IntPtr info, int len, IntPtr ret);
    public static long DebutThread(uint tid) {
        IntPtr h = OpenThread(0x0040 | 0x0800, false, tid);
        if (h == IntPtr.Zero) return -1;
        try { IntPtr a; int s = NtQueryInformationThread(h, 9, out a, IntPtr.Size, IntPtr.Zero); return s == 0 ? a.ToInt64() : -1; }
        finally { CloseHandle(h); }
    }
}
'@

$SS_CodePoignees = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class SnowPoignees {
    [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint acc, bool inh, uint pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();
    [DllImport("advapi32.dll")] static extern bool OpenProcessToken(IntPtr p, uint acc, out IntPtr t);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string s, string n, out long luid);
    [StructLayout(LayoutKind.Sequential, Pack = 4)] struct TP { public uint Count; public long Luid; public uint Attr; }
    [DllImport("advapi32.dll")] static extern bool AdjustTokenPrivileges(IntPtr t, bool dis, ref TP n, int len, IntPtr p, IntPtr r);
    public static void ActiverDebug() {
        IntPtr t;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out t)) return;
        long l;
        if (LookupPrivilegeValue(null, "SeDebugPrivilege", out l)) { var tp = new TP { Count = 1, Luid = l, Attr = 2 }; AdjustTokenPrivileges(t, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero); }
        CloseHandle(t);
    }
    public class Acces { public uint Pid; public uint Droits; }
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, IntPtr buf, int len, out int ret);
    [DllImport("kernel32.dll")] static extern bool DuplicateHandle(IntPtr sp, IntPtr sh, IntPtr tp, out IntPtr th, uint acc, bool inh, uint opt);
    [DllImport("kernel32.dll")] static extern uint GetProcessId(IntPtr h);
    static IntPtr Poignees(IntPtr proc, out long n) {
        n = 0; int taille = 1 << 16, ret;
        for (int essai = 0; essai < 8; essai++) {
            IntPtr b = Marshal.AllocHGlobal(taille);
            int st = NtQueryInformationProcess(proc, 51, b, taille, out ret);
            if (st == 0) { n = Marshal.ReadInt64(b); return b; }
            Marshal.FreeHGlobal(b);
            if (st != unchecked((int)0xC0000004) && st != unchecked((int)0x80000005) && st != unchecked((int)0xC0000023)) return IntPtr.Zero;
            taille = Math.Max(taille * 2, ret + 4096);
        }
        return IntPtr.Zero;
    }
    // Sans admin : on parcourt les poignees de chaque programme qu'on peut ouvrir (meme utilisateur)
    public static List<Acces> OuvreursUtilisateur(uint cible, out int illisibles) {
        illisibles = 0;
        var res = new Dictionary<uint, uint>();
        uint moi = GetCurrentProcessId();
        // index du type "Process" : on le lit sur une de nos propres poignees
        IntPtr hc = OpenProcess(0x1000, false, cible);
        if (hc == IntPtr.Zero) return null;
        int typeProc = -1;
        try {
            long n; IntPtr b = Poignees(GetCurrentProcess(), out n);
            if (b == IntPtr.Zero) return null;
            try { for (long i = 0; i < n; i++) { long p = b.ToInt64() + 16 + i * 40; if (Marshal.ReadInt64(new IntPtr(p)) == hc.ToInt64()) { typeProc = Marshal.ReadInt32(new IntPtr(p + 28)); break; } } }
            finally { Marshal.FreeHGlobal(b); }
        } finally { CloseHandle(hc); }
        if (typeProc < 0) return null;
        foreach (var pr in System.Diagnostics.Process.GetProcesses()) {
            uint pid = (uint)pr.Id;
            if (pid == moi || pid == cible || pid <= 4) continue;
            IntPtr hp = OpenProcess(0x40 | 0x400, false, pid);
            if (hp == IntPtr.Zero) { illisibles++; continue; }
            try {
                long n; IntPtr b = Poignees(hp, out n);
                if (b == IntPtr.Zero) { illisibles++; continue; }
                try {
                    for (long i = 0; i < n; i++) {
                        long p = b.ToInt64() + 16 + i * 40;
                        if (Marshal.ReadInt32(new IntPtr(p + 28)) != typeProc) continue;
                        IntPtr dup;
                        if (!DuplicateHandle(hp, Marshal.ReadIntPtr(new IntPtr(p)), GetCurrentProcess(), out dup, 0x1000, false, 0)) continue;
                        uint vise = GetProcessId(dup); CloseHandle(dup);
                        if (vise != cible) continue;
                        uint acc = (uint)Marshal.ReadInt32(new IntPtr(p + 24));
                        uint deja; res[pid] = res.TryGetValue(pid, out deja) ? (deja | acc) : acc;
                    }
                } finally { Marshal.FreeHGlobal(b); }
            } finally { CloseHandle(hp); }
        }
        var l = new List<Acces>();
        foreach (var kv in res) l.Add(new Acces { Pid = kv.Key, Droits = kv.Value });
        return l;
    }
    // Liste des processus qui ont une poignee ouverte sur le processus "cible" (et les droits obtenus)
    public static List<Acces> Ouvreurs(uint cible, out string erreur) {
        erreur = null;
        IntPtr h = OpenProcess(0x1000, false, cible);
        if (h == IntPtr.Zero) { erreur = "impossible d'ouvrir le jeu"; return null; }
        try {
            int taille = 1 << 23, ret = 0, st = 0; IntPtr buf = IntPtr.Zero;
            while (true) {
                buf = Marshal.AllocHGlobal(taille);
                st = NtQuerySystemInformation(64, buf, taille, out ret);
                if (st == unchecked((int)0xC0000004)) {
                    Marshal.FreeHGlobal(buf); buf = IntPtr.Zero;
                    taille = Math.Max(taille * 2, ret + (1 << 20));
                    if (taille > (1 << 30)) { erreur = "table trop grande"; return null; }
                    continue;
                }
                break;
            }
            try {
                if (st != 0) { erreur = "statut 0x" + st.ToString("X8"); return null; }
                long n = Marshal.ReadIntPtr(buf).ToInt64();
                int te = 8 + 8 + 8 + 4 + 2 + 2 + 4 + 4;
                long debut = buf.ToInt64() + 16;
                long moi = GetCurrentProcessId();
                long hv = h.ToInt64();
                long objet = 0; int type = -1;
                for (long i = 0; i < n; i++) {
                    long p = debut + i * te;
                    if (Marshal.ReadInt64(new IntPtr(p + 8)) == moi && Marshal.ReadInt64(new IntPtr(p + 16)) == hv) {
                        objet = Marshal.ReadInt64(new IntPtr(p)); type = Marshal.ReadInt16(new IntPtr(p + 30)); break;
                    }
                }
                if (objet == 0) { erreur = "adresses masquées par Windows (lance en administrateur)"; return null; }
                var res = new Dictionary<uint, uint>();
                for (long i = 0; i < n; i++) {
                    long p = debut + i * te;
                    if (Marshal.ReadInt64(new IntPtr(p)) != objet || Marshal.ReadInt16(new IntPtr(p + 30)) != type) continue;
                    uint pid = (uint)Marshal.ReadInt64(new IntPtr(p + 8));
                    if (pid == moi || pid == cible) continue;
                    uint acc = (uint)Marshal.ReadInt32(new IntPtr(p + 24));
                    uint deja; res[pid] = res.TryGetValue(pid, out deja) ? (deja | acc) : acc;
                }
                var l = new List<Acces>();
                foreach (var kv in res) l.Add(new Acces { Pid = kv.Key, Droits = kv.Value });
                return l;
            } finally { if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf); }
        } finally { CloseHandle(h); }
    }
}
'@

function Initialize-Poignees {
    if (-not ('SnowPoignees' -as [type])) { Add-Type -TypeDefinition $SS_CodePoignees -ErrorAction Stop }
}

$SS_CodeTouches = @'
using System;
using System.Runtime.InteropServices;
public static class SnowTouches {
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

    public static bool AuPremierPlan(IntPtr jeu) { return GetForegroundWindow() == jeu; }

    // Met la fenetre du jeu au premier plan (restaure si reduite)
    public static bool Activer(IntPtr jeu) {
        if (IsIconic(jeu)) ShowWindow(jeu, 9);
        if (SetForegroundWindow(jeu)) return true;
        uint p; uint tAvant = GetWindowThreadProcessId(GetForegroundWindow(), out p);
        uint moi = GetCurrentThreadId();
        AttachThreadInput(moi, tAvant, true);
        BringWindowToTop(jeu); bool ok = SetForegroundWindow(jeu);
        AttachThreadInput(moi, tAvant, false);
        return ok || GetForegroundWindow() == jeu;
    }

    public static int[] Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return new int[] { r.L, r.T, r.R, r.B }; }

    // Appuie (ou relache) une touche par son code de balayage physique : independant du clavier AZERTY/QWERTY
    public static bool Appui(ushort scan, bool etendue, bool relache) {
        uint f = 0x0008 | (etendue ? 0x0001u : 0u) | (relache ? 0x0002u : 0u);
        var e = new INPUT[1];
        e[0].type = 1; e[0].u.ki.wScan = scan; e[0].u.ki.dwFlags = f;
        return SendInput(1, e, Marshal.SizeOf(typeof(INPUT))) == 1;
    }
}
'@

function Initialize-Natif {
    if (-not ('SnowNatif' -as [type])) { Add-Type -TypeDefinition $SS_CodeNatif -ErrorAction Stop }
}

# Lecture des .pf du Prefetch : chemin complet de l'exe qui a ete lance
$SS_CodePrefetch = @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class SnowPrefetch {
    [DllImport("ntdll.dll")] static extern uint RtlGetCompressionWorkSpaceSize(ushort fmt, out uint ws, out uint fs);
    [DllImport("ntdll.dll")] static extern uint RtlDecompressBufferEx(ushort fmt, byte[] dst, uint dstSize, byte[] src, uint srcSize, out uint final, byte[] ws);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint QueryDosDevice(string nom, StringBuilder cible, int max);
    // Windows 10/11 : .pf compresse (en-tete "MAM") ; Windows 7/8 : brut
    static byte[] Lire(string chemin) {
        byte[] d = File.ReadAllBytes(chemin);
        if (d.Length < 8 || d[0] != 0x4D || d[1] != 0x41 || d[2] != 0x4D) return d;
        ushort fmt = (ushort)(d[3] & 0x0F);
        int deb = (d[3] & 0xF0) != 0 ? 12 : 8;
        uint taille = BitConverter.ToUInt32(d, 4), ws, fs, fin;
        if (taille == 0 || taille > (64u << 20) || RtlGetCompressionWorkSpaceSize(fmt, out ws, out fs) != 0) return null;
        byte[] src = new byte[d.Length - deb];
        Array.Copy(d, deb, src, 0, src.Length);
        byte[] o = new byte[taille];
        if (RtlDecompressBufferEx(fmt, o, taille, src, (uint)src.Length, out fin, new byte[ws]) != 0) return null;
        return o;
    }
    // Chemin de l'exe tel que Windows l'a enregistre (\VOLUME{...}\... ou \DEVICE\HARDDISKVOLUMEx\...), null si illisible
    public static string Exe(string chemin) {
        byte[] d = Lire(chemin);
        if (d == null || d.Length < 0x6C || BitConverter.ToUInt32(d, 4) != 0x41434353) return null;
        string nom = Encoding.Unicode.GetString(d, 0x10, 60).Split('\0')[0];
        int off = BitConverter.ToInt32(d, 0x64), len = BitConverter.ToInt32(d, 0x68);
        if (nom.Length == 0 || off <= 0 || len <= 0 || (long)off + len > d.Length) return null;
        foreach (string f in Encoding.Unicode.GetString(d, off, len).Split('\0')) {
            int i = f.LastIndexOf('\\');
            if (i >= 0 && f.Substring(i + 1).StartsWith(nom, StringComparison.OrdinalIgnoreCase)) return f;
        }
        return null;
    }
    public static string Volume(string lettre) {
        var sb = new StringBuilder(512);
        return QueryDosDevice(lettre, sb, 512) == 0 ? null : sb.ToString();
    }
}
'@

function Initialize-Prefetch {
    if (-not ('SnowPrefetch' -as [type])) { Add-Type -TypeDefinition $SS_CodePrefetch -ErrorAction Stop }
}

function Get-Volumes {
    if ($null -eq $script:SS_Volumes) {
        $script:SS_Volumes = @(foreach ($d in @(Get-CimInstance Win32_LogicalDisk)) {
            [pscustomobject]@{ Lettre = $d.DeviceID; Serie = $d.VolumeSerialNumber; Device = [SnowPrefetch]::Volume($d.DeviceID) }
        })
    }
    return $script:SS_Volumes
}

# \VOLUME{date-NUMSERIE}\... (Prefetch) ou \Device\HarddiskVolumeX\... (BAM) -> C:\...
function Convert-CheminWindows {
    param([string]$Brut)
    if ($Brut -notmatch '^\\(?:VOLUME\{[0-9a-f]*-([0-9a-f]{8})\}|DEVICE\\HARDDISKVOLUME\d+)(\\.*)$') { return $Brut }
    $serie = $Matches[1]; $rel = $Matches[2]
    $device = $Brut.Substring(0, $Brut.Length - $rel.Length)
    foreach ($v in @(Get-Volumes)) {
        if (($serie -and $v.Serie -eq $serie) -or (-not $serie -and $v.Device -eq $device)) { return $v.Lettre + $rel }
    }
    return $rel
}

# Le nom d'un .pf finit par le hash du chemin complet de l'exe (\DEVICE\HARDDISKVOLUMEX\...)
function Get-HashPrefetch {
    param([string]$Chemin)
    [uint64]$h = 314159
    foreach ($b in [Text.Encoding]::Unicode.GetBytes($Chemin.ToUpperInvariant())) { $h = (($h * 37) + $b) % 4294967296 }
    return ('{0:X8}' -f $h)
}

# Si le .pf est illisible : cherche parmi les vrais inject-helper de Medal / OBS celui dont le chemin donne ce hash
function Find-InjectHelperParHash {
    param([string]$NomPf)
    if ($NomPf -notmatch '-([0-9A-F]{8})\.pf$') { return $null }
    $cible = $Matches[1]
    $cands = @(Get-ChildItem -Path "$env:LOCALAPPDATA\Medal\recorder-*\Host\inject-helper*.exe" -Force)
    foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) { if ($r) { $cands += @(Get-ChildItem -LiteralPath "$r\obs-studio\data\obs-plugins\win-capture" -Filter 'inject-helper*.exe' -Force) } }
    foreach ($c in $cands) {
        $v = @(Get-Volumes) | Where-Object { $_.Lettre -eq $c.FullName.Substring(0, 2) } | Select-Object -First 1
        if ($v -and $v.Device -and (Get-HashPrefetch ($v.Device + $c.FullName.Substring(2))) -eq $cible) { return $c.FullName }
    }
    return $null
}

# inject-helper*.exe = outil de capture video de Medal / OBS (accroche l'enregistrement au jeu).
# Un cheat peut prendre ce nom : on verifie le dossier et la signature. Renvoie @(niveau, explication).
function Get-AvisInjectHelper {
    param([string]$Exe)
    $outil = $null; $editeur = $null
    if ($Exe -match '(?i)\\AppData\\Local\\Medal\\recorder-[\d.]+\\Host\\inject-helper(32|64)-v2\.exe$') { $outil = 'Medal'; $editeur = 'Ferox Games' }
    elseif ($Exe -match '(?i)\\data\\obs-plugins\\win-capture\\inject-helper(32|64)\.exe$') { $outil = 'OBS' }
    if (-not $outil) { return @('ORANGE', 'porte le nom de l''outil de capture de Medal / OBS mais n''est PAS dans leur dossier : faux nom possible, demande au joueur ce que c''est') }
    if ($Exe -notmatch '^[a-z]:\\' -or -not (Test-Path -LiteralPath $Exe)) {
        $medalLa = @(Get-ChildItem -Path "$env:LOCALAPPDATA\Medal\recorder-*\Host\inject-helper*-v2.exe" -Force).Count -gt 0
        if ($outil -eq 'Medal' -and $medalLa -and -not (Test-Path -LiteralPath (Split-Path $Exe -Parent))) {
            return @('INFO', 'outil de capture de Medal, ancienne version (Medal efface ses anciennes versions en se mettant à jour) : normal si le joueur enregistre ses parties')
        }
        return @('ORANGE', ('dossier de {0} mais l''exe n''existe plus : supprimé depuis, à demander au joueur' -f $outil))
    }
    $s = Get-AuthenticodeSignature -LiteralPath $Exe
    $qui = ''
    if ($s.SignerCertificate) { $qui = $s.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) }
    $etat = '{0} ({1})' -f $(if ($qui) { $qui } else { 'aucune signature' }), $s.Status
    if ($s.Status -eq 'HashMismatch') { return @('ROUGE', ('copie MODIFIÉE de l''outil de capture de {0} : signature cassée · {1}' -f $outil, $etat)) }
    if ($editeur -and ($s.Status -ne 'Valid' -or $qui -notmatch [regex]::Escape($editeur))) { return @('ROUGE', ('imite l''outil de capture de Medal mais n''est pas signé par Medal ({0}) · {1}' -f $editeur, $etat)) }
    if ($s.Status -ne 'Valid') { return @('ORANGE', ('dossier d''OBS mais exe non signé (vieille version d''OBS ou copie) · {0}' -f $etat)) }
    return @('INFO', ('outil de capture de {0}, vérifié (bon dossier, signé {1}) : normal si le joueur enregistre ses parties' -f $outil, $qui))
}

# Ce qui a ete injecte dans le jeu (agents, options, DLL, threads)
function Invoke-ScanInjection {
    param($p, [string]$cmd)
    $titreJeu = "jeu PID $($p.ProcessId)"
    $rien = $true

    # 1. Agents Java (charges au lancement)
    foreach ($a in [regex]::Matches($cmd, '-javaagent:([^"\r\n]*?\.jar)')) {
        $chemin = $a.Groups[1].Value
        $fa = Get-Item -LiteralPath $chemin -Force
        if ((Split-Path $chemin -Leaf) -eq 'theseus.jar' -and $chemin -match '\\\.tmp\w+\\theseus\.jar$' -and $fa -and $fa.Length -lt 2MB) {
            Add-Res Injection OK 'Agent Java du Modrinth App' 'theseus.jar : agent normal du launcher Modrinth' $chemin
            continue
        }
        $rien = $false
        $niv = 'ORANGE'
        if ($chemin -match '(?i)\\(temp|tmp|downloads|telechargements|t.l.chargements|desktop|bureau)\\' -or (Test-SurUsb $chemin)) { $niv = 'ROUGE' }
        $det = 'Un agent Java peut modifier le jeu au lancement'
        if ($fa) {
            $an = Get-AnalyseJar $chemin (Split-Path $chemin -Leaf)
            if ($an.Niveau -eq 'ROUGE') { $niv = 'ROUGE' }
            if ($an.Raisons) { $det += ' · ' + $an.Raisons }
        } else { $det += ' · le fichier n''existe plus (supprimé après le lancement ?)'; $niv = 'ROUGE' }
        Add-Res Injection $niv ('Agent Java injecté au lancement : ' + (Split-Path $chemin -Leaf)) $det $chemin
    }
    # 2. Agents natifs et options de lancement suspectes
    foreach ($a in [regex]::Matches($cmd, '-agent(path|lib):([^\s"]+)')) {
        $rien = $false
        $val = $a.Groups[2].Value
        if ($a.Groups[1].Value -eq 'lib' -and $val -match '^jdwp') { Add-Res Injection ORANGE 'Débogueur Java activé (jdwp)' ('Permet de modifier le jeu en direct : ' + $val) }
        else { Add-Res Injection ROUGE ('Agent natif chargé dans le jeu (-agent' + $a.Groups[1].Value + ')') ('DLL chargée par Java au démarrage : ' + $val) $val }
    }
    $options = @(
        @{ R = '-Xbootclasspath/[ap]:(\S+)'; T = 'Classes ajoutées au démarrage de Java (-Xbootclasspath)' },
        @{ R = '(?<!\S)(-noverify|-Xverify:none)'; T = 'Vérification du code Java désactivée (-noverify)' },
        @{ R = '-Djava\.system\.class\.loader=(\S+)'; T = 'Chargeur de classes remplacé' },
        @{ R = '(?i)-Dfabric\.addMods=(?:"([^"]+)"|(\S+))'; T = 'Mods chargés depuis un autre dossier (-Dfabric.addMods)' }
    )
    foreach ($o in $options) {
        foreach ($a in [regex]::Matches($cmd, $o.R)) {
            $rien = $false
            Add-Res Injection ORANGE $o.T $a.Value.Trim()
            if ($o.T -like 'Mods charg*') {
                $extra = Get-Chemin $a.Groups
                foreach ($x in ("$extra" -split ';')) { if ($x) { $script:SS_DossiersMods.Add([pscustomobject]@{ Chemin = $x; Jeu = $true }) } }
            }
        }
    }

    if (-not $p.ExecutablePath) { return }
    $javaDir = Split-Path (Split-Path $p.ExecutablePath -Parent) -Parent
    $gp = Get-Process -Id $p.ProcessId
    if (-not $gp -or -not $gp.Modules) {
        Add-Res Injection INFO 'DLL et threads du jeu' 'Liste illisible : relance le scan en administrateur.'
        return
    }
    $modules = @($gp.Modules)

    # 3. DLL injectees
    Set-Etape 10 'Recherche de DLL injectées dans le jeu...'
    $dlls = @($modules | Where-Object {
        $_.FileName -and
        -not $_.FileName.StartsWith($env:windir, [StringComparison]::OrdinalIgnoreCase) -and
        -not $_.FileName.StartsWith($javaDir, [StringComparison]::OrdinalIgnoreCase) -and
        $_.FileName -notmatch $SS_RegexDllNormale
    })
    foreach ($d in $dlls) {
        $rien = $false
        $sig = Get-AuthenticodeSignature -LiteralPath $d.FileName
        $signe = ($sig -and $sig.Status -eq 'Valid')
        $editeur = ''
        if ($signe) { $editeur = ($sig.SignerCertificate.Subject -replace '^CN=("?)([^",]+).*$', '$2') }
        $niv = 'ORANGE'
        if (-not $signe -and $d.FileName -match '(?i)\\(temp|tmp|downloads|t.l.chargements|desktop|bureau)\\') { $niv = 'ROUGE' }
        if (Test-SurUsb $d.FileName) { $niv = 'ROUGE' }
        if ($signe) { $det = "signée par $editeur" } else { $det = 'NON signée' }
        $det += (' · {0} · {1}' -f (Format-Taille (Get-Item -LiteralPath $d.FileName -Force).Length), $titreJeu)
        Add-Res Injection $niv ('DLL injectée dans le jeu : ' + $d.ModuleName) $det $d.FileName
    }
    if ($dlls.Count -eq 0) { Add-Res Injection OK 'DLL chargées dans le jeu' ("{0} DLL vérifiées, aucune DLL étrangère ({1})." -f $modules.Count, $titreJeu) }

    # 4. Threads qui ne demarrent dans aucun module (injection manuelle / shellcode)
    Set-Etape 12 'Recherche de threads injectés dans le jeu...'
    try {
        Initialize-Natif
        $plages = @($modules | ForEach-Object { [pscustomobject]@{ D = $_.BaseAddress.ToInt64(); F = $_.BaseAddress.ToInt64() + $_.ModuleMemorySize } })
        $suspects = @(); $lus = 0
        foreach ($th in @($gp.Threads)) {
            $adr = [SnowNatif]::DebutThread([uint32]$th.Id)
            if ($adr -le 0) { continue }
            $lus++
            $dedans = $false
            foreach ($pl in $plages) { if ($adr -ge $pl.D -and $adr -lt $pl.F) { $dedans = $true; break } }
            if (-not $dedans) { $suspects += ('thread {0} → 0x{1:X}' -f $th.Id, $adr) }
        }
        if ($suspects.Count -gt 0) {
            $rien = $false
            Add-Res Injection ROUGE ('Threads injectés dans le jeu : ' + $suspects.Count) ('Ces threads ne démarrent dans aucune DLL connue : signe d''injection manuelle (manual map / shellcode) · ' + ($suspects[0..([Math]::Min(4, $suspects.Count - 1))] -join ', ') + ' · ' + $titreJeu)
        } elseif ($lus -gt 0) {
            Add-Res Injection OK 'Threads du jeu' ("{0} threads vérifiés, tous démarrent dans une DLL connue ({1})." -f $lus, $titreJeu)
        } else {
            Add-Res Injection INFO 'Threads du jeu' 'Illisibles : relance le scan en administrateur.'
        }
    } catch { Add-Res Injection INFO 'Threads du jeu' ('Vérification impossible : ' + $_.Exception.Message) }
}

# Compare les mods charges par le jeu (logs\latest.log) avec ceux encore presents
function Invoke-ScanLogJeu {
    Set-Etape 66 'Comparaison avec le log du jeu...'
    foreach ($j in $script:SS_Jeux) {
        $log = Join-Path $j.Dossier 'logs\latest.log'
        if (-not (Test-Path -LiteralPath $log)) { continue }
        $lignes = @()
        try {
            $fs = New-Object IO.FileStream($log, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            $sr = New-Object IO.StreamReader($fs)
            $lignes = $sr.ReadToEnd() -split "`r?`n"
            $sr.Dispose()
        } catch { continue }
        $charges = @()
        $dans = $false
        foreach ($l in $lignes) {
            if ($l -match 'Loading \d+ mods:') { $dans = $true; $charges = @(); continue }
            if ($dans) {
                if ($l -match '^\t- ([A-Za-z0-9_\-\.]+) ') { $charges += $Matches[1]; continue }
                if ($l -match '^\t\s') { continue }
                $dans = $false
            }
        }
        if ($charges.Count -eq 0) { continue }
        $presents = @{}
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $j.Dossier 'mods') -Filter *.jar -File -Force)) {
            $id = Get-ModIdRapide $f.FullName
            if ($id) { $presents[$id.ToLower()] = $true }
        }
        $integres = '^(minecraft|java|fabricloader|quilt_loader|mixinextras|fabric-api-base)$'
        $manquants = @($charges | Where-Object { $_ -notmatch $integres -and -not $presents.ContainsKey($_.ToLower()) })
        if ($manquants.Count -gt 0) {
            Add-Res Injection ROUGE ('Mods chargés par le jeu mais supprimés depuis : ' + ($manquants -join ', ')) ('Le log du jeu montre ces mods au lancement, mais leur jar n''est plus dans le dossier mods (supprimé ou déplacé pendant la partie ?) · ' + $log) $log
        } else {
            Add-Res Injection OK 'Mods du log du jeu' ("{0} mods chargés au lancement, tous encore présents dans le dossier mods." -f $charges.Count) $log
        }
        $txt = $lignes -join "`n"
        $m = [regex]::Match($txt, '(?i)\b(meteor ?client|wurst|aristois|liquidbounce|rusherhack|thunderhack|bleachhack|boze|doomsday|prestige ?client|vape|phobos|konas|earthhack|self.?destruct)\b')
        if ($m.Success) { Add-Res Injection ORANGE ('Nom de client de triche dans le log du jeu : ' + $m.Value) $log $log }
    }
}

# =====================================================================
#  Logs du jeu : toutes les instances, 7 derniers jours (latest.log, .log.gz, crash-reports)
# =====================================================================
$SS_LogJours = 7
$SS_ReClientLog = '(?i)\b(meteor[\s-]?client|meteordevelopment|net\.wurstclient|wurst[\s-]?client|aristois|liquidbounce|net\.ccbluex|rusherhack|thunderhack|bleachhack|boze[\s-]?client|dev\.boze|doomsday[\s-]?client|prestige[\s-]?client|vape[\s-]?(lite|v4)|phobos|konas|future[\s-]?client|earthhack|lvstrng|inertia[\s-]?client|coffee[\s-]?client|salhack|kami[\s-]?blue|lambda[\s-]?client|impact[\s-]?client|self[\s-]?destruct)\b'
$SS_ReChatCheat = '\[CHAT\]\s*(?:<[^>]*>\s*)?[\[(<](Meteor|Wurst|LiquidBounce|Thunder\w*|Rusher\w*|Boze|Prestige|Argon|Aristois|BleachHack|Future|Inertia|Konas|Phobos|Vape|Doomsday|Lambda|Impact)[\])>]'
$SS_ReToggle = '(?i)\b(toggled|enabled|disabled|activ[ée]e?|d[ée]sactiv[ée]e?)\b[^\r\n]{0,30}\b(KillAura|Kill Aura|TriggerBot|AimAssist|Aim Assist|AutoCrystal|CrystalAura|AnchorAura|Reach|Velocity|AutoTotem|Scaffold|Flight|NoFall|XRay|X-Ray|Freecam|AutoClicker|ESP|Tracers|Nuker|AutoAnchor|HitBoxes|Criticals)\b'

function Read-Log {
    param([string]$Fichier)
    try {
        $fs = New-Object IO.FileStream($Fichier, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            if ($fs.Length -gt 40MB) { return '' }
            $st = $fs
            if ($Fichier -like '*.gz') { $st = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress) }
            $sr = New-Object IO.StreamReader($st, [Text.Encoding]::UTF8, $true)
            $t = $sr.ReadToEnd(); $sr.Dispose(); return $t
        } finally { $fs.Dispose() }
    } catch { return '' }
}

function Invoke-ScanLogsJeu {
    Set-Etape 66 'Lecture des logs du jeu...'
    $depuis = (Get-Date).AddDays(-$SS_LogJours)
    # dossiers de jeu : jeu lancé + parent de chaque dossier mods trouvé + .minecraft
    $dossiers = [ordered]@{}
    foreach ($j in $script:SS_Jeux) { if ($j.Dossier) { $dossiers[$j.Dossier.TrimEnd('\').ToLower()] = @{ Chemin = $j.Dossier.TrimEnd('\'); Jeu = $true } } }
    foreach ($d in $script:SS_DossiersMods) {
        $par = Split-Path $d.Chemin -Parent
        if ($par -and (Test-Path -LiteralPath (Join-Path $par 'logs')) -and -not $dossiers.Contains($par.ToLower())) { $dossiers[$par.ToLower()] = @{ Chemin = $par; Jeu = $false } }
    }
    foreach ($x in "$env:APPDATA\.minecraft", "$env:APPDATA\.tlauncher\legacy\Minecraft\game") {
        if ((Test-Path -LiteralPath (Join-Path $x 'logs')) -and -not $dossiers.Contains($x.ToLower())) { $dossiers[$x.ToLower()] = @{ Chemin = $x; Jeu = $false } }
    }
    $lunar = "$env:USERPROFILE\.lunarclient\logs"
    $alertes = 0; $nbFichiers = 0
    $serveurs = [ordered]@{}
    $traiter = {
        param([string]$Fichier, [string]$Etiquette, $Ids)
        $t = Read-Log $Fichier
        if (-not $t) { return }
        $script:SS_LogNb++
        $fi = Get-Item -LiteralPath $Fichier -Force
        $quand = Format-Date $fi.LastWriteTime
        $source = '[' + $Etiquette + '] ' + $fi.Name + ' · ' + $quand
        $lignes = $t -split "`r?`n"
        $vusL = $script:SS_LogVus; $nbIci = 0
        $dansListe = $false
        foreach ($l in $lignes) {
            if ($l -match 'Loading \d+ mods:') { $dansListe = $true; continue }
            if ($dansListe) {
                if ($l -match '^\t- ([A-Za-z0-9_\-\.]+) ') { if ($Ids -ne $null -and -not $Ids.ContainsKey($Matches[1])) { $Ids[$Matches[1]] = $fi.LastWriteTime }; continue }
                if ($l -match '^\t\s') { continue }
                $dansListe = $false
            }
            if ($l -match 'Connecting to ([^\s,]+),\s*(\d+)') { $cle = $Matches[1].ToLower(); if (-not $serveurs.Contains($cle)) { $serveurs[$cle] = $fi.LastWriteTime } elseif ($fi.LastWriteTime -gt $serveurs[$cle]) { $serveurs[$cle] = $fi.LastWriteTime }; continue }
            $chat = $l -match '\[CHAT\]'
            $type = $null; $niv = 'ORANGE'
            if ($l -match $SS_ReChatCheat) { $type = 'Message d''un client de triche dans le chat'; $niv = 'ROUGE' }
            elseif ($l -match $SS_ReToggle -and ($l -match '\[CHAT\]\s*(\[|§)' -or -not $chat)) { $type = 'Module de triche activé / désactivé'; $niv = 'ROUGE' }
            elseif (-not $chat -and $l -match $SS_ReClientLog) { $type = 'Client de triche dans les lignes techniques du jeu'; $niv = 'ROUGE' }
            elseif (-not $chat -and $l -match '(?i)\bbaritone\b') { $type = 'Baritone (bot de déplacement / minage)' }
            elseif ($l -match '(?i)(disconnect|kicked|lost connection|connection lost|déconnecté|expulsé)' -and $l -match '(?i)(cheat|hack|kill\s?aura|reach|fly|anti-?cheat|ban|sanction|triche)') { $type = 'Expulsé d''un serveur (motif lié à la triche)' }
            if (-not $type) { continue }
            $cle = $type + '|' + ($l -replace '^\[[^\]]*\]\s*', '' -replace '\d', '').Trim()
            if ($vusL.ContainsKey($cle)) { $vusL[$cle]++; continue }
            $vusL[$cle] = 1; $nbIci++
            if ($nbIci -gt 12) { break }
            $script:SS_LogAlertes++
            $extrait = ($l.Trim() -replace '§.', '')
            if ($extrait.Length -gt 220) { $extrait = $extrait.Substring(0, 220) + '…' }
            Add-Res Logs $niv ($type) ($extrait + ' · ' + $source) $Fichier
        }
    }
    $script:SS_LogNb = 0; $script:SS_LogAlertes = 0; $script:SS_LogVus = @{}
    foreach ($d in $dossiers.Values) {
        $l = Get-LauncherChemin $d.Chemin
        $etiq = Format-Launcher $l
        $ids = @{}
        $fichiers = @(Get-ChildItem -LiteralPath (Join-Path $d.Chemin 'logs') -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)\.log(\.gz)?$' -and $_.LastWriteTime -ge $depuis } | Sort-Object LastWriteTime -Descending | Select-Object -First 40)
        $crash = @(Get-ChildItem -LiteralPath (Join-Path $d.Chemin 'crash-reports') -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $depuis })
        if ($d.Jeu -and -not (Test-Path -LiteralPath (Join-Path $d.Chemin 'logs\latest.log'))) {
            $script:SS_LogAlertes++
            Add-Res Logs ORANGE ('Pas de latest.log alors que le jeu tourne : ' + $etiq) 'Le log de la partie en cours a été supprimé ou désactivé : demande au joueur pourquoi.' (Join-Path $d.Chemin 'logs')
        }
        if ($fichiers.Count -eq 0 -and $crash.Count -eq 0) { continue }
        foreach ($f in $fichiers) { & $traiter $f.FullName $etiq $ids; Invoke-Pompe }
        foreach ($f in $crash) {
            $t = Read-Log $f.FullName
            if ($t -match $SS_ReClientLog) { $script:SS_LogAlertes++; Add-Res Logs ROUGE 'Rapport de crash qui cite un client de triche' ($Matches[0] + ' · [' + $etiq + '] ' + $f.Name + ' · ' + (Format-Date $f.LastWriteTime)) $f.FullName }
        }
        # mods chargés pendant une partie passée mais absents aujourd'hui (fabric / quilt)
        if ($ids.Count) {
            $presents = @{}
            foreach ($jar in @(Get-ChildItem -LiteralPath (Join-Path $d.Chemin 'mods') -Filter *.jar -File -Force -ErrorAction SilentlyContinue)) { $id = Get-ModIdRapide $jar.FullName; if ($id) { $presents[$id.ToLower()] = $true } }
            $integres = '^(minecraft|java|fabricloader|quilt_loader|mixinextras|fabric-api-base|fabric-api|fabric|quilted_fabric_api|qsl)$'
            $partis = @($ids.Keys | Where-Object { $_ -notmatch $integres -and -not $presents.ContainsKey($_.ToLower()) } | Sort-Object)
            if ($partis.Count) {
                $script:SS_LogAlertes++
                $triche = @($partis | Where-Object { $_ -match $SS_RegexNom })
                $niv = $(if ($triche.Count) { 'ROUGE' } else { 'ORANGE' })
                $liste = ($partis | ForEach-Object { '{0} ({1:dd/MM})' -f $_, $ids[$_] }) -join ', '
                Add-Res Logs $niv ('Mods utilisés ces ' + $SS_LogJours + ' jours mais plus dans le dossier : ' + $etiq) ($liste + ' · ils apparaissent dans les logs d''une partie passée mais leur jar n''est plus là (supprimé, ou mod d''un autre profil)') (Join-Path $d.Chemin 'mods')
            }
        }
        Add-Res Logs INFO ('Logs lus : ' + $etiq) ('{0} fichier(s) de log et {1} rapport(s) de crash des {2} derniers jours · {3}' -f $fichiers.Count, $crash.Count, $SS_LogJours, $d.Chemin) (Join-Path $d.Chemin 'logs')
    }
    if (Test-Path -LiteralPath $lunar) {
        foreach ($f in @(Get-ChildItem -LiteralPath $lunar -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)\.log(\.gz)?$' -and $_.LastWriteTime -ge $depuis } | Select-Object -First 30)) { & $traiter $f.FullName 'Lunar Client' $null }
    }
    if ($serveurs.Count) {
        Add-Res Logs INFO ('Serveurs rejoints ces ' + $SS_LogJours + ' jours : ' + $serveurs.Count) (($serveurs.Keys | ForEach-Object { '{0} ({1:dd/MM HH:mm})' -f $_, $serveurs[$_] }) -join ', ')
    }
    if ($script:SS_LogNb -eq 0) { Add-Res Logs INFO 'Logs du jeu' ('Aucun log de moins de ' + $SS_LogJours + ' jours trouvé (jeu jamais lancé récemment, ou logs supprimés).') }
    elseif ($script:SS_LogAlertes -eq 0) { Add-Res Logs OK 'Logs du jeu' ('{0} fichier(s) lus : aucun client de triche, module activé, Baritone ni kick pour triche.' -f $script:SS_LogNb) }
}

function Get-ModIdRapide {
    param([string]$Chemin)
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Chemin)
        try {
            foreach ($nom in 'fabric.mod.json', 'quilt.mod.json') {
                $e = $zip.GetEntry($nom)
                if ($e) {
                    $m = [regex]::Match((Read-Entree $e), '"id"\s*:\s*"([^"]+)"')
                    if ($m.Success) { return $m.Groups[1].Value }
                }
            }
        } finally { $zip.Dispose() }
    } catch { }
    return $null
}

# Fenetres cachees a la capture (stream-proof) et overlays transparents
function Invoke-ScanStreamProof {
    Set-Etape 74 'Fenêtres cachées au stream / screenshare...'
    try { Initialize-Natif } catch { Add-Res Injection INFO 'Fenêtres stream-proof' ('Vérification impossible : ' + $_.Exception.Message); return }
    $procs = @{}
    foreach ($pr in @(Get-Process)) { $procs[[uint32]$pr.Id] = $pr }
    $legit = '(?i)^(1password|keepass.*|bitwarden|dashlane|lastpass|nordpass|proton ?pass)$'
    $overlayOk = '(?i)^(discord.*|nvcontainer|nvidia.*|steam.*|gameoverlayui.*|medal.*|obs.*|overwolf.*|rtss|msiafterburner|xboxgamebar|gamebar.*|explorer|textinputhost|shellexperiencehost|searchhost|startmenuexperiencehost|tiktok.*|lghub.*|razer.*|claude|code|chrome|msedge|firefox|opera.*|brave|applicationframehost|systemsettings|ctfmon|dwm|lockapp|widgets|powertoys.*|snippingtool|screenclippinghost|sharex|lively.*|wallpaper.*|rainmeter|msedgewebview2|teams|ms-teams|spotify|nahimic.*|armourycrate.*|signalrgb|icue|steelseries.*|amdrsserv|radeonsoftware|copilot|phoneexperiencehost)$'
    $cachees = 0; $overlays = 0
    foreach ($f in [SnowNatif]::Fenetres()) {
        if ($f.Pid -eq $PID) { continue }
        $pr = $procs[[uint32]$f.Pid]
        $nomP = "PID $($f.Pid)"; $chemin = ''
        if ($pr) { $nomP = $pr.ProcessName; $chemin = $pr.Path }
        $titre = $f.Titre
        if (-not $titre) { $titre = '(sans titre)' }
        $topmost = (($f.ExStyle -band 0x8) -ne 0)
        $transp = (($f.ExStyle -band 0x20) -ne 0) -and (($f.ExStyle -band 0x80000) -ne 0)
        if ($f.Affinite -ne 0) {
            if (-not $f.Visible) { continue }
            $cachees++
            if ($f.Affinite -eq 0x11) { $mode = 'invisible à la capture (WDA_EXCLUDEFROMCAPTURE)' } else { $mode = 'apparaît en noir à la capture (WDA_MONITOR)' }
            $niv = 'ORANGE'
            if ($nomP -match '(?i)^javaw?$' -or ($topmost -and $transp) -or $nomP -match $SS_RegexProgramme) { $niv = 'ROUGE' }
            if ($nomP -match $legit) { $niv = 'INFO' }
            Add-Res Injection $niv ('Fenêtre cachée au stream : ' + $nomP + '.exe') ("'{0}' · {1} · {2}x{3} · classe {4}. Le staff ne la voit PAS en screenshare : demande au joueur de la montrer." -f $titre, $mode, $f.Largeur, $f.Hauteur, $f.Classe) $chemin
            continue
        }
        if ($f.Visible -and $topmost -and $transp -and $f.Largeur -ge 300 -and $f.Hauteur -ge 200 -and $nomP -notmatch $overlayOk) {
            $overlays++
            $niv = 'ORANGE'
            if ($nomP -match '(?i)^javaw?$') { $niv = 'ROUGE' }
            Add-Res Injection $niv ('Overlay transparent par-dessus l''écran : ' + $nomP + '.exe') ("'{0}' · {1}x{2} · classe {3}. Fenêtre invisible qui se pose sur le jeu (ESP / HUD de triche possible)." -f $titre, $f.Largeur, $f.Hauteur, $f.Classe) $chemin
        }
    }
    if ($cachees -eq 0) { Add-Res Injection OK 'Fenêtres stream-proof' 'Aucune fenêtre cachée à la capture : tout ce qui est à l''écran est visible en screenshare.' }
    if ($overlays -eq 0) { Add-Res Injection OK 'Overlays' 'Aucun overlay transparent inconnu par-dessus l''écran.' }
}

function Invoke-ScanMinecraft {
    Set-Etape 8 'Recherche de Minecraft...'
    $script:SS_Jeux = @()
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
        if ($m.Success) { $script:SS_Jeux += [pscustomobject]@{ Pid = $p.ProcessId; Dossier = $gd } }
        Invoke-InfoLancement $p $cmd $(if ($m.Success) { $gd } else { '' })
        Invoke-ScanInjection $p $cmd
    }
    if ($nb -eq 0) { Add-Res Minecraft ORANGE 'Aucun Minecraft lancé' 'Demande au joueur de garder son jeu ouvert pendant le scan.' }
    Invoke-ScanLaunchers
}

# =====================================================================
#  Launchers et clients
# =====================================================================
$SS_LaunchersProc = @(
    @('(?i)^(MinecraftLauncher|Minecraft)\.exe$|Minecraft Launcher', 'Launcher officiel Minecraft'),
    @('(?i)lunar', 'Lunar Client'), @('(?i)feather', 'Feather Client'), @('(?i)badlion', 'Badlion Client'),
    @('(?i)modrinth|theseus', 'Modrinth App'), @('(?i)prismlauncher', 'Prism Launcher'), @('(?i)polymc', 'PolyMC'),
    @('(?i)multimc', 'MultiMC'), @('(?i)curseforge|overwolf', 'CurseForge'), @('(?i)atlauncher', 'ATLauncher'),
    @('(?i)gdlauncher', 'GDLauncher'), @('(?i)tlauncher', 'TLauncher (launcher cracké)'), @('(?i)sklauncher', 'SKLauncher (launcher cracké)'),
    @('(?i)labymod', 'LabyMod'), @('(?i)technic', 'Technic Launcher'), @('(?i)salwyrr', 'Salwyrr'), @('(?i)pvplounge', 'PvPLounge'),
    @('(?i)legacy.?launcher', 'Legacy Launcher (launcher cracké)'), @('(?i)hmcl', 'HMCL')
)

function Get-LauncherChemin {
    # Devine le launcher et l'instance a partir d'un chemin (dossier mods, gameDir...)
    param([string]$Chemin)
    $c = "$Chemin".TrimEnd('\') + '\'
    $regles = @(
        @('\\(?:ModrinthApp|com\.modrinth\.theseus)\\profiles\\([^\\]+)\\', 'Modrinth App'),
        @('\\PrismLauncher\\instances\\([^\\]+)\\', 'Prism Launcher'),
        @('\\PolyMC\\instances\\([^\\]+)\\', 'PolyMC'),
        @('\\MultiMC\\instances\\([^\\]+)\\', 'MultiMC'),
        @('\\curseforge\\minecraft\\Instances\\([^\\]+)\\', 'CurseForge'),
        @('\\ATLauncher\\instances\\([^\\]+)\\', 'ATLauncher'),
        @('\\gdlauncher[^\\]*\\(?:data\\)?instances\\([^\\]+)\\', 'GDLauncher'),
        @('\\\.technic\\modpacks\\([^\\]+)\\', 'Technic Launcher'),
        @('\\\.lunarclient\\profiles\\([^\\]+\\[^\\]+)\\', 'Lunar Client'),
        @('\\\.lunarclient\\()', 'Lunar Client'),
        @('\\\.feather\\user-mods\\([^\\]+)\\', 'Feather Client'),
        @('\\\.feather\\()', 'Feather Client'),
        @('\\Badlion Client\\()', 'Badlion Client'),
        @('\\\.tlauncher\\()', 'TLauncher (launcher cracké)'),
        @('\\labymod-neo\\()', 'LabyMod'),
        @('\\\.minecraft\\()', 'Launcher officiel / .minecraft')
    )
    foreach ($r in $regles) {
        $m = [regex]::Match($c, '(?i)' + $r[0])
        if ($m.Success) { return [pscustomobject]@{ Nom = $r[1]; Instance = $m.Groups[1].Value.Replace('\', ' / ') } }
    }
    return [pscustomobject]@{ Nom = 'Autre dossier'; Instance = '' }
}

function Format-Launcher {
    param($L)
    if ($L.Instance) { return ('{0} · {1}' -f $L.Nom, $L.Instance) }
    return $L.Nom
}

function Get-ClientJeu {
    # Client / chargeur de mods d'apres la ligne de commande Java
    param([string]$Cmd)
    $c = @()
    if ($Cmd -match '(?i)com\.moonsworth|\\\.lunarclient\\') { $c += 'Lunar Client' }
    if ($Cmd -match '(?i)\\\.feather\\|net\.digitalingot') { $c += 'Feather Client' }
    if ($Cmd -match '(?i)net\.badlion|Badlion Client') { $c += 'Badlion Client' }
    if ($Cmd -match '(?i)net\.labymod|labymod') { $c += 'LabyMod' }
    if ($Cmd -match '(?i)--fml\.neoForgeVersion\s+(\S+)') { $c += ('NeoForge ' + $Matches[1]) }
    elseif ($Cmd -match '(?i)net\.neoforged') { $c += 'NeoForge' }
    elseif ($Cmd -match '(?i)--fml\.forgeVersion\s+(\S+)') { $c += ('Forge ' + $Matches[1]) }
    elseif ($Cmd -match '(?i)cpw\.mods|net\.minecraftforge|FMLTweaker') { $c += 'Forge' }
    if ($Cmd -match '(?i)org\.quiltmc\.loader') { $v = ''; if ($Cmd -match '(?i)quilt-loader[-\\/](\d[\w.+-]*?)(\.jar|\\|/)') { $v = ' ' + $Matches[1] }; $c += ('Quilt' + $v) }
    elseif ($Cmd -match '(?i)net\.fabricmc\.loader') { $v = ''; if ($Cmd -match '(?i)fabric-loader[-\\/](\d[\w.+-]*?)(\.jar|\\|/)') { $v = ' ' + $Matches[1] }; $c += ('Fabric' + $v) }
    if ($Cmd -match '(?i)optifine') { $c += 'OptiFine' }
    if ($c.Count -eq 0) { $c += 'Vanilla (sans chargeur de mods)' }
    return ($c -join ' + ')
}

function Invoke-InfoLancement {
    param($Proc, [string]$Cmd, [string]$GameDir)
    # 1. Client / chargeur de mods
    Add-Res Minecraft INFO ('Client : ' + (Get-ClientJeu $Cmd)) ('PID ' + $Proc.ProcessId)
    # 2. Programme qui a lance le jeu (chaine des processus parents)
    $tous = @{}
    foreach ($x in @(Get-CimInstance Win32_Process)) { $tous[[int]$x.ProcessId] = $x }
    $cur = $Proc; $chaine = @()
    for ($i = 0; $i -lt 5; $i++) {
        $par = $tous[[int]$cur.ParentProcessId]
        if (-not $par -or ($par.CreationDate -and $cur.CreationDate -and $par.CreationDate -gt $cur.CreationDate)) { break }
        $chaine += $par; $cur = $par
    }
    $launcher = $null; $lanceur = $null
    foreach ($par in $chaine) {
        if ($par.Name -match '(?i)^(java|javaw)\.exe$' -and "$($par.CommandLine)" -match $SS_RegexJeu -and "$($par.CommandLine)" -notmatch '(?i)-jar\s') { continue }
        foreach ($l in $SS_LaunchersProc) { if ("$($par.Name) $($par.CommandLine)" -match $l[0]) { $launcher = $l[1]; $lanceur = $par; break } }
        if ($launcher) { break }
    }
    $direct = $null; if ($chaine.Count -gt 0) { $direct = $chaine[0] }
    if ($launcher) {
        Add-Res Minecraft INFO ('Lancé avec : ' + $launcher) ('{0} (PID {1}) · {2}' -f $lanceur.Name, $lanceur.ProcessId, $lanceur.ExecutablePath) $lanceur.ExecutablePath
    } elseif ($direct -and $direct.Name -match '(?i)^(explorer|cmd|powershell|pwsh|conhost|WindowsTerminal|OpenConsole)\.exe$') {
        Add-Res Minecraft ORANGE ('Minecraft lancé à la main (' + $direct.Name + ')') 'Pas lancé par un launcher : quelqu''un a tapé la commande Java lui-même (méthode utilisée pour charger des clients modifiés). Demande au joueur comment il lance son jeu.' $direct.ExecutablePath
    } elseif ($direct) {
        $niv = 'ORANGE'; if ("$($direct.Name) $($direct.ExecutablePath)" -match $SS_RegexNom -or (Test-SurUsb $direct.ExecutablePath)) { $niv = 'ROUGE' }
        Add-Res Minecraft $niv ('Lancé par un programme inconnu : ' + $direct.Name) ('PID {0} · {1} · ce n''est pas un launcher connu' -f $direct.ProcessId, $direct.ExecutablePath) $direct.ExecutablePath
    } else {
        $indice = $null
        if ($Cmd -match '(?i)-Dminecraft\.launcher\.brand=(\S+)') { $indice = $Matches[1] }
        $deduit = Format-Launcher (Get-LauncherChemin $(if ($GameDir) { $GameDir } else { "$($Proc.ExecutablePath)" }))
        $det = 'le launcher est fermé (normal pour beaucoup de launchers)'
        if ($indice) { $det += ' · marque déclarée par le launcher : ' + $indice }
        Add-Res Minecraft INFO ('Lancé avec : ' + $deduit + ' (déduit des dossiers)') $det
    }
    # 3. Jars du classpath : client de triche ou jar hors des dossiers du launcher
    $dejaVus = @{}
    foreach ($m in [regex]::Matches($Cmd, '(?i)(?<![\w\\])[A-Z]:\\[^;"*?<>|\s]+?\.jar(?![\w])')) {
        $j = $m.Value
        if ($dejaVus.ContainsKey($j.ToLower())) { continue }
        $dejaVus[$j.ToLower()] = $true
        $nom = Split-Path $j -Leaf
        if ($nom -eq 'theseus.jar' -and (Test-Path -LiteralPath $j) -and (Get-Item -LiteralPath $j).Length -lt 2MB) { continue }   # agent normal du Modrinth App
        if ($nom -match $SS_RegexNom -and $nom -notmatch '(?i)^(authlib|brigadier|datafixerupper)') {
            Add-Res Minecraft ROUGE ('Client suspect dans le classpath : ' + $nom) 'Le jeu a été lancé avec ce jar : nom de client de triche' $j
        } elseif ($j -match '(?i)\\(Downloads|Téléchargements|Desktop|Bureau|Temp)\\' -or (Test-SurUsb $j)) {
            $an = Get-AnalyseJar $j $nom
            $niv = $(if ($an.Niveau -eq 'ROUGE') { 'ROUGE' } else { 'ORANGE' })
            $det = 'le jeu charge ce jar hors des dossiers du launcher'
            if ($an.Raisons) { $det = $an.Raisons + ' · ' + $det }
            Add-Res Minecraft $niv ('Jar chargé depuis un dossier inhabituel : ' + $nom) $det $j
        }
    }
}

function Invoke-ScanLaunchers {
    Set-Etape 12 'Launchers et clients installés...'
    $mc = "$env:APPDATA\.minecraft"
    $connus = [ordered]@{
        'Launcher officiel Minecraft' = @("$mc\launcher_profiles.json", "$mc\launcher_accounts_microsoft_store.json", "${env:ProgramFiles(x86)}\Minecraft Launcher")
        'Lunar Client'     = @("$env:USERPROFILE\.lunarclient")
        'Feather Client'   = @("$env:APPDATA\.feather")
        'Badlion Client'   = @("$env:APPDATA\Badlion Client", "$env:LOCALAPPDATA\Programs\Badlion Client")
        'Modrinth App'     = @("$env:APPDATA\ModrinthApp", "$env:APPDATA\com.modrinth.theseus")
        'Prism Launcher'   = @("$env:APPDATA\PrismLauncher")
        'PolyMC'           = @("$env:APPDATA\PolyMC")
        'CurseForge'       = @("$env:USERPROFILE\curseforge\minecraft")
        'ATLauncher'       = @("$env:APPDATA\ATLauncher")
        'GDLauncher'       = @("$env:APPDATA\gdlauncher_next", "$env:APPDATA\gdlauncher_carbon")
        'LabyMod'          = @("$mc\labymod-neo", "$env:LOCALAPPDATA\Programs\labymodlauncher")
        'Technic Launcher' = @("$env:APPDATA\.technic")
        'TLauncher (cracké)'  = @("$env:APPDATA\.tlauncher")
        'SKLauncher (cracké)' = @("$mc\sklauncher", "$env:APPDATA\.sklauncher")
    }
    $trouves = @()
    foreach ($k in $connus.Keys) { foreach ($ch in $connus[$k]) { if ($ch -and (Test-Path -LiteralPath $ch)) { $trouves += $k; break } } }
    if ($trouves.Count) { Add-Res Minecraft INFO ('Launchers / clients installés : ' + $trouves.Count) ($trouves -join ', ') }
    else { Add-Res Minecraft INFO 'Launchers / clients installés' 'Aucun launcher connu trouvé : demande au joueur lequel il utilise.' }

    # Versions installees dans .minecraft : un client de triche s'installe souvent comme une version
    if (Test-Path -LiteralPath "$mc\versions") {
        $perso = 0
        foreach ($v in @(Get-ChildItem -LiteralPath "$mc\versions" -Directory -Force)) {
            $n = $v.Name
            if ($n -match '^\d+\.\d+(\.\d+)?([- ](pre|rc|snapshot|pre-release|release-candidate)[- ]?\d+)?$|^\d\dw\d\d[a-z]$|^fabric-loader-|^quilt-loader-|-forge-|^forge-|^neoforge-|-OptiFine_|^OptiFine|^LabyMod|^Badlion|^lunar') { continue }
            $jar = Join-Path $v.FullName ($n + '.jar')
            $niv = 'INFO'; $det = 'version personnalisée installée le ' + (Format-Date $v.CreationTime)
            if ($n -match $SS_RegexNom) { $niv = 'ROUGE'; $det = 'nom de client de triche · ' + $det }
            if ((Test-Path -LiteralPath $jar) -and (Get-Item -LiteralPath $jar).Length -lt 80MB) {
                $an = Get-AnalyseJar $jar ($n + '.jar')
                if ($an.Niveau -eq 'ROUGE') { $niv = 'ROUGE'; $det = $an.Raisons + ' · ' + $det }
                elseif ($an.Niveau -and $niv -eq 'INFO' -and $an.Raisons -notmatch 'aucun fichier de mod') { $niv = 'ORANGE'; $det = $an.Raisons + ' · ' + $det }
            }
            $perso++
            Add-Res Minecraft $niv ('Version de jeu : ' + $n) $det $v.FullName
            if ($perso -ge 25) { break }
        }
    }
    # Profils du launcher officiel : arguments Java caches (agent injecte a chaque lancement)
    foreach ($fp in "$mc\launcher_profiles.json", "$mc\launcher_profiles_microsoft_store.json") {
        if (-not (Test-Path -LiteralPath $fp)) { continue }
        try { $js = [IO.File]::ReadAllText($fp) | ConvertFrom-Json } catch { continue }
        if (-not $js.profiles) { continue }
        foreach ($pp in $js.profiles.PSObject.Properties) {
            $pr = $pp.Value; $nomP = "$($pr.name)"; if (-not $nomP) { $nomP = $pp.Name }
            $ja = "$($pr.javaArgs)"
            if ($ja -match '(?i)-javaagent|-agentpath|-agentlib:(?!jdwp)|-Xbootclasspath|-noverify') {
                Add-Res Minecraft ROUGE ('Profil du launcher avec injection : ' + $nomP) ('arguments Java : ' + $ja) $fp
            }
            if ("$($pr.lastVersionId)" -match $SS_RegexNom) { Add-Res Minecraft ROUGE ('Profil du launcher sur une version suspecte : ' + $nomP) ('version : ' + $pr.lastVersionId) $fp }
        }
    }
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
        "$env:USERPROFILE\.lunarclient\profiles\*\*\mods",
        "$env:APPDATA\PolyMC\instances\*\.minecraft\mods",
        "$env:APPDATA\ATLauncher\instances\*\mods",
        "$env:APPDATA\gdlauncher_next\instances\*\mods",
        "$env:APPDATA\gdlauncher_carbon\data\instances\*\instance\mods",
        "$env:APPDATA\.technic\modpacks\*\mods",
        "$env:APPDATA\.minecraft\labymod-neo\addons",
        "$env:APPDATA\ModrinthApp\profiles\*\resourcepacks",
        "$env:APPDATA\PrismLauncher\instances\*\.minecraft\resourcepacks",
        "$env:USERPROFILE\curseforge\minecraft\Instances\*\resourcepacks"
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
        $l = Get-LauncherChemin $plein
        $dossiers += [pscustomobject]@{ Chemin = $plein; Jeu = $d.Jeu; Packs = ((Split-Path $plein -Leaf) -eq 'resourcepacks'); Launcher = $l.Nom; Etiquette = (Format-Launcher $l) }
    }
    if ($dossiers.Count -eq 0) { Add-Res Mods INFO 'Aucun dossier mods trouvé' 'Le joueur utilise peut-être un launcher non reconnu : demande-lui où sont ses mods.' }
    # le dossier du jeu lance passe en premier, puis tri par launcher et instance
    $dossiers = @($dossiers | Sort-Object @{ Expression = { -not $_.Jeu } }, Launcher, Etiquette, Packs)

    $jars = @()
    $parLauncher = [ordered]@{}
    $ordre = 0
    foreach ($d in $dossiers) {
        $ordre++
        $tag = ''
        if ($d.Jeu) { $tag = '  (JEU LANCÉ)' }
        if ($d.Packs) {
            $packs = @(Get-ChildItem -LiteralPath $d.Chemin -Force)
            $d | Add-Member -NotePropertyName Entete -NotePropertyValue @('INFO', ('{0} · packs de textures : {1}{2}' -f $d.Etiquette, $packs.Count, $tag))
            $d | Add-Member -NotePropertyName Alertes -NotePropertyValue @($packs | Where-Object { $_.Name -match '(?i)x-?ray|ore.?(esp|finder)|see.?through' })
            continue
        }
        $fichiers = @(Get-ChildItem -LiteralPath $d.Chemin -Recurse -Depth 1 -File -Force)
        $lesJars = @($fichiers | Where-Object { $_.Extension -eq '.jar' })
        if (-not $parLauncher.Contains($d.Launcher)) { $parLauncher[$d.Launcher] = 0 }
        $parLauncher[$d.Launcher] += $lesJars.Count
        $d | Add-Member -NotePropertyName Entete -NotePropertyValue @('INFO', ('{0} : {1} mod(s){2}' -f $d.Etiquette, $lesJars.Count, $tag))
        $d | Add-Member -NotePropertyName Alertes -NotePropertyValue @($fichiers | Where-Object { $_.Extension -match '(?i)^\.(exe|dll|zip|rar|7z|class|bat|cmd|ps1|vbs)$' })
        foreach ($f in $lesJars) {
            $jars += [pscustomobject]@{ Nom = $f.Name; Chemin = $f.FullName; Modif = $f.LastWriteTime; Jeu = $d.Jeu; Sha1 = $null; Ordre = $ordre; Dossier = $d }
        }
    }
    if ($parLauncher.Count) { Add-Res Mods INFO 'Mods par launcher' (($parLauncher.Keys | ForEach-Object { '{0} : {1}' -f $_, $parLauncher[$_] }) -join ' · ') }
    # en-tete de chaque dossier (les dossiers sans jar ou de packs sont affiches tout de suite)
    $afficherEntete = {
        param($d)
        if ($d.PSObject.Properties['Fait']) { return }
        $d | Add-Member -NotePropertyName Fait -NotePropertyValue $true
        Add-Res Mods $d.Entete[0] ('▸ ' + $d.Entete[1]) $d.Chemin $d.Chemin $d.Launcher
        foreach ($a in $d.Alertes) {
            if ($d.Packs) { Add-Res Mods ORANGE 'Pack de textures X-Ray' ('[' + $d.Etiquette + '] ' + $a.Name) $a.FullName $d.Launcher }
            else { Add-Res Mods ORANGE 'Fichier bizarre dans un dossier mods' ('[' + $d.Etiquette + '] ' + $a.Name) $a.FullName $d.Launcher }
        }
    }
    # affiche dans l'ordre tous les en-tetes jusqu'au dossier n (les dossiers vides ou de packs restent a leur place)
    $script:SS_EnteteSuivant = 0
    $entetesJusqua = {
        param([int]$n)
        while ($script:SS_EnteteSuivant -lt [Math]::Min($n, $dossiers.Count)) { & $afficherEntete $dossiers[$script:SS_EnteteSuivant]; $script:SS_EnteteSuivant++ }
    }

    $script:SS_NbJars = $jars.Count
    Set-Etape 22 ('Calcul des empreintes ({0} jars)...' -f $jars.Count)
    foreach ($j in $jars) { $j.Sha1 = (Get-FileHash -LiteralPath $j.Chemin -Algorithm SHA1).Hash.ToLower(); Invoke-Pompe }
    $hashes = @($jars | Where-Object { $_.Sha1 } | ForEach-Object { $_.Sha1 } | Sort-Object -Unique)
    Set-Etape 28 'Vérification auprès de Modrinth...'
    $modrinth = Get-InfosModrinth $hashes

    $n = $jars.Count; $i = 0
    foreach ($j in ($jars | Sort-Object Ordre, Nom)) {
        $i++
        Set-Etape (30 + [int](35 * $i / [Math]::Max(1, $n))) ('Analyse des mods ({0}/{1})...' -f $i, $n)
        & $entetesJusqua $j.Ordre
        $recent = ' · [' + $j.Dossier.Etiquette + ']'
        if ($j.Modif -ge $script:SS_Depuis) { $recent = (' · modifié le {0:dd/MM HH:mm}' -f $j.Modif) + $recent }
        if ($j.Jeu -and $script:SS_LancementJeu -and $j.Modif -gt $script:SS_LancementJeu) {
            Add-Res Mods ORANGE ('Jar modifié APRÈS le lancement du jeu : ' + $j.Nom) ('modifié le {0}' -f (Format-Date $j.Modif)) $j.Chemin $j.Dossier.Launcher
        }
        $info = $null
        if ($j.Sha1 -and $modrinth.ContainsKey($j.Sha1)) { $info = $modrinth[$j.Sha1] }
        $connu = ($info -and $info.Projet)
        if ($connu -and $info.Projet.downloads -ge $SS_SeuilModrinth) {
            Add-Res Mods OK $j.Nom ('{0} {1} · {2:N0} téléchargements sur Modrinth{3}' -f $info.Projet.title, $info.Version, $info.Projet.downloads, $recent) $j.Chemin $j.Dossier.Launcher
            if ($info.Projet.slug -match $SS_RegexInterdit) { Add-Res Mods ORANGE ('Mod interdit sur la plupart des serveurs : ' + $info.Projet.title) $j.Nom $j.Chemin $j.Dossier.Launcher }
            continue
        }
        $an = Get-AnalyseJar $j.Chemin $j.Nom
        $source = 'pas sur Modrinth (peut venir de CurseForge ou d''ailleurs)'
        if ($connu) { $source = ('sur Modrinth mais peu téléchargé : {0} ({1:N0})' -f $info.Projet.title, $info.Projet.downloads) }
        $titre = $j.Nom
        if ($an.ModId) { $titre += "  [id: $($an.ModId)]" }
        if ($an.Niveau) { Add-Res Mods $an.Niveau $titre ($an.Raisons + ' · ' + $source + $recent) $j.Chemin $j.Dossier.Launcher }
        else { Add-Res Mods INFO $titre ($source + ', rien de suspect dedans' + $recent) $j.Chemin $j.Dossier.Launcher }
    }
    & $entetesJusqua $dossiers.Count
}

$SS_RegexOuvreurConnu = '(?i)^(csrss|lsass|svchost|wininit|services|smss|MsMpEng|NisSrv|SecurityHealthService|MpDefenderCoreService|audiodg|dwm|explorer|taskmgr|sihost|ctfmon|WmiPrvSE|RuntimeBroker|SearchHost|StartMenuExperienceHost|ShellExperienceHost|ApplicationFrameHost|Discord|DiscordCanary|DiscordPTB|Medal|MedalEncoder|obs64|obs32|obs-ffmpeg-mux|nvcontainer|NVIDIA Share|NVIDIA Overlay|NVIDIA app|nvsphelper64|RadeonSoftware|amdow|AMDRSServ|AMDRSSrcExt|atieclxx|steam|steamwebhelper|GameBar|GameBarFTServer|GameBarPresenceWriter|XboxGameBarWidgets|Overwolf|OverwolfHelper64|ShareX|avp|AvastSvc|AvastUI|avgsvc|ekrn|bdservicehost|MBAMService|vgc|vgtray|EasyAntiCheat|BEService|Lunar Client|Feather Launcher|Badlion Client|Modrinth App|prismlauncher|MinecraftLauncher|CurseForge|ATLauncher|GDLauncher|PolyMC|MultiMC|MSIAfterburner|RTSS|RTSSHooksLoader64|EncoderServer|Spotify|WerFault|WerFaultSecure|Lightshot|Gyazo|SteelSeriesGG|lghub_agent|NahimicSvc64|Nahimic3)$'
$SS_RoleConnu = @(
    @('(?i)^(Medal|MedalEncoder)$', 'Medal : enregistrement de clips'),
    @('(?i)^obs', 'OBS : enregistrement / stream'),
    @('(?i)^Discord', 'Discord : détection du jeu / overlay'),
    @('(?i)^(nv|NVIDIA)', 'NVIDIA : overlay / enregistrement'),
    @('(?i)^(Radeon|amd|AMD|atie)', 'AMD : overlay / enregistrement'),
    @('(?i)^(csrss|lsass|svchost|wininit|services|smss|dwm|explorer|sihost|ctfmon|WmiPrvSE|RuntimeBroker|audiodg|taskmgr)', 'Windows'),
    @('(?i)^(MsMpEng|NisSrv|SecurityHealth|MpDefender|avp|Avast|avg|ekrn|bdservice|MBAM)', 'antivirus'),
    @('(?i)^(vgc|EasyAntiCheat|BEService)', 'anti-cheat d''un autre jeu'),
    @('(?i)^(GameBar|XboxGameBar)', 'Xbox Game Bar'),
    @('(?i)^(steam|Overwolf|MSIAfterburner|RTSS)', 'overlay / FPS')
)

function Format-Droits {
    param([uint32]$d)
    if (($d -band 0x1FFFFF) -eq 0x1FFFFF) { return 'accès total (lire, écrire, injecter)' }
    $l = @()
    if ($d -band 0x20) { $l += 'écrire dans la mémoire' }
    if ($d -band 0x10) { $l += 'lire la mémoire' }
    if ($d -band 0x2) { $l += 'lancer du code dans le jeu' }
    if ($d -band 0x8) { $l += 'modifier la mémoire' }
    if ($d -band 0x800) { $l += 'mettre le jeu en pause' }
    if ($d -band 0x1) { $l += 'fermer le jeu' }
    if ($d -band 0x40) { $l += 'copier ses poignées' }
    if ($l.Count -eq 0) { $l += 'consulter seulement' }
    return ($l -join ', ')
}

function Invoke-ScanAccesJeu {
    # Quels programmes ont « ouvert » le processus de Minecraft, et avec quels droits
    Set-Etape 67 'Programmes qui ouvrent Minecraft...'
    $jeux = @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object { "$($_.CommandLine)" -match $SS_RegexJeu -or -not $_.CommandLine })
    if ($jeux.Count -eq 0) { Add-Res Programmes INFO 'Programmes qui ouvrent Minecraft' 'Non vérifié : Minecraft n''est pas lancé.'; return }
    try { Initialize-Poignees } catch { Add-Res Programmes INFO 'Programmes qui ouvrent Minecraft' ('Vérification impossible : ' + $_.Exception.Message); return }
    $tous = @{}; foreach ($x in @(Get-CimInstance Win32_Process)) { $tous[[int]$x.ProcessId] = $x }
    $suspects = 0
    foreach ($jeu in $jeux) {
        $liste = $null; $mode = ''; $err = $null; $ill = 0
        if ($script:SS_Admin) {
            try { [SnowPoignees]::ActiverDebug(); $liste = [SnowPoignees]::Ouvreurs([uint32]$jeu.ProcessId, [ref]$err); $mode = 'complet' } catch { $liste = $null }
        }
        if ($null -eq $liste) {
            try { $liste = [SnowPoignees]::OuvreursUtilisateur([uint32]$jeu.ProcessId, [ref]$ill); $mode = 'utilisateur' } catch { $liste = $null }
        }
        if ($null -eq $liste) { Add-Res Programmes INFO 'Programmes qui ouvrent Minecraft' 'Vérification impossible sur ce PC.'; continue }
        foreach ($a in ($liste | Sort-Object { -[int](($_.Droits -band 0x32) -ne 0) }, Pid)) {
            $pr = $tous[[int]$a.Pid]
            $nom = $(if ($pr) { $pr.Name -replace '\.exe$', '' } else { "PID $($a.Pid)" })
            $chemin = $(if ($pr) { "$($pr.ExecutablePath)" } else { '' })
            $droits = Format-Droits $a.Droits
            $det = ('{0} · PID {1}{2}' -f $droits, $a.Pid, $(if ($chemin) { ' · ' + $chemin } else { '' }))
            if ([int]$a.Pid -eq [int]$jeu.ParentProcessId) {
                Add-Res Programmes INFO ('Ouvre Minecraft : ' + $nom + ' (le launcher qui a lancé le jeu)') $det $chemin; continue
            }
            if ($nom -match $SS_RegexOuvreurConnu -and -not (Test-SurUsb $chemin)) {
                $role = 'programme connu'
                foreach ($r in $SS_RoleConnu) { if ($nom -match $r[0]) { $role = $r[1]; break } }
                Add-Res Programmes INFO ('Ouvre Minecraft : ' + $nom + ' (' + $role + ')') $det $chemin; continue
            }
            $ecrit = ($a.Droits -band 0x2A) -ne 0
            $lit = ($a.Droits -band 0x10) -ne 0
            $signe = $false
            $interprete = $nom -match '(?i)^(powershell|pwsh|python\w*|pythonw|java|javaw|cmd|wscript|cscript|mshta|rundll32|node|autohotkey\w*)$'
            if ($chemin -and -not $interprete -and (Test-Path -LiteralPath $chemin)) { try { $signe = ((Get-AuthenticodeSignature -LiteralPath $chemin).Status -eq 'Valid') } catch { } }
            if ($interprete -and $pr -and $pr.CommandLine) { $det += ' · script lancé : ' + ("$($pr.CommandLine)".Substring(0, [Math]::Min(180, "$($pr.CommandLine)".Length))) }
            if ($ecrit) {
                $suspects++
                $niv = $(if ($signe -and $nom -notmatch $SS_RegexNom -and $nom -notmatch $SS_RegexProgramme) { 'ORANGE' } else { 'ROUGE' })
                Add-Res Programmes $niv ('Peut MODIFIER Minecraft : ' + $nom) ($det + ' · ' + $(if ($signe) { 'programme signé' } else { 'programme NON signé' }) + ' : un programme inconnu qui écrit dans le jeu = injecteur ou cheat externe possible') $chemin
            } elseif ($lit) {
                $suspects++
                Add-Res Programmes ORANGE ('LIT la mémoire de Minecraft : ' + $nom) ($det + ' · peut servir à un cheat externe (ESP, radar) : demande au joueur ce que c''est') $chemin
            } else {
                Add-Res Programmes INFO ('Ouvre Minecraft : ' + $nom) ($det + ' · ne peut ni lire ni modifier le jeu') $chemin
            }
        }
        if ($suspects -eq 0) { Add-Res Programmes OK 'Programmes qui touchent à Minecraft' ('Aucun programme inconnu ne lit ni ne modifie le jeu (PID {0}).' -f $jeu.ProcessId) }
        if ($mode -eq 'utilisateur' -and $ill -gt 0) {
            Add-Res Programmes INFO 'Programmes protégés non vérifiés' ("$ill programme(s) système ou lancés en administrateur n'ont pas pu être vérifiés : relance l'outil en administrateur pour tout voir.")
        }
    }
}

function Invoke-ScanProgrammes {
    Invoke-ScanAccesJeu
    Set-Etape 68 'Programmes ouverts...'
    $rien = $true
    foreach ($pr in @(Get-CimInstance Win32_Process)) {
        if ($pr.Name -match $SS_RegexProgramme -or $pr.ExecutablePath -match $SS_RegexProgramme) {
            Add-Res Programmes ORANGE ('Programme suspect ouvert : ' + $pr.Name) ('PID {0} · {1}' -f $pr.ProcessId, $pr.ExecutablePath) $pr.ExecutablePath
            $rien = $false
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
    try { Initialize-Prefetch } catch { }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings\$sid"
    if (-not (Test-Path $cle)) { $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings\$sid" }
    $entrees = @()
    $props = Get-ItemProperty -Path $cle
    if ($props) {
        foreach ($pp in $props.PSObject.Properties) {
            if ($pp.Value -is [byte[]] -and $pp.Value.Length -ge 8) {
                $date = [DateTime]::FromFileTime([BitConverter]::ToInt64($pp.Value, 0))
                if ($date -ge $script:SS_Depuis) { $entrees += [pscustomobject]@{ Date = $date; Exe = (Convert-CheminWindows $pp.Name) } }
            }
        }
    }
    # pendant la partie (depuis 10 min avant le lancement du jeu) : détaillé ; avant : résumé en une ligne
    $debutPartie = $null
    if ($script:SS_LancementJeu) { $debutPartie = $script:SS_LancementJeu.AddMinutes(-10) }
    $avant = @()
    foreach ($en in ($entrees | Sort-Object Date -Descending)) {
        $nom = Split-Path $en.Exe -Leaf
        $pendant = ($debutPartie -and $en.Date -ge $debutPartie)
        if ($nom -match '(?i)^inject-helper') {
            $avis = Get-AvisInjectHelper $en.Exe
            Add-Res Programmes $avis[0] ($(if ($pendant) { 'Lancé PENDANT la partie : ' } else { 'Lancé récemment : ' }) + $nom) ('{0} · {1} · {2}' -f (Format-Date $en.Date), $en.Exe, $avis[1]) $en.Exe
        }
        elseif ($en.Exe -match $SS_RegexProgramme) { Add-Res Programmes ORANGE ($(if ($pendant) { 'Lancé PENDANT la partie : ' } else { 'Lancé récemment : ' }) + $nom) ('{0} · {1}' -f (Format-Date $en.Date), $en.Exe) }
        elseif ($pendant) { Add-Res Programmes INFO ('Lancé pendant la partie : ' + $nom) ('{0} · {1}' -f (Format-Date $en.Date), $en.Exe) }
        else { $avant += $nom }
    }
    if ($avant.Count) { Add-Res Programmes INFO ("$($avant.Count) autre(s) programme(s) lancé(s) avant la partie") (($avant | Select-Object -Unique -First 40) -join ', ') }
    $pf = @(Get-ChildItem -Path "$env:windir\Prefetch" -Filter *.pf -Force | Where-Object { $_.LastWriteTime -ge $script:SS_Depuis -and $_.Name -match $SS_RegexProgramme })
    foreach ($f in $pf) {
        $exe = $null
        if ('SnowPrefetch' -as [type]) { try { $brut = [SnowPrefetch]::Exe($f.FullName); if ($brut) { $exe = Convert-CheminWindows $brut } } catch { } }
        $quand = 'lancé le ' + (Format-Date $f.LastWriteTime)
        if ($f.Name -match '(?i)^INJECT-HELPER') {
            if (-not $exe) { $exe = Find-InjectHelperParHash $f.Name }
            if ($exe) {
                $avis = Get-AvisInjectHelper $exe
                Add-Res Programmes $avis[0] ('Prefetch : ' + $f.Name) ('{0} · {1} · {2}' -f $quand, $exe, $avis[1]) $f.FullName
            } else {
                Add-Res Programmes ORANGE ('Prefetch : ' + $f.Name) ($quand + ' · chemin de l''exe illisible et absent des dossiers de Medal / OBS : impossible de vérifier que c''est leur outil de capture') $f.FullName
            }
        } else { Add-Res Programmes ORANGE ('Prefetch : ' + $f.Name) ($quand + $(if ($exe) { ' · ' + $exe })) $f.FullName }
    }
    if ($pf.Count -eq 0) { Add-Res Programmes OK 'Prefetch' 'Aucun programme suspect lancé récemment.' }
}

# =====================================================================
#  Macros / autoclickers
# =====================================================================
$SS_RegexMacroProg = '(?i)(autohotkey|\.ahk2?\b|tinytask|pulover|macro.?creator|macro.?recorder|jitbit|macro|auto.?click|clicker|op.?auto|gs.?auto|murgee|speed.?auto|ghost.?mouse|mouse.?recorder|keyran|xmouse|x-mouse|interception)'
$SS_RegexMacroClic = '(?i)(auto.?click|clicker|tinytask|op.?auto|gs.?auto|murgee|speed.?auto|ghost.?mouse)'
$SS_RegexNomMacro  = '(?i)(?<![a-z0-9])(auto[ _-]?click(er|ing)?|rapid[ _-]?fire|butterfly|jitter[ _-]?click|drag[ _-]?click|spam[ _-]?click|turbo[ _-]?click|double[ _-]?click|clicker|god[ _-]?bridg\w*|\d{1,2}[ _-]?cps)(?![a-z])'
$SS_RegexLogicielSouris = '(?i)(g hub|logitech gaming software|razer synapse|razer central|steelseries gg|steelseries engine|icue|bloody|glorious core|roccat swarm|ngenuity|x-?mouse button control)'

function Get-FichiersProfonds {
    param([string[]]$Racines, [string]$RegexNom, [int]$Prof = 3, [int]$Max = 3000)
    $ignore = '(?i)^(cache|code cache|gpucache|dawncache|crashpad|crashdumps|blob_storage|indexeddb|service worker|session storage|logs?|node_modules|\.git|shadercache|webcache|temp|tmp|windowsapps)$'
    $out = New-Object System.Collections.Generic.List[string]
    $pile = New-Object System.Collections.Generic.Stack[object]
    foreach ($r in $Racines) { if ($r -and [IO.Directory]::Exists($r)) { $pile.Push(@($r, 0)) } }
    $vus = 0
    while ($pile.Count -gt 0 -and $vus -lt $Max) {
        $e = $pile.Pop(); $d = [string]$e[0]; $n = [int]$e[1]
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($d)) {
                $vus++
                if ([IO.Path]::GetFileName($f) -match $RegexNom) { $out.Add($f) }
                if ($vus % 400 -eq 0) { Invoke-Pompe }
                if ($vus -ge $Max) { break }
            }
        } catch { }
        if ($n -lt $Prof) {
            try { foreach ($s in [IO.Directory]::EnumerateDirectories($d)) { if ([IO.Path]::GetFileName($s) -notmatch $ignore) { $pile.Push(@($s, ($n + 1))) } } } catch { }
        }
    }
    return ,$out
}

function Read-TexteBrut {
    param([string]$Fichier, [long]$Max = 26214400)
    try {
        $fs = New-Object IO.FileStream($Fichier, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            if ($fs.Length -eq 0 -or $fs.Length -gt $Max) { return '' }
            $b = New-Object byte[] $fs.Length
            $lu = 0
            while ($lu -lt $b.Length) { $k = $fs.Read($b, $lu, $b.Length - $lu); if ($k -le 0) { break }; $lu += $k }
        } finally { $fs.Close() }
        $t = [Text.Encoding]::GetEncoding(28591).GetString($b)
        $zeros = 0; $ech = [Math]::Min($b.Length, 4000)
        for ($i = 1; $i -lt $ech; $i += 2) { if ($b[$i] -eq 0) { $zeros++ } }
        if ($ech -gt 0 -and $zeros -gt ($ech / 4)) { $t += "`n" + [Text.Encoding]::Unicode.GetString($b) }
        elseif ($t -match '[\xC3\xC5][\x80-\xBF]') { $t += "`n" + [Text.Encoding]::UTF8.GetString($b) }
        return $t
    } catch { return '' }
}

function Get-AnalyseMacro {
    # Dit si un script (AutoHotkey, Lua Logitech, AutoIt, Python...) clique tout seul
    param([string]$Texte)
    if (-not $Texte) { return $null }
    $clic   = $Texte -match '(?im)(^\s*(Click|MouseClick|ControlClick)\b|\bClick\s*\(|\bSend(Input|Play|Event)?\b[^\r\n]{0,40}\{\s*(Click|LButton|RButton)|\bPress(AndRelease)?MouseButton\s*\(|\bmouse_event\b|\bpyautogui\.click|\bmouse\.click|\bpynput\b[\s\S]{0,400}\.click|\bxdotool\s+click|\bydotool\s+click|\bMouseClick\s*\()'
    $boucle = $Texte -match '(?im)(^\s*(Loop|While|SetTimer|repeat|for|Do)\b|\bwhile\s*\(|\bwhile\s+true|\bSetTimer\b|\brepeat\b[\s\S]{0,600}\buntil\b)'
    $tient  = $Texte -match '(?im)(GetKeyState\s*\(?\s*"?(LButton|RButton|XButton[12])|IsMouseButtonPressed\s*\(|^\s*[~$*!^+#]*(LButton|RButton|XButton1|XButton2|MButton)(\s+up)?\s*::)'
    $hasard = ($Texte -match '(?i)\bRandom\b|math\.random|random\.(uniform|randint)') -and ($Texte -match '(?i)\bSleep\b|time\.sleep')
    $bouge  = $Texte -match '(?i)\bMoveMouseRelative\s*\(|\bMouseMove\b[^\r\n]{0,40},\s*R\b|\bmouse\.move\(|\bmoveRel\('
    if ($clic -and ($boucle -or $tient)) {
        $r = 'AUTOCLICKER : envoie des clics de souris en boucle'
        if ($tient) { $r += ' tant qu''un bouton est maintenu' }
        if ($hasard) { $r += ', avec un délai aléatoire pour paraître humain' }
        return @{ Niveau = 'ROUGE'; Raison = $r }
    }
    if ($bouge -and ($boucle -or $tient)) { return @{ Niveau = 'ORANGE'; Raison = 'déplace la souris tout seul en boucle (anti-recul / visée)' } }
    if ($clic) { return @{ Niveau = 'ORANGE'; Raison = 'envoie des clics de souris' } }
    return $null
}

function Test-ExeAutoHotkey {
    param([string]$Fichier)
    $t = Read-TexteBrut $Fichier 12582912
    if (-not $t) { return $false }
    return ($t -match 'AUTOHOTKEY SCRIPT' -or $t -match 'A.U.T.O.H.O.T.K.E.Y. .S.C.R.I.P.T' -or $t -match '(?i)AutoHotkey(SC)?\.exe|www\.autohotkey\.com')
}

function Invoke-ScanMacros {
    Set-Etape 73 'Macros et autoclickers...'
    $alerte = 0
    $vus = @{}
    $extUsb = @()
    foreach ($u in $script:SS_Usb) { $extUsb += ($u.Lettre + '\') }

    # 1. Programmes de macro ouverts (AutoHotkey, TinyTask, autoclickers, logiciels de souris)
    foreach ($pr in @(Get-CimInstance Win32_Process)) {
        $exe = "$($pr.ExecutablePath)"
        if ($pr.Name -match '(?i)^autohotkey') {
            $scr = $null
            if ($pr.CommandLine -match '(?i)"?([^"]+\.ahk2?)"?\s*$' -or $pr.CommandLine -match '(?i)"([^"]+\.ahk2?)"') { $scr = $Matches[1] }
            $alerte++
            if ($scr -and (Test-Path -LiteralPath $scr)) {
                $vus[$scr.ToLower()] = $true
                $an = Get-AnalyseMacro (Read-TexteBrut $scr)
                if ($an) { Add-Res Macros $an.Niveau ('Script AutoHotkey EN COURS : ' + (Split-Path $scr -Leaf)) $an.Raison $scr }
                else { Add-Res Macros ORANGE ('Script AutoHotkey EN COURS : ' + (Split-Path $scr -Leaf)) 'ne clique pas lui-même, mais peut remapper des touches : demande au joueur de le fermer et de le montrer' $scr }
            } else {
                Add-Res Macros ORANGE 'AutoHotkey EN COURS' ('script : ' + $(if ($scr) { $scr } else { 'inconnu' }) + ' · PID ' + $pr.ProcessId) $exe
            }
            continue
        }
        if ($pr.Name -match $SS_RegexMacroClic -or $exe -match $SS_RegexMacroClic) {
            $alerte++; Add-Res Macros ROUGE ('Autoclicker EN COURS : ' + $pr.Name) ('PID {0} · {1}' -f $pr.ProcessId, $exe) $exe; continue
        }
        if ($pr.Name -match $SS_RegexMacroProg) {
            $alerte++; Add-Res Macros ORANGE ('Logiciel de macro EN COURS : ' + $pr.Name) ('PID {0} · {1}' -f $pr.ProcessId, $exe) $exe; continue
        }
        if ($pr.Name -match $SS_RegexSouris) {
            Add-Res Macros INFO ('Logiciel de souris ouvert : ' + $pr.Name) 'Peut contenir des macros : fais-le ouvrir et montrer l''onglet Macros / Assignations.' $exe; continue
        }
        # programme AutoHotkey compile en .exe (macro cachee sous un autre nom)
        if ($exe -and $exe -notmatch '(?i)^[A-Z]:\\(Windows|Program Files|Program Files \(x86\))\\' -and ($exe -like "$env:USERPROFILE*" -or (Test-SurUsb $exe) -or $exe -match '(?i)\\(temp|tmp)\\')) {
            if (Test-ExeAutoHotkey $exe) {
                $alerte++; Add-Res Macros ROUGE ('Macro AutoHotkey compilée EN COURS : ' + $pr.Name) ('script AutoHotkey caché dans un .exe · PID {0} · {1}' -f $pr.ProcessId, $exe) $exe
            }
        }
    }
    Invoke-Pompe

    # 2. Scripts de macro sur le disque (.ahk, macros TinyTask / Pulover / Jitbit, Lua Logitech)
    Set-Etape 74 'Macros : scripts sur le disque...'
    $racines = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), (Join-Path $env:USERPROFILE 'Downloads'), $env:APPDATA) + $extUsb
    $fich = Get-FichiersProfonds -Racines $racines -RegexNom '(?i)\.(ahk|ah2|ahk2|amc|amc2|mcr|pmc|rec|lua|au3)$' -Prof 4 -Max 40000
    $nbScripts = 0
    foreach ($f in $fich) {
        if ($vus.ContainsKey($f.ToLower())) { continue }
        $ext = [IO.Path]::GetExtension($f).ToLower()
        try { $fi = Get-Item -LiteralPath $f -Force } catch { continue }
        $recent = $fi.LastWriteTime -ge (Get-Date).AddDays(-30)
        $quand = ' · modifié le ' + (Format-Date $fi.LastWriteTime)
        if ($ext -in '.lua', '.rec') {
            $t = Read-TexteBrut $f 2097152
            if ($ext -eq '.lua' -and $t -notmatch 'PressMouseButton|PressAndReleaseMouseButton|MoveMouseRelative') { continue }
            if ($ext -eq '.rec' -and $f -notmatch '(?i)tinytask|macro|click') { continue }
        } else { $t = Read-TexteBrut $f 4194304 }
        $nbScripts++
        $an = Get-AnalyseMacro $t
        $sur = ''; if (Test-SurUsb $f) { $sur = ' (sur une clé USB)' }
        if ($an -and $an.Niveau -eq 'ROUGE') {
            $alerte++; $niv = $(if ($recent -or $sur) { 'ROUGE' } else { 'ORANGE' })
            Add-Res Macros $niv ('Script autoclicker' + $sur + ' : ' + $fi.Name) ($an.Raison + $quand) $f
        } elseif ($an) {
            $alerte++; Add-Res Macros ORANGE ('Script de macro' + $sur + ' : ' + $fi.Name) ($an.Raison + $quand) $f
        } elseif ($ext -in '.amc', '.amc2', '.mcr', '.pmc', '.rec') {
            $niv = $(if ($recent) { 'ORANGE' } else { 'INFO' })
            if ($niv -eq 'ORANGE') { $alerte++ }
            Add-Res Macros $niv ('Fichier de macro enregistrée' + $sur + ' : ' + $fi.Name) ('macro de souris/clavier enregistrée (Bloody, Jitbit, Pulover, TinyTask...)' + $quand) $f
        } else {
            Add-Res Macros INFO ('Script AutoHotkey : ' + $fi.Name) ('ne contient pas de clic automatique' + $quand) $f
        }
        if ($nbScripts -ge 60) { break }
    }
    # .exe recents qui sont des macros AutoHotkey compilees
    $exes = Get-FichiersProfonds -Racines @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads'), $env:TEMP) -RegexNom '(?i)\.exe$' -Prof 2 -Max 8000
    foreach ($f in $exes) {
        try { $fi = Get-Item -LiteralPath $f -Force } catch { continue }
        if ($fi.Length -gt 12MB -or $fi.LastWriteTime -lt (Get-Date).AddDays(-30)) { continue }
        if (Test-ExeAutoHotkey $f) { $alerte++; Add-Res Macros ORANGE ('Macro AutoHotkey compilée : ' + $fi.Name) ('script AutoHotkey caché dans un .exe · modifié le ' + (Format-Date $fi.LastWriteTime)) $f }
    }

    # 3. Macros enregistrees dans les logiciels de souris
    Set-Etape 75 'Macros : logiciels de souris...'
    $vendeurs = @(
        @{ Nom = 'Logitech G HUB / LGS'; Dossiers = @("$env:LOCALAPPDATA\LGHUB", "$env:ProgramData\LGHUB", "$env:LOCALAPPDATA\Logitech\Logitech Gaming Software", "$env:APPDATA\Logitech") }
        @{ Nom = 'Razer Synapse'; Dossiers = @("$env:LOCALAPPDATA\Razer", "$env:ProgramData\Razer", "$env:APPDATA\Razer") }
        @{ Nom = 'SteelSeries GG / Engine'; Dossiers = @("$env:ProgramData\SteelSeries", "$env:APPDATA\steelseries-gg-client") }
        @{ Nom = 'Corsair iCUE'; Dossiers = @("$env:APPDATA\Corsair", "$env:LOCALAPPDATA\Corsair", "$env:ProgramData\Corsair") }
        @{ Nom = 'Bloody / A4Tech'; Dossiers = @("${env:ProgramFiles(x86)}\Bloody7", "$env:ProgramFiles\Bloody7", "${env:ProgramFiles(x86)}\Bloody8", "$env:ProgramFiles\Bloody8") }
        @{ Nom = 'Glorious Core'; Dossiers = @("$env:LOCALAPPDATA\Glorious Core", "$env:APPDATA\Glorious Core", "$env:ProgramData\Glorious Core", "$env:APPDATA\GloriousCore") }
        @{ Nom = 'ROCCAT Swarm'; Dossiers = @("$env:APPDATA\ROCCAT", "$env:ProgramData\ROCCAT") }
        @{ Nom = 'HyperX NGenuity'; Dossiers = @("$env:ProgramData\HyperX", "$env:LOCALAPPDATA\HyperX") }
        @{ Nom = 'X-Mouse Button Control'; Dossiers = @("$env:APPDATA\Highresolution Enterprises") }
    )
    foreach ($v in $vendeurs) {
        $dossiers = @($v.Dossiers | Where-Object { $_ -and [IO.Directory]::Exists($_) })
        if ($dossiers.Count -eq 0) { continue }
        $fv = Get-FichiersProfonds -Racines $dossiers -RegexNom '(?i)(\.(xml|json|db|sqlite|lua|amc2?|cueprofile|txt|dat|ini|cfg|mcr|profile|settings)$|macro)' -Prof 7 -Max 6000
        $nbMacro = 0; $noms = @{}; $scr = $null; $simule = $false; $recents = 0
        foreach ($f in $fv) {
            # fichiers livres avec le logiciel (traductions, presets, liste de jeux) : pas des macros du joueur
            if ($f -match '(?i)\\(depots|strings|locales?|i18n|images?|icons?|resources|assets|presets?|applications?|firmware|drivers?|updates?)\\') { continue }
            if ($f -match '(?i)macro') {
                $nbMacro++
                try { if ((Get-Item -LiteralPath $f -Force).LastWriteTime -ge (Get-Date).AddDays(-30)) { $recents++ } } catch { }
            }
            if ($f -match '(?i)\.amc2?$') { continue }
            $t = Read-TexteBrut $f
            if (-not $t) { continue }
            foreach ($m in [regex]::Matches($t, $SS_RegexNomMacro)) { if ($noms.Count -lt 8) { $noms[$m.Value.Trim().ToLower()] = $true } }
            if ($t -match 'PressMouseButton|PressAndReleaseMouseButton|MoveMouseRelative') {
                foreach ($m in [regex]::Matches($t, 'PressMouseButton|PressAndReleaseMouseButton|MoveMouseRelative')) {
                    $deb = [Math]::Max(0, $m.Index - 1500)
                    $an = Get-AnalyseMacro ($t.Substring($deb, [Math]::Min(3000, $t.Length - $deb)))
                    if ($an -and (-not $scr -or $an.Niveau -eq 'ROUGE')) { $scr = @{ An = $an; F = $f } }
                    if ($scr -and $scr.An.Niveau -eq 'ROUGE') { break }
                }
            }
            if ($v.Nom -like 'X-Mouse*' -and $t -match '(?i)\{(LMB|RMB|MB4|MB5)\}') { $simule = $true }
            Invoke-Pompe
        }
        if ($scr) {
            $alerte++
            Add-Res Macros $scr.An.Niveau ('Script dans ' + $v.Nom) ($scr.An.Raison + ' · script Lua du logiciel de souris') $scr.F
        }
        if ($noms.Count -gt 0) {
            $alerte++
            Add-Res Macros ORANGE ('Macro au nom suspect dans ' + $v.Nom) ('noms trouvés : ' + (($noms.Keys | Sort-Object) -join ', ') + ' · fais ouvrir le logiciel et montrer cette macro') $dossiers[0]
        }
        if ($simule) {
            $alerte++
            Add-Res Macros ORANGE 'X-Mouse Button Control simule des clics' 'un bouton de la souris est réglé pour envoyer des clics ({LMB}/{RMB}) : peut servir d''autoclicker' $dossiers[0]
        }
        if (-not $scr -and $noms.Count -eq 0 -and -not $simule) {
            if ($nbMacro -gt 0) {
                $niv = $(if ($recents -gt 0 -and $v.Nom -like 'Bloody*') { 'ORANGE' } else { 'INFO' })
                $det = "$nbMacro fichier(s) de macros"
                if ($recents -gt 0) { $det += " dont $recents modifié(s) ces 30 derniers jours" }
                Add-Res Macros $niv ($v.Nom + ' : macros enregistrées') ($det + ' · fais ouvrir le logiciel et montrer l''onglet Macros') $dossiers[0]
            } else {
                Add-Res Macros INFO ($v.Nom + ' installé') 'Aucune macro trouvée dans ses fichiers (les macros dans la mémoire de la souris restent invisibles).' $dossiers[0]
            }
        }
    }

    # 4. Pilotes qui interceptent la souris / le clavier (Interception = autoclickers indétectables)
    Set-Etape 76 'Macros : pilotes souris / clavier...'
    $interception = $false
    foreach ($svc in 'mouse', 'keyboard') {
        $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -ErrorAction SilentlyContinue
        if ($p -and "$($p.ImagePath)" -match "(?i)$svc\.sys") { $interception = $true }
    }
    $filtres = @()
    foreach ($cl in @(@('{4D36E96F-E325-11CE-BFC1-08002BE10318}', 'souris', 'mouclass'), @('{4D36E96B-E325-11CE-BFC1-08002BE10318}', 'clavier', 'kbdclass'))) {
        $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$($cl[0])" -ErrorAction SilentlyContinue
        foreach ($fl in @($p.UpperFilters)) {
            if (-not $fl -or $fl -eq $cl[2]) { continue }
            if ($fl -in 'mouse', 'keyboard') { $interception = $true; continue }
            $filtres += "$fl ($($cl[1]))"
        }
    }
    if ($interception) {
        $alerte++
        Add-Res Macros ORANGE 'Pilote Interception installé' 'Pilote qui intercepte la souris et le clavier : utilisé par les autoclickers et macros « indétectables ». Demande au joueur à quoi il sert.'
    }
    if ($filtres.Count -gt 0) { Add-Res Macros INFO 'Filtres de pilote souris / clavier' (($filtres -join ', ') + ' · souvent un logiciel de marque, à vérifier si inconnu') }

    # 5. Logiciels de macro installes / lances recemment (sans admin)
    Set-Etape 77 'Macros : historique...'
    $inst = @{}
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($a in @(Get-ItemProperty $k -ErrorAction SilentlyContinue)) {
            $n = "$($a.DisplayName)"
            if (-not $n -or $inst.ContainsKey($n)) { continue }
            if ($n -match '(?i)(autohotkey|tinytask|pulover|macro|auto.?clicker|jitbit|murgee|ghost.?mouse|keyran|interception)') {
                $inst[$n] = $true; $alerte++
                $di = "$($a.InstallDate)"
                if ($di -match '^(\d{4})(\d\d)(\d\d)$') { $di = "$($Matches[3])/$($Matches[2])/$($Matches[1])" } elseif (-not $di) { $di = '?' }
                Add-Res Macros ORANGE ('Logiciel de macro installé : ' + $n) ('installé le ' + $di + ' · ' + $a.InstallLocation) "$($a.InstallLocation)"
            } elseif ($n -match $SS_RegexLogicielSouris) {
                $inst[$n] = $true
                Add-Res Macros INFO ('Logiciel de souris installé : ' + $n) 'Peut faire des macros : fais-le ouvrir pendant le screenshare.' "$($a.InstallLocation)"
            }
        }
    }
    $rot13 = { param([string]$s) -join ($s.ToCharArray() | ForEach-Object { $c = [int]$_; if ($c -ge 65 -and $c -le 90) { [char](65 + ($c - 65 + 13) % 26) } elseif ($c -ge 97 -and $c -le 122) { [char](97 + ($c - 97 + 13) % 26) } else { $_ } }) }
    foreach ($cle in @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist' -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty (Join-Path $cle.PSPath 'Count') -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        foreach ($x in $p.PSObject.Properties) {
            if ($x.Value -isnot [byte[]] -or $x.Value.Length -lt 68) { continue }
            $chemin = & $rot13 $x.Name
            if ($chemin -notmatch $SS_RegexMacroProg -or $chemin -match '(?i)uninst') { continue }
            $quand = $null
            try { $ft = [BitConverter]::ToInt64($x.Value, 60); if ($ft -gt 0) { $quand = [DateTime]::FromFileTime($ft) } } catch { }
            if (-not $quand -or $quand -lt (Get-Date).AddDays(-30)) { continue }
            $niv = 'ORANGE'
            if ($quand -ge $script:SS_Depuis -and $chemin -match $SS_RegexMacroClic) { $niv = 'ROUGE' }
            $alerte++
            Add-Res Macros $niv ('Lancé récemment : ' + (Split-Path $chemin -Leaf)) ('dernier lancement : {0} (il y a {1}) · {2} fois · {3}' -f (Format-Date $quand), (Format-Duree ((Get-Date) - $quand)), [BitConverter]::ToInt32($x.Value, 4), $chemin) $chemin
        }
    }
    if ($script:SS_Admin) {
        foreach ($f in @(Get-ChildItem -Path "$env:windir\Prefetch" -Filter *.pf -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-30) -and $_.Name -match '(?i)(autohotkey|tinytask|pulover|macro|clicker|murgee|ghostmouse|keyran)' })) {
            $alerte++; Add-Res Macros ORANGE ('Prefetch : ' + $f.Name) ('lancé le ' + (Format-Date $f.LastWriteTime)) $f.FullName
        }
    }

    if ($alerte -eq 0) { Add-Res Macros OK 'Macros / autoclick' 'Aucun autoclicker, script de macro ni macro suspecte trouvé.' }
    Add-Res Macros INFO 'Macros dans la mémoire de la souris' 'Les macros enregistrées DANS la souris (mode sans logiciel) ne sont pas lisibles depuis le PC : fais montrer le logiciel de la souris.'
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
    if ($devs.Count -eq 0) { Add-Res Usb OK 'Historique des clés de stockage' 'Aucune clé USB de stockage n''a été branchée sur ce PC (selon Windows).'; return }
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
            $min = [int]((Get-Date) - $h.Retrait).TotalMinutes
            if ($min -le $SS_MinutesAvantScan) { Add-Res Usb ROUGE ('Clé USB retirée {0} min AVANT le scan : {1}' -f $min, $h.Nom) ('Demande au joueur de la rebrancher · ' + $det) }
            else { Add-Res Usb ORANGE ('Clé retirée récemment : ' + $h.Nom) $det }
        } else {
            Add-Res Usb INFO ('Historique : ' + $h.Nom) $det
        }
    }
}

# Marques connues (VID USB)
$SS_Marques = @{
    '046D' = 'Logitech'; '1532' = 'Razer'; '1038' = 'SteelSeries'; '1B1C' = 'Corsair'; '0951' = 'HyperX / Kingston'
    '03F0' = 'HP / HyperX'; '3151' = 'MonsGeek / Akko'; '258A' = 'SinoWealth (générique)'; '09DA' = 'A4Tech / Bloody'
    '1E7D' = 'Roccat'; '054C' = 'Sony'; '05AC' = 'Apple'; '045E' = 'Microsoft'; '0E8D' = 'MediaTek'; '1462' = 'MSI'
    '05E3' = 'Genesys (hub)'; '0B05' = 'ASUS'; '2516' = 'Cooler Master'; '04D9' = 'Holtek (générique)'; '0C45' = 'Microdia'
    '093A' = 'PixArt'; '0781' = 'SanDisk'; '090C' = 'Silicon Motion'; '13FE' = 'Phison'; '058F' = 'Alcor'; '8564' = 'Transcend'
    '18D1' = 'Google / Android'; '04E8' = 'Samsung'; '2717' = 'Xiaomi'; '0A12' = 'Cambridge Silicon (Bluetooth)'
    '8087' = 'Intel'; '0BDA' = 'Realtek'; '2109' = 'VIA (hub)'; '1A40' = 'Terminus (hub)'; '25A7' = 'Areson (générique)'
    '248A' = 'Maxxter (générique)'; '1EA7' = 'SHARKOON'; '3434' = 'Keychron'; '342D' = 'Glorious'; '373B' = 'Attack Shark'
}
# Cartes programmables : peuvent se faire passer pour une souris ou un clavier (autoclicker materiel)
$SS_Microcontroleurs = @{
    '2341' = 'Arduino'; '2A03' = 'Arduino'; '1B4F' = 'SparkFun'; '16C0' = 'Teensy / V-USB'; '239A' = 'Adafruit'
    '2E8A' = 'Raspberry Pi Pico'; '1A86' = 'CH340 (clone Arduino)'; '10C4' = 'Silicon Labs CP210x'; '0403' = 'FTDI'
    '303A' = 'Espressif ESP32'; '0483' = 'STMicro'; '1209' = 'pid.codes (open hardware)'; '2886' = 'Seeed'; '1FC9' = 'NXP'
}

function Invoke-ScanPeripheriques {
    Set-Etape 84 'Appareils USB (souris, claviers, récepteurs...)...'
    $tousPnp = @(Get-PnpDevice)
    $classes = @{}
    foreach ($d in $tousPnp) {
        $m = [regex]::Match("$($d.InstanceId)", 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})')
        if (-not $m.Success) { continue }
        $k = ($m.Groups[1].Value + ':' + $m.Groups[2].Value).ToUpper()
        if (-not $classes.ContainsKey($k)) { $classes[$k] = New-Object System.Collections.Generic.List[string] }
        if ($d.Class -and -not $classes[$k].Contains($d.Class)) { $classes[$k].Add($d.Class) }
    }
    $racines = @($tousPnp | Where-Object { $_.InstanceId -match '^USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}\\' -and $_.InstanceId -notmatch '^USB\\VID_0000' })
    $liste = @()
    foreach ($d in $racines) {
        Invoke-Pompe
        if ($d.Service -match '^(USBSTOR|UASPStor)$') { continue }   # deja dans la partie cles de stockage
        $m = [regex]::Match($d.InstanceId, 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})')
        $vid = $m.Groups[1].Value.ToUpper(); $idProd = $m.Groups[2].Value.ToUpper()
        $pr = @(Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc', 'DEVPKEY_Device_LastArrivalDate', 'DEVPKEY_Device_LastRemovalDate', 'DEVPKEY_Device_FirstInstallDate')
        $h = @{}
        foreach ($x in $pr) { $h[$x.KeyName] = $x.Data }
        $nom = "$($h['DEVPKEY_Device_BusReportedDeviceDesc'])".Trim()
        if (-not $nom) { $nom = $d.FriendlyName }
        if ($nom -match '(?i)\bhub\b|concentrateur' -or $d.FriendlyName -match '(?i)\bhub\b|concentrateur') { continue }
        $cl = @()
        if ($classes.ContainsKey("$vid`:$idProd")) { $cl = @($classes["$vid`:$idProd"]) }
        $souris = $cl -contains 'Mouse'; $clavier = $cl -contains 'Keyboard'
        if ($souris -and $clavier) {
            if ($nom -match '(?i)receiver|récepteur|dongle|wireless|unifying|lightspeed|2\.4') { $type = 'Récepteur sans fil (souris/clavier)' }
            elseif ($nom -match '(?i)keyboard|clavier|kbd') { $type = 'Clavier' }
            elseif ($nom -match '(?i)mouse|souris') { $type = 'Souris' }
            else { $type = 'Souris / clavier' }
        } elseif ($souris) { $type = 'Souris' }
        elseif ($clavier) { $type = 'Clavier' }
        elseif ($cl -contains 'XnaComposite' -or $nom -match '(?i)controller|manette|gamepad|dualsense|dualshock|xbox') { $type = 'Manette' }
        elseif ($cl -contains 'MEDIA' -or $cl -contains 'AudioEndpoint' -or $nom -match '(?i)micro|headset|casque|audio') { $type = 'Audio' }
        elseif ($cl -contains 'WPD' -or $cl -contains 'Image' -or $nom -match '(?i)iphone|ipad|android|phone') { $type = 'Téléphone / appareil photo' }
        elseif ($cl -contains 'Bluetooth') { $type = 'Adaptateur Bluetooth' }
        elseif ($cl -contains 'Camera') { $type = 'Webcam' }
        elseif ($cl -contains 'Ports') { $type = 'Port série' }
        elseif ($cl -contains 'HIDClass') { $type = 'Périphérique HID' }
        else { $type = 'Autre' }
        $marque = $SS_Marques[$vid]
        $micro = $SS_Microcontroleurs[$vid]
        if ($micro) { $marque = $micro }
        $liste += [pscustomobject]@{
            Nom = $nom; Type = $type; Vid = $vid; Pid = $idProd; Marque = $marque; Micro = $micro
            Present = ($d.Status -eq 'OK'); Hid = ($souris -or $clavier -or ($cl -contains 'HIDClass'))
            Arrivee = $h['DEVPKEY_Device_LastArrivalDate']; Retrait = $h['DEVPKEY_Device_LastRemovalDate']; Premiere = $h['DEVPKEY_Device_FirstInstallDate']
        }
    }
    $presents = @($liste | Where-Object { $_.Present } | Sort-Object Type, Nom)
    $anciens = @($liste | Where-Object { -not $_.Present } | Sort-Object { if ($_.Arrivee) { $_.Arrivee } else { [DateTime]::MinValue } } -Descending)
    $script:SS_NbUsbPresents = $presents.Count
    $script:SS_NbHistUsb = $anciens.Count
    if ($liste.Count -eq 0) { Add-Res Usb INFO 'Appareils USB' 'Aucun appareil USB trouvé (ou liste illisible).'; Invoke-ScanTracesUsb; Invoke-ScanActiviteUsb; return }

    foreach ($a in ($presents + $anciens | Select-Object -First 60)) {
        $titre = '{0} : {1}' -f $a.Type, $a.Nom
        if ($a.Marque) { $titre += " ($($a.Marque))" }
        if ($a.Present) { $etat = 'branché maintenant' } else { $etat = 'débranché' }
        $det = '{0} · VID:PID {1}:{2} · 1re fois : {3} · dernier branchement : {4} · dernier retrait : {5}' -f $etat, $a.Vid, $a.Pid, (Format-Date $a.Premiere), (Format-Date $a.Arrivee), (Format-Date $a.Retrait)
        $niv = 'INFO'
        if ($a.Micro) {
            if ($a.Hid) { $niv = 'ROUGE'; $det = 'Carte programmable qui se fait passer pour une souris/un clavier : autoclicker matériel possible · ' + $det }
            else { $niv = 'ORANGE'; $det = 'Carte programmable (Arduino ou similaire) : à faire montrer par le joueur · ' + $det }
        } elseif ($a.Vid -eq '09DA' -and $a.Type -match 'Souris') {
            $niv = 'ORANGE'; $det = 'Souris Bloody : macros intégrées possibles (mode Ultra Core / logiciel Bloody) · ' + $det
        } elseif ($a.Present -and $a.Type -match 'Souris|Récepteur' -and $a.Vid -match '^(046D|1532|1038|1B1C|1E7D|2516|3434|342D)$') {
            $det = 'Souris de marque : macros possibles via son logiciel, demande au joueur de l''ouvrir · ' + $det
        }
        if (-not $a.Present -and $a.Retrait -and $a.Retrait -ge $script:SS_Depuis -and $a.Type -match 'Souris|Clavier|Récepteur|HID|Autre|Série') {
            $min = [int]((Get-Date) - $a.Retrait).TotalMinutes
            if ($min -le $SS_MinutesAvantScan) {
                $niv = 'ROUGE'
                $titre = ('Débranché {0} min AVANT le scan · ' -f $min) + $titre
                $det = 'Appareil retiré juste avant le screenshare : demande au joueur de le rebrancher et de le montrer · ' + $det
            } else {
                if ($niv -ne 'ROUGE') { $niv = 'ORANGE' }
                $titre = ('Débranché il y a {0} · ' -f (Format-Duree ((Get-Date) - $a.Retrait))) + $titre
            }
            if ($script:SS_LancementJeu -and $a.Retrait -gt $script:SS_LancementJeu) { $det += ' · retiré PENDANT que Minecraft tournait' }
        }
        if (-not $a.Present -and $niv -eq 'INFO') { $titre = 'Historique · ' + $titre }
        Add-Res Usb $niv $titre $det
    }
    Invoke-ScanTracesUsb
    Invoke-ScanActiviteUsb
}

# Ce qui a ete lance / ouvert depuis une cle USB (ou un lecteur qui n'est plus branche)
function Invoke-ScanActiviteUsb {
    Set-Etape 87 'Ce qui a été lancé depuis une clé USB...'
    $fixes = @{}
    foreach ($ld in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) { $fixes[$ld.DeviceID.ToUpper()] = $true }
    foreach ($u in $script:SS_Usb) { $fixes.Remove($u.Lettre) }   # disque USB vu comme fixe : il reste externe
    $estExterne = { param([string]$c) $c -match '^([A-Za-z]:)\\' -and -not $fixes.ContainsKey($Matches[1].ToUpper()) }
    $trouve = 0

    # 1. Programmes qui tournent en ce moment depuis une cle
    foreach ($pr in @(Get-CimInstance Win32_Process)) {
        if ($pr.ExecutablePath -and (& $estExterne $pr.ExecutablePath)) {
            $trouve++
            Add-Res Usb ROUGE ('Programme lancé depuis une clé USB en ce moment : ' + $pr.Name) ('PID {0} · {1}' -f $pr.ProcessId, $pr.ExecutablePath) $pr.ExecutablePath
        }
    }

    # 2. UserAssist : programmes lances par le joueur (nom en ROT13, date du dernier lancement)
    $rot13 = { param([string]$s) -join ($s.ToCharArray() | ForEach-Object { $c = [int]$_; if ($c -ge 65 -and $c -le 90) { [char](65 + ($c - 65 + 13) % 26) } elseif ($c -ge 97 -and $c -le 122) { [char](97 + ($c - 97 + 13) % 26) } else { $_ } }) }
    $ua = @()
    foreach ($cle in @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist')) {
        $p = Get-ItemProperty (Join-Path $cle.PSPath 'Count')
        if (-not $p) { continue }
        foreach ($x in $p.PSObject.Properties) {
            if ($x.Value -isnot [byte[]] -or $x.Value.Length -lt 68) { continue }
            $chemin = & $rot13 $x.Name
            if (-not (& $estExterne $chemin)) { continue }
            $quand = $null
            try { $ft = [BitConverter]::ToInt64($x.Value, 60); if ($ft -gt 0) { $quand = [DateTime]::FromFileTime($ft) } } catch { }
            $ua += [pscustomobject]@{ Chemin = $chemin; Quand = $quand; Nb = [BitConverter]::ToInt32($x.Value, 4) }
        }
    }
    foreach ($e in ($ua | Sort-Object { if ($_.Quand) { $_.Quand } else { [DateTime]::MinValue } } -Descending | Select-Object -First 25)) {
        $trouve++
        $niv = 'INFO'
        if ($e.Quand -and $e.Quand -ge $script:SS_Depuis) { $niv = 'ROUGE' }
        elseif ($e.Quand -and $e.Quand -ge (Get-Date).AddDays(-30)) { $niv = 'ORANGE' }
        $min = ''
        if ($e.Quand) { $min = ' (il y a ' + (Format-Duree ((Get-Date) - $e.Quand)) + ')' }
        Add-Res Usb $niv ('Programme lancé depuis une clé USB : ' + (Split-Path $e.Chemin -Leaf)) ('dernier lancement : {0}{1} · lancé {2} fois · {3}' -f (Format-Date $e.Quand), $min, $e.Nb, $e.Chemin) $e.Chemin
    }

    # 3. Fichiers recents de l'explorateur pointant vers une cle
    try {
        $sh = New-Object -ComObject WScript.Shell
        foreach ($l in @(Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -Filter *.lnk -Force | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-30) } | Sort-Object LastWriteTime -Descending)) {
            $cible = $sh.CreateShortcut($l.FullName).TargetPath
            if (-not $cible -or -not (& $estExterne $cible)) { continue }
            $trouve++
            $niv = 'ORANGE'
            if ($cible -match '(?i)\.(exe|jar|bat|cmd|ps1|vbs|dll|ahk)$' -or $cible -match $SS_RegexNom -or $cible -match $SS_RegexProgramme) { $niv = 'ROUGE' }
            elseif ($l.LastWriteTime -lt $script:SS_Depuis) { $niv = 'INFO' }
            Add-Res Usb $niv ('Ouvert depuis une clé USB : ' + (Split-Path $cible -Leaf)) ('le {0} · {1}' -f (Format-Date $l.LastWriteTime), $cible) $cible
        }
    } catch { }

    # 4. BAM (admin) : programmes executes depuis un volume qui n'est plus branche
    if ($script:SS_Admin) {
        $volumes = @{}
        foreach ($lt in [char[]](67..90)) {
            try { $d = [SnowNatif]::Peripherique("$($lt):") } catch { Initialize-Natif; $d = [SnowNatif]::Peripherique("$($lt):") }
            if ($d) { $volumes[$d.ToLower()] = "$($lt):" }
        }
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\State\UserSettings\$sid"
        if (-not (Test-Path $cle)) { $cle = "HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings\$sid" }
        $props = Get-ItemProperty -Path $cle
        if ($props) {
            foreach ($pp in $props.PSObject.Properties) {
                if ($pp.Value -isnot [byte[]] -or $pp.Value.Length -lt 8) { continue }
                $m = [regex]::Match($pp.Name, '^(\\Device\\HarddiskVolume\d+)(\\.*)$')
                if (-not $m.Success) { continue }
                $vol = $m.Groups[1].Value.ToLower()
                $lettre = $volumes[$vol]
                if ($lettre -and $fixes.ContainsKey($lettre)) { continue }
                $quand = [DateTime]::FromFileTime([BitConverter]::ToInt64($pp.Value, 0))
                if ($quand -lt $script:SS_Depuis) { continue }
                $trouve++
                $ou = 'un lecteur qui n''est plus branché'
                if ($lettre) { $ou = "le lecteur externe $lettre" }
                Add-Res Usb ROUGE ('Programme exécuté depuis ' + $ou + ' : ' + (Split-Path $m.Groups[2].Value -Leaf)) ('le {0} · {1}{2} (trace BAM)' -f (Format-Date $quand), $m.Groups[1].Value, $m.Groups[2].Value)
            }
        }
    }
    if ($trouve -eq 0) {
        $note = ''
        if (-not $script:SS_Admin) { $note = ' (BAM non vérifié : lance en administrateur pour la vérification complète)' }
        Add-Res Usb OK 'Activité depuis une clé USB' ('Aucun programme ni fichier lancé depuis une clé USB.' + $note)
    }
}

# Bilan : tout ce qu'une cle USB a charge / injecte dans Minecraft
function Invoke-BilanUsb {
    Set-Etape 97 'Ce que la clé USB a fait au jeu...'
    $fixes = @{}
    foreach ($ld in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) { $fixes[$ld.DeviceID.ToUpper()] = $true }
    foreach ($u in $script:SS_Usb) { $fixes.Remove($u.Lettre) }
    $estExt = {
        param([string]$txt)
        foreach ($m in [regex]::Matches("$txt", '(?<![A-Za-z])([A-Za-z]:)\\')) { if (-not $fixes.ContainsKey($m.Groups[1].Value.ToUpper())) { return $true } }
        return $false
    }
    $n = 0
    foreach ($r in @($script:SS_Resultats.ToArray())) {
        if (($r.Cat -ne 'Injection' -and $r.Cat -ne 'Minecraft') -or ($r.Niveau -ne 'ROUGE' -and $r.Niveau -ne 'ORANGE')) { continue }
        if (& $estExt ("$($r.Chemin) $($r.Detail)")) {
            $n++
            Add-Res Usb ROUGE ('La clé USB agit sur le jeu : ' + $r.Titre) $r.Detail $r.Chemin
        }
    }
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'")) {
        $par = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)"
        if ($par -and $par.ExecutablePath -and (& $estExt $par.ExecutablePath)) {
            $n++
            Add-Res Usb ROUGE ('Minecraft a été lancé par un programme de la clé USB : ' + $par.Name) $par.ExecutablePath $par.ExecutablePath
        }
    }
    if ($n -eq 0) { Add-Res Usb OK 'Ce que la clé USB a fait au jeu' 'Rien chargé ni injecté dans Minecraft depuis une clé USB.' }
}

# Traces dans les journaux Windows : branchements, appareils effaces, disques/cles USB
function Invoke-ScanTracesUsb {
    Set-Etape 86 'Journaux Windows (branchements USB)...'
    $evts = @()
    try { $evts = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Configuration'; Id = 400, 410, 420; StartTime = $script:SS_Depuis } -ErrorAction Stop) } catch { }
    $effaces = @{}; $branches = @{}
    foreach ($e in $evts) {
        $inst = "$($e.Properties[0].Value)"
        if ($inst -notmatch '^(USB\\VID_|USBSTOR\\|HID\\VID_|SCSI\\DISK)') { continue }
        $m = [regex]::Match($inst, 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})')
        $cle = $inst
        if ($m.Success) { $cle = ($m.Groups[1].Value + ':' + $m.Groups[2].Value).ToUpper() }
        if ($e.Id -eq 420) {
            if (-not $effaces.ContainsKey($cle) -or $e.TimeCreated -gt $effaces[$cle].Quand) { $effaces[$cle] = [pscustomobject]@{ Quand = $e.TimeCreated; Inst = $inst } }
        } elseif ($inst -match '^(USB\\VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}\\|USBSTOR\\)') {
            if (-not $branches.ContainsKey($cle) -or $e.TimeCreated -gt $branches[$cle].Quand) { $branches[$cle] = [pscustomobject]@{ Quand = $e.TimeCreated; Inst = $inst } }
        }
    }
    foreach ($k in $effaces.Keys) {
        $x = $effaces[$k]
        $marque = ''
        if ($k -match '^([0-9A-F]{4}):') { $marque = $SS_Marques[$Matches[1]]; if ($SS_Microcontroleurs[$Matches[1]]) { $marque = $SS_Microcontroleurs[$Matches[1]] } }
        if ($marque) { $marque = " ($marque)" }
        Add-Res Usb ROUGE ('Appareil USB effacé de l''historique Windows' + $marque) ('Supprimé le {0} : quelqu''un a nettoyé les traces de cet appareil (outil type USBDeview ?) · {1}' -f (Format-Date $x.Quand), $x.Inst)
    }
    # appareils connus de Windows (branches ou dans l'historique)
    $connus = @{}
    foreach ($d in @(Get-PnpDevice)) {
        $m = [regex]::Match("$($d.InstanceId)", 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})')
        if ($m.Success) { $connus[($m.Groups[1].Value + ':' + $m.Groups[2].Value).ToUpper()] = $true }
        $connus["$($d.InstanceId)".ToUpper()] = $true
    }
    $fantomes = 0
    foreach ($k in ($branches.Keys | Sort-Object { $branches[$_].Quand } -Descending)) {
        if ($connus.ContainsKey($k.ToUpper()) -or $effaces.ContainsKey($k)) { continue }
        $x = $branches[$k]
        $fantomes++
        $marque = ''
        if ($k -match '^([0-9A-F]{4}):') { $marque = $SS_Marques[$Matches[1]]; if ($SS_Microcontroleurs[$Matches[1]]) { $marque = $SS_Microcontroleurs[$Matches[1]] } }
        $nom = $marque
        if (-not $nom) { $nom = $k }
        Add-Res Usb ORANGE ('Appareil USB branché le {0} mais absent de l''historique : {1}' -f (Format-Date $x.Quand), $nom) ('Le journal Windows l''a vu, mais Windows ne le connaît plus (trace effacée ?) · ' + $x.Inst)
    }
    if ($effaces.Count -eq 0 -and $fantomes -eq 0) { Add-Res Usb OK 'Journaux Windows' ("Aucun appareil USB effacé ou caché depuis $SS_Heures h.") }
    # Disques et cles USB (journal Partition/Diagnostic, garde la trace meme si le registre est nettoye)
    $disques = @()
    try { $disques = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Partition/Diagnostic'; Id = 1006; StartTime = $script:SS_Depuis } -ErrorAction Stop) } catch { }
    $vus = @{}
    foreach ($e in $disques) {
        $pr = @($e.Properties)
        if ($pr.Count -lt 14 -or "$($pr[13].Value)" -ne '7') { continue }   # 7 = bus USB
        $taille = 0
        try { $taille = [double]$pr[12].Value } catch { }
        $textes = @($pr | ForEach-Object { $_.Value } | Where-Object { $_ -is [string] -and $_ -match '[A-Za-z]{2}' -and $_ -notmatch '^[0-9a-fA-F\-]{30,}$' })
        $nom = ($textes | Select-Object -First 3) -join ' '
        if (-not $nom) { $nom = 'disque USB' }
        $cle = "$nom|$taille"
        if ($vus.ContainsKey($cle)) { continue }
        $vus[$cle] = $true
        $min = [int]((Get-Date) - $e.TimeCreated).TotalMinutes
        $niv = 'ORANGE'
        $titre = 'Clé / disque USB branché ou retiré le ' + (Format-Date $e.TimeCreated)
        if ($min -le $SS_MinutesAvantScan) { $niv = 'ROUGE'; $titre = ('Clé / disque USB branché ou retiré {0} min AVANT le scan' -f $min) }
        $det = $nom
        if ($taille -gt 0) { $det += ' · ' + (Format-Taille $taille) }
        Add-Res Usb $niv $titre ($det + ' · trace du journal Windows (Partition/Diagnostic)')
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
    if ($script:ScanEnCours) {
        $titre = 'Scan en cours...'; $sous = 'Analyse du PC du joueur, ne ferme pas la fenêtre.'; $niv = 'ACCENT'; $glyphe = [string][char]0xE895
    } elseif ($r -gt 0) {
        $titre = 'SUSPECT'; $sous = "$r alerte(s) rouge et $o orange : triche probable, regarde le détail ci-dessous."; $niv = 'ROUGE'; $glyphe = [string][char]0xEA39
    } elseif ($o -gt 0) {
        $titre = 'À VÉRIFIER'; $sous = "$o point(s) orange à regarder avec le joueur."; $niv = 'ORANGE'; $glyphe = [string][char]0xE7BA
    } else {
        $titre = 'RIEN DE SUSPECT'; $sous = 'Aucune alerte. Un scan propre ne prouve pas à 100 % que le joueur est clean.'; $niv = 'OK'; $glyphe = [string][char]0xE73E
    }
    $script:VerdictTexte = 'VERDICT : ' + $titre + '  ·  ' + $sous
    if ($script:UI) {
        $p = $script:Pinceaux[$niv]
        $script:UI.Verdict.Text = $titre
        $script:UI.Verdict.Foreground = $p.C
        $script:UI.SousVerdict.Text = $sous
        $script:UI.Rond.Background = $p.C
        $script:UI.IconeVerdict.Text = $glyphe
        $script:UI.IconeVerdict.Foreground = $p.C
        $script:UI.Barre.Background = $p.C
    }
}

function Get-TexteRapport {
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("SnowFall SS v$SS_Version - rapport de screenshare")
    [void]$sb.AppendLine(('Date : {0:dd/MM/yyyy HH:mm:ss}  ·  PC : {1}  ·  session : {2}' -f (Get-Date), $env:COMPUTERNAME, $env:USERNAME))
    [void]$sb.AppendLine($script:VerdictTexte)
    foreach ($cle in $SS_Categories.Keys) {
        if ($cle -eq 'Resume') { continue }
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($x in $script:SS_Resultats) { if ($x.Cat -eq $cle) { $rows.Add($x) } }
        if ($rows.Count -eq 0) { continue }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('=== ' + $SS_Categories[$cle] + ' ===')
        foreach ($r in $rows) {
            [void]$sb.AppendLine(('[{0}] {1} : {2}' -f $r.Niveau, $r.Titre, $r.Detail))
            if ($r.Chemin -and -not "$($r.Detail)".Contains($r.Chemin)) { [void]$sb.AppendLine('        -> ' + $r.Chemin) }
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
    $script:SS_NbJars = 0
    $script:SS_NbHistUsb = 0
    $script:SS_NbUsbPresents = 0
    $script:SS_Usb = @()
    $script:SS_Volumes = $null
    $script:SS_Depuis = (Get-Date).AddHours(-$SS_Heures)
    if ($script:UI) {
        foreach ($b in $script:UI.Actions) { $b.IsEnabled = $false }
        $script:UI.InfoRapport.Text = ''
        Update-Verdict
        Update-Navigation
        Show-Categorie 'Resume'
    }
    try {
        $script:SS_Usb = @(Get-LecteursUsb)
        Invoke-ScanSysteme
        Invoke-ScanMinecraft
        Invoke-ScanMods
        Invoke-ScanLogJeu
        Invoke-ScanLogsJeu
        Invoke-ScanProgrammes
        Invoke-ScanMacros
        Invoke-ScanStreamProof
        Invoke-ScanUsb
        Invoke-ScanPeripheriques
        Invoke-ScanFichiers
        Invoke-ScanCorbeille
        Invoke-BilanUsb
    } catch {
        if ("$_" -eq 'SCAN_ANNULE') { $script:ScanEnCours = $false; return }
        Add-Res Systeme ORANGE 'Erreur pendant le scan' $_.Exception.Message
    }
    $script:ScanEnCours = $false
    Update-Verdict
    Save-Rapport
    if ($script:UI) {
        $script:UI.Barre.Width = $script:UI.BarreFond.ActualWidth
        $script:UI.Statut.Text = ('Scan terminé à {0:HH:mm:ss}' -f (Get-Date))
        if ($script:SS_Fichier) { $script:UI.InfoRapport.Text = 'Rapport enregistré : ' + $script:SS_Fichier }
        foreach ($b in $script:UI.Actions) { $b.IsEnabled = $true }
        Update-Navigation
        Show-Categorie 'Resume'
    }
}

# =====================================================================
#  Interface (WPF)
# =====================================================================
$SS_Icones = @{
    Resume = 0xE80F; Systeme = 0xE770; Minecraft = 0xE7FC; Injection = 0xEA18; Mods = 0xE74C
    Programmes = 0xE71D; Usb = 0xE88E; Fichiers = 0xE8A5; Corbeille = 0xE74D
}

$SS_NomsNiveaux = @{ ROUGE = 'ALERTE'; ORANGE = 'À VÉRIFIER'; OK = 'OK'; INFO = 'INFO' }

function Invoke-PompeUi {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $cb = [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; return $null }
    [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $cb, $frame)
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function New-Pinceau {
    param([string]$Hex)
    $b = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex)
    $b.Freeze()
    return $b
}

function Update-Navigation {
    if (-not $script:UI) { return }
    foreach ($cle in $SS_Categories.Keys) {
        $n = $script:UI.Nav[$cle]
        $r = Get-Compte $cle ROUGE
        $o = Get-Compte $cle ORANGE
        $n.R.Text = [string]$r; $n.R.Visibility = $(if ($r -gt 0) { 'Visible' } else { 'Collapsed' })
        $n.O.Text = [string]$o; $n.O.Visibility = $(if ($o -gt 0) { 'Visible' } else { 'Collapsed' })
        $n.Z.Visibility = $(if ($r -eq 0 -and $o -eq 0) { 'Visible' } else { 'Collapsed' })
    }
    $script:UI.StatRouge.Text = [string](Get-Compte Resume ROUGE)
    $script:UI.StatOrange.Text = [string](Get-Compte Resume ORANGE)
    $script:UI.StatMods.Text = [string]$script:SS_NbJars
    $script:UI.StatUsb.Text = [string]$script:SS_NbUsbPresents
    $script:UI.StatUsbSous.Text = ('{0} stockage · {1} anciens' -f @($script:SS_Usb).Count, $script:SS_NbHistUsb)
}

function Show-Categorie {
    param([string]$Cle)
    if (-not $script:UI) { return }
    $memeCat = ($script:CatActive -eq $Cle)
    $script:CatActive = $Cle
    $script:NbAffiche = $script:SS_Resultats.Count
    Update-FiltreLaunchers $Cle
    $filtre = $(if ($Cle -eq 'Mods') { "$($script:FiltreLauncher)" } else { '' })
    $rouges = New-Object System.Collections.Generic.List[object]
    $oranges = New-Object System.Collections.Generic.List[object]
    $autres = New-Object System.Collections.Generic.List[object]
    foreach ($x in $script:SS_Resultats) {
        if ($Cle -ne 'Resume' -and $x.Cat -ne $Cle) { continue }
        if ($filtre -and $x.Groupe -ne $filtre) { continue }
        if ($x.Niveau -eq 'ROUGE') { $rouges.Add($x) }
        elseif ($x.Niveau -eq 'ORANGE') { $oranges.Add($x) }
        elseif ($Cle -ne 'Resume') { $autres.Add($x) }
    }
    $rows = @($rouges.ToArray()) + @($oranges.ToArray()) + @($autres.ToArray())
    if ($Cle -eq 'Resume' -and $rows.Count -eq 0) {
        if ($script:ScanEnCours) {
            $rows = @([pscustomobject]@{ Cat = 'Resume'; Niveau = 'INFO'; Titre = 'Scan en cours...'; Detail = 'Les alertes apparaîtront ici dès qu''elles sont trouvées.'; Chemin = '' })
        } else {
            $rows = @([pscustomobject]@{ Cat = 'Resume'; Niveau = 'OK'; Titre = 'Aucune alerte'; Detail = 'Aucun élément rouge ou orange. Regarde quand même les autres catégories.'; Chemin = '' })
        }
    }
    $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($r in $rows) {
        $p = $script:Pinceaux[$r.Niveau]
        $catTexte = ''; $catVis = 'Collapsed'
        if ($Cle -eq 'Resume' -and $r.Cat -ne 'Resume') { $catTexte = $SS_Categories[$r.Cat]; $catVis = 'Visible' }
        $chemin = ''; $vis = 'Collapsed'
        if ($r.Chemin -and -not "$($r.Detail)".Contains($r.Chemin)) { $chemin = $r.Chemin; $vis = 'Visible' }
        $barre = $script:Pinceaux.VIDE
        if ($r.Niveau -eq 'ROUGE') { $barre = $p.C }
        $items.Add([pscustomobject]@{
            Titre = $r.Titre; Detail = "$($r.Detail)"; Chemin = $chemin; CheminVis = $vis
            CatTexte = $catTexte; CatVis = $catVis; Barre = $barre
            Couleur = $p.C; NiveauTexte = $SS_NomsNiveaux[$r.Niveau]; Source = $r
        })
    }
    $script:UI.Liste.ItemsSource = $items
    if ($Cle -eq 'Resume') { $script:UI.TitreListe.Text = 'POINTS À EXAMINER AVEC LE JOUEUR' } else { $script:UI.TitreListe.Text = $SS_Categories[$Cle].ToUpper() }
    $script:UI.CompteListe.Text = ('{0} entrée(s)' -f $rows.Count)
    if (-not $memeCat) { $script:UI.Defile.ScrollToTop() }
    $script:ChangeNav = $true
    try { $script:UI.Nav[$Cle].Bouton.IsChecked = $true } finally { $script:ChangeNav = $false }
}

# Touches qui ouvrent souvent un menu de cheat et ne font rien en vanilla
# (nom, code de balayage physique, touche étendue)
$SS_TouchesMenu = @(
    @('Shift droit', 0x36, $false), @('Inser', 0x52, $true), @('Suppr', 0x53, $true), @('Origine (Home)', 0x47, $true),
    @('Fin (End)', 0x4F, $true), @('Page haut', 0x49, $true), @('Page bas', 0x51, $true), @('Ctrl droit', 0x1D, $true),
    @('Alt Gr / Alt droit', 0x38, $true), @('² / ` (sous Échap)', 0x29, $false), @('F12', 0x58, $false), @('F9', 0x43, $false),
    @('Pavé num. 0', 0x52, $false), @('Pavé num. 5', 0x4C, $false), @('Pavé num. Entrée', 0x1C, $true), @('Ù / apostrophe', 0x28, $false),
    @('* / antislash', 0x2B, $false), @('M / point-virgule', 0x27, $false)
)

function Wait-Pompe {
    param([int]$Ms)
    $fin = (Get-Date).AddMilliseconds($Ms)
    while ((Get-Date) -lt $fin) { Invoke-PompeUi; Start-Sleep -Milliseconds 30 }
}

function Start-TestTouches {
    param([IntPtr]$Hwnd = [IntPtr]::Zero, [switch]$SansConfirmation, $Touches = $SS_TouchesMenu, [int]$Attente = 2200)
    if (-not ('SnowTouches' -as [type])) { Add-Type -TypeDefinition $SS_CodeTouches -ErrorAction Stop }
    $nomJeu = 'Minecraft'
    if ($Hwnd -eq [IntPtr]::Zero) {
        foreach ($j in @(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'")) {
            if ("$($j.CommandLine)" -and "$($j.CommandLine)" -notmatch $SS_RegexJeu) { continue }
            $gp = Get-Process -Id $j.ProcessId -ErrorAction SilentlyContinue
            if ($gp -and $gp.MainWindowHandle -ne [IntPtr]::Zero) { $Hwnd = $gp.MainWindowHandle; $nomJeu = "Minecraft (PID $($j.ProcessId))"; break }
        }
    }
    if ($Hwnd -eq [IntPtr]::Zero) {
        [void][System.Windows.MessageBox]::Show($script:UI.Fenetre, 'Minecraft n''est pas ouvert (ou sa fenêtre est introuvable). Demande au joueur de lancer le jeu, puis réessaie.', 'Tester les touches', 'OK', 'Warning')
        return
    }
    if (-not $SansConfirmation) {
        $msg = "Le jeu va passer au premier plan et l'outil va appuyer sur $($Touches.Count) touches, une toutes les 3 secondes environ (chaque touche 2 fois : ouvrir puis refermer).`n`n" +
               "Regarde le stream du joueur : si un menu de cheat s'ouvre, le nom de la touche est affiché en haut de l'écran.`n`n" +
               "Demande au joueur de ne pas toucher son clavier pendant le test (environ $([int]($Touches.Count * ($Attente + 900) / 1000)) s)."
        if ([System.Windows.MessageBox]::Show($script:UI.Fenetre, $msg, 'Tester les touches', 'OKCancel', 'Information') -ne 'OK') { return }
    }
    foreach ($b in $script:UI.Actions) { $b.IsEnabled = $false }
    # Petite étiquette en haut de l'écran du jeu (ne prend pas le focus)
    $etiq = New-Object System.Windows.Window
    $etiq.WindowStyle = 'None'; $etiq.AllowsTransparency = $true; $etiq.Topmost = $true; $etiq.ShowActivated = $false
    $etiq.ShowInTaskbar = $false; $etiq.SizeToContent = 'WidthAndHeight'; $etiq.Background = [System.Windows.Media.Brushes]::Transparent
    $bord = New-Object System.Windows.Controls.Border
    $bord.Background = (New-Pinceau '#E6111317'); $bord.BorderBrush = $script:Pinceaux.ACCENT.C; $bord.BorderThickness = 1; $bord.CornerRadius = 4; $bord.Padding = '14,8'
    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.Foreground = (New-Pinceau '#F1F3F6'); $txt.FontFamily = 'Segoe UI'; $txt.FontSize = 15; $txt.FontWeight = 'SemiBold'
    $bord.Child = $txt; $etiq.Content = $bord
    $r = [SnowTouches]::Rect($Hwnd)
    $etiq.Left = $r[0] + 24; $etiq.Top = $r[1] + 40
    $faites = @(); $arret = $null
    try {
        if (-not [SnowTouches]::Activer($Hwnd)) { $arret = 'impossible de mettre le jeu au premier plan' }
        $etiq.Show()
        Wait-Pompe 900
        $i = 0
        foreach ($t in $Touches) {
            if ($arret) { break }
            $i++
            $txt.Text = ('SnowFall SS · test de touche {0}/{1} : {2}' -f $i, $Touches.Count, $t[0])
            if (-not [SnowTouches]::AuPremierPlan($Hwnd)) {
                [void][SnowTouches]::Activer($Hwnd); Wait-Pompe 400
                if (-not [SnowTouches]::AuPremierPlan($Hwnd)) { $arret = 'le jeu n''est plus au premier plan (le joueur a changé de fenêtre)'; break }
            }
            foreach ($fois in 1, 2) {
                [void][SnowTouches]::Appui([uint16]$t[1], [bool]$t[2], $false); Wait-Pompe 70
                [void][SnowTouches]::Appui([uint16]$t[1], [bool]$t[2], $true)
                Wait-Pompe $(if ($fois -eq 1) { $Attente } else { 700 })
            }
            $faites += $t[0]
        }
    } finally {
        $etiq.Close()
        foreach ($b in $script:UI.Actions) { $b.IsEnabled = $true }
        try { $script:UI.Fenetre.Activate() | Out-Null } catch { }
    }
    $det = ('{0} à {1:HH:mm:ss} · touches : {2}' -f $nomJeu, (Get-Date), ($faites -join ', '))
    if ($arret) { Add-Res Minecraft ORANGE ('Test des touches arrêté : ' + $arret) $det }
    else { Add-Res Minecraft INFO ('Test des touches de menu : ' + $faites.Count + ' touche(s) appuyée(s)') ($det + ' · si un menu s''est ouvert sur le stream, note la touche') }
    Save-Rapport
    Update-Navigation
    Show-Categorie $script:CatActive
    $script:UI.Statut.Text = $(if ($arret) { 'Test des touches arrêté : ' + $arret } else { ('Test des touches terminé ({0} touches)' -f $faites.Count) })
}

function Update-FiltreLaunchers {
    # Boutons « Tous / Modrinth App / Launcher officiel... » au-dessus de la liste des mods
    param([string]$Cle)
    $panneau = $script:UI.FiltreLaunchers
    if (-not $panneau) { return }
    $panneau.Children.Clear()
    if ($Cle -ne 'Mods') { $panneau.Visibility = 'Collapsed'; return }
    $groupes = [ordered]@{}
    foreach ($x in $script:SS_Resultats) {
        if ($x.Cat -ne 'Mods' -or -not $x.Groupe) { continue }
        if (-not $groupes.Contains($x.Groupe)) { $groupes[$x.Groupe] = 0 }
        if ("$($x.Chemin)" -like '*.jar' -and $x.Titre -notlike '▸*' -and $x.Titre -notlike 'Jar modifié*' -and $x.Titre -notlike 'Mod interdit*') { $groupes[$x.Groupe]++ }
    }
    if ($script:FiltreLauncher -and -not $groupes.Contains($script:FiltreLauncher)) { $script:FiltreLauncher = '' }
    if ($groupes.Count -eq 0) { $panneau.Visibility = 'Collapsed'; return }
    $panneau.Visibility = 'Visible'
    $total = 0; foreach ($v in $groupes.Values) { $total += $v }
    $style = $script:UI.Fenetre.FindResource('Puce')
    $choix = @(, @('', 'Tous les launchers', $total))
    foreach ($g in $groupes.Keys) { $choix += , @($g, $g, $groupes[$g]) }
    foreach ($c in $choix) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $style
        $b.Tag = $c[0]
        $b.Content = ('{0}  {1}' -f $c[1], $c[2])
        if ("$($script:FiltreLauncher)" -eq $c[0]) {
            $b.Background = (New-Pinceau '#1A1D23'); $b.BorderBrush = $script:Pinceaux.ACCENT.C; $b.Foreground = (New-Pinceau '#F1F3F6')
        }
        $b.Add_Click({ param($s, $e) $script:FiltreLauncher = [string]$s.Tag; Show-Categorie 'Mods'; $script:UI.Defile.ScrollToTop() })
        [void]$panneau.Children.Add($b)
    }
}

function Open-Emplacement {
    param($Item)
    if (-not $Item -or -not $Item.Source) { return }
    $c = $Item.Source.Chemin
    if (-not $c -or -not (Test-Path -LiteralPath $c)) { return }
    if ((Get-Item -LiteralPath $c -Force).PSIsContainer) { Start-Process explorer.exe -ArgumentList ('"' + $c + '"') }
    else { Start-Process explorer.exe -ArgumentList ('/select,"' + $c + '"') }
}

function Get-ItemSous {
    param($Element)
    $e = $Element
    while ($e) {
        if ($e.DataContext -and $e.DataContext.PSObject.Properties['Source']) { return $e.DataContext }
        if ($e -is [System.Windows.Media.Visual] -or $e -is [System.Windows.Media.Media3D.Visual3D]) { $e = [System.Windows.Media.VisualTreeHelper]::GetParent($e) }
        elseif ($e.Parent) { $e = $e.Parent }
        else { return $null }
    }
    return $null
}

$SS_Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SnowFall SS" Width="1280" Height="820" MinWidth="1020" MinHeight="640"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
    <FontFamily x:Key="Icones">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
    <FontFamily x:Key="Mono">Cascadia Mono, Consolas</FontFamily>

    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border Background="#2C3038" CornerRadius="2" Margin="3,2"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#7B818C"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="GroupName" Value="Nav"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="2,0,0,0" Padding="18,7,20,7">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1A1D23"/>
                <Setter Property="Foreground" Value="#D7DAE0"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1A1D23"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#8AB4F8"/>
                <Setter Property="Foreground" Value="#F1F3F6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#D7DAE0"/>
      <Setter Property="Background" Value="#111317"/>
      <Setter Property="BorderBrush" Value="#2C3038"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="4" Padding="14,6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#7B818C"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.8"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BtnPrimaire" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#E8EAED"/>
      <Setter Property="BorderBrush" Value="#E8EAED"/>
      <Setter Property="Foreground" Value="#0C0D10"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style x:Key="Puce" TargetType="Button">
      <Setter Property="Foreground" Value="#7B818C"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="#2C3038"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,6,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4" Padding="10,4">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#7B818C"/>
                <Setter Property="Foreground" Value="#D7DAE0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="BtnFenetre" TargetType="Button">
      <Setter Property="Foreground" Value="#7B818C"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Width" Value="46"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent">
              <TextBlock Text="{TemplateBinding Content}" FontFamily="{StaticResource Icones}" FontSize="10"
                         Foreground="{TemplateBinding Foreground}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1A1D23"/>
                <Setter Property="Foreground" Value="#F1F3F6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Etiquette" TargetType="TextBlock">
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#565B65"/>
    </Style>
    <Style x:Key="ValeurMono" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource Mono}"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="#D7DAE0"/>
      <Setter Property="Margin" Value="0,2,0,0"/>
    </Style>
    <Style x:Key="Cellule" TargetType="Border">
      <Setter Property="BorderBrush" Value="#23262D"/>
      <Setter Property="BorderThickness" Value="0,0,1,0"/>
      <Setter Property="Padding" Value="16,12"/>
    </Style>
    <Style x:Key="Chiffre" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="{StaticResource Mono}"/>
      <Setter Property="FontSize" Value="24"/>
      <Setter Property="Foreground" Value="#F1F3F6"/>
      <Setter Property="Margin" Value="0,4,0,0"/>
    </Style>
    <Style x:Key="SousChiffre" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Foreground" Value="#565B65"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Racine" CornerRadius="6" Background="#0C0D10" BorderBrush="#2C3038" BorderThickness="1" Margin="14">
    <Border.Effect>
      <DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.55" Color="#000000"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <!-- En-tete : marque, infos machine, verdict, boutons fenetre -->
      <Border Background="#111317" BorderBrush="#23262D" BorderThickness="0,0,0,1" CornerRadius="6,6,0,0">
        <Grid x:Name="BarreTitre" Background="Transparent" Height="66">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="236"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Border BorderBrush="#23262D" BorderThickness="0,0,1,0" Padding="20,0">
            <StackPanel VerticalAlignment="Center">
              <TextBlock Text="SnowFall SS" FontSize="14" FontWeight="SemiBold" Foreground="#F1F3F6"/>
              <TextBlock x:Name="SousTitre" FontFamily="{StaticResource Mono}" FontSize="10" Foreground="#565B65" Margin="0,2,0,0"/>
            </StackPanel>
          </Border>
          <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="20,0">
            <StackPanel>
              <TextBlock Text="MACHINE / SESSION" Style="{StaticResource Etiquette}"/>
              <TextBlock x:Name="InfoPc" Style="{StaticResource ValeurMono}"/>
            </StackPanel>
            <StackPanel x:Name="BadgeAdmin" Margin="32,0,0,0">
              <TextBlock Text="DROITS" Style="{StaticResource Etiquette}"/>
              <TextBlock x:Name="TexteAdmin" Style="{StaticResource ValeurMono}"/>
              <TextBlock x:Name="IconeAdmin" Visibility="Collapsed"/>
            </StackPanel>
            <StackPanel Margin="32,0,0,0">
              <TextBlock Text="VERSION" Style="{StaticResource Etiquette}"/>
              <TextBlock x:Name="InfoVersion" Style="{StaticResource ValeurMono}"/>
            </StackPanel>
          </StackPanel>
          <Border Grid.Column="2" BorderBrush="#23262D" BorderThickness="1,0,0,0" MinWidth="330">
            <Grid>
              <Border x:Name="Rond" Width="3" HorizontalAlignment="Left"/>
              <TextBlock x:Name="IconeVerdict" Visibility="Collapsed"/>
              <StackPanel Margin="22,0,24,0" VerticalAlignment="Center">
                <TextBlock Text="VERDICT" Style="{StaticResource Etiquette}"/>
                <TextBlock x:Name="Verdict" FontSize="15" FontWeight="SemiBold" Margin="0,1,0,0"/>
                <TextBlock x:Name="SousVerdict" FontSize="11.5" Foreground="#7B818C" TextWrapping="Wrap" MaxWidth="380"/>
              </StackPanel>
            </Grid>
          </Border>
          <StackPanel Grid.Column="3" Orientation="Horizontal">
            <Border Width="1" Background="#23262D"/>
            <Button x:Name="BtnMin" Style="{StaticResource BtnFenetre}" Content="&#xE921;"/>
            <Button x:Name="BtnFermer" Style="{StaticResource BtnFenetre}" Content="&#xE8BB;"/>
          </StackPanel>
        </Grid>
      </Border>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="236"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Navigation -->
        <Border Background="#111317" BorderBrush="#23262D" BorderThickness="0,0,1,0" CornerRadius="0,0,0,6">
          <DockPanel Margin="0,12,0,14">
            <StackPanel DockPanel.Dock="Bottom" Margin="20,0">
              <TextBlock Text="LECTURE SEULE" Style="{StaticResource Etiquette}"/>
              <TextBlock Text="Aucun fichier modifié, supprimé ou envoyé (sauf les empreintes des mods à Modrinth). « Tester les touches » appuie seulement sur des touches dans le jeu, quand tu cliques." TextWrapping="Wrap" FontSize="11" Foreground="#565B65" Margin="0,4,0,0"/>
            </StackPanel>
            <StackPanel x:Name="Nav"/>
          </DockPanel>
        </Border>

        <!-- Contenu -->
        <Grid Grid.Column="1" Margin="20,16,20,14">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- Progression + actions -->
          <DockPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="20,0,0,0">
              <Button x:Name="BtnTouches" Style="{StaticResource Btn}" Content="Tester les touches" ToolTip="Met Minecraft au premier plan et appuie sur les touches qui ouvrent les menus de cheat (Shift droit, Inser, Suppr...)"/>
              <Button x:Name="BtnCopier" Style="{StaticResource Btn}" Content="Copier le rapport"/>
              <Button x:Name="BtnOuvrir" Style="{StaticResource Btn}" Content="Ouvrir le rapport"/>
              <Button x:Name="BtnRelancer" Style="{StaticResource BtnPrimaire}" Content="Relancer le scan"/>
            </StackPanel>
            <StackPanel VerticalAlignment="Center">
              <TextBlock x:Name="Statut" FontFamily="{StaticResource Mono}" FontSize="11.5" Foreground="#7B818C" TextTrimming="CharacterEllipsis"/>
              <Grid Height="2" Margin="0,8,0,0">
                <Border x:Name="BarreFond" Background="#23262D"/>
                <Border x:Name="Barre" HorizontalAlignment="Left" Width="0"/>
              </Grid>
            </StackPanel>
          </DockPanel>

          <!-- Compteurs -->
          <Border Grid.Row="1" Margin="0,16,0,0" Background="#111317" BorderBrush="#23262D" BorderThickness="1" CornerRadius="4">
            <UniformGrid Columns="4">
              <Border Style="{StaticResource Cellule}">
                <StackPanel>
                  <TextBlock Text="ALERTES" Style="{StaticResource Etiquette}"/>
                  <TextBlock x:Name="StatRouge" Text="0" Style="{StaticResource Chiffre}" Foreground="#E5484D"/>
                  <TextBlock Text="triche quasi certaine" Style="{StaticResource SousChiffre}"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Cellule}">
                <StackPanel>
                  <TextBlock Text="À VÉRIFIER" Style="{StaticResource Etiquette}"/>
                  <TextBlock x:Name="StatOrange" Text="0" Style="{StaticResource Chiffre}" Foreground="#E2A336"/>
                  <TextBlock Text="à voir avec le joueur" Style="{StaticResource SousChiffre}"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Cellule}">
                <StackPanel>
                  <TextBlock Text="MODS ANALYSÉS" Style="{StaticResource Etiquette}"/>
                  <TextBlock x:Name="StatMods" Text="0" Style="{StaticResource Chiffre}"/>
                  <TextBlock Text="comparés à Modrinth" Style="{StaticResource SousChiffre}"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Cellule}" BorderThickness="0">
                <StackPanel>
                  <TextBlock Text="APPAREILS USB" Style="{StaticResource Etiquette}"/>
                  <TextBlock x:Name="StatUsb" Text="0" Style="{StaticResource Chiffre}"/>
                  <TextBlock x:Name="StatUsbSous" Style="{StaticResource SousChiffre}"/>
                </StackPanel>
              </Border>
            </UniformGrid>
          </Border>

          <!-- Titre de section -->
          <DockPanel Grid.Row="2" Margin="0,22,0,10">
            <TextBlock x:Name="CompteListe" DockPanel.Dock="Right" FontFamily="{StaticResource Mono}" FontSize="11" Foreground="#565B65" VerticalAlignment="Bottom"/>
            <TextBlock x:Name="TitreListe" FontSize="11.5" FontWeight="SemiBold" Foreground="#F1F3F6"/>
          </DockPanel>

          <!-- Resultats -->
          <!-- Filtre par launcher (catégorie Mods) -->
          <WrapPanel x:Name="FiltreLaunchers" Grid.Row="3" Margin="0,0,0,8" Visibility="Collapsed"/>

          <ScrollViewer x:Name="Defile" Grid.Row="4" VerticalScrollBarVisibility="Auto">
            <Border VerticalAlignment="Top" BorderBrush="#23262D" BorderThickness="1,1,1,0" CornerRadius="4" Margin="0,0,4,0">
              <ItemsControl x:Name="Liste">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Border x:Name="Ligne" Background="#14161B" BorderBrush="#23262D" BorderThickness="0,0,0,1" Cursor="Hand">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="2"/>
                          <ColumnDefinition Width="118"/>
                          <ColumnDefinition Width="Auto"/>
                          <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Background="{Binding Barre}"/>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top" Margin="12,12,0,10">
                          <Border Width="7" Height="7" CornerRadius="1" Background="{Binding Couleur}" VerticalAlignment="Center"/>
                          <TextBlock Text="{Binding NiveauTexte}" Foreground="{Binding Couleur}" FontFamily="{StaticResource Mono}" FontSize="10.5" FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Grid.Column="2" Text="{Binding CatTexte}" Visibility="{Binding CatVis}" Width="150" Foreground="#7B818C" FontSize="12" Margin="0,10,12,10" TextWrapping="Wrap"/>
                        <StackPanel Grid.Column="3" Margin="0,9,16,10">
                          <TextBlock Text="{Binding Titre}" Foreground="#F1F3F6" FontSize="13" TextWrapping="Wrap"/>
                          <TextBlock Text="{Binding Detail}" Foreground="#7B818C" FontSize="12" Margin="0,2,0,0" TextWrapping="Wrap"/>
                          <TextBlock Text="{Binding Chemin}" Visibility="{Binding CheminVis}" Foreground="#8AB4F8" Opacity="0.85" FontFamily="{StaticResource Mono}" FontSize="11" Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                      </Grid>
                    </Border>
                    <DataTemplate.Triggers>
                      <Trigger SourceName="Ligne" Property="IsMouseOver" Value="True">
                        <Setter TargetName="Ligne" Property="Background" Value="#1A1D23"/>
                      </Trigger>
                    </DataTemplate.Triggers>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </Border>
          </ScrollViewer>

          <!-- Pied -->
          <DockPanel Grid.Row="5" Margin="0,12,0,0">
            <TextBlock DockPanel.Dock="Right" Text="double-clic : ouvrir l'emplacement · clic droit : copier" FontSize="11" Foreground="#565B65"/>
            <TextBlock x:Name="InfoRapport" FontFamily="{StaticResource Mono}" FontSize="11" Foreground="#565B65" TextTrimming="CharacterEllipsis" Margin="0,0,20,0"/>
          </DockPanel>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

function New-Interface {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $script:Pinceaux = @{
        ROUGE  = @{ C = (New-Pinceau '#E5484D') }
        ORANGE = @{ C = (New-Pinceau '#E2A336') }
        OK     = @{ C = (New-Pinceau '#46A758') }
        INFO   = @{ C = (New-Pinceau '#6B7280') }
        ACCENT = @{ C = (New-Pinceau '#8AB4F8') }
        VIDE   = (New-Pinceau '#00000000')
    }

    $w = [Windows.Markup.XamlReader]::Parse($SS_Xaml)
    $ui = @{ Fenetre = $w }
    foreach ($nom in 'Racine', 'BarreTitre', 'SousTitre', 'InfoPc', 'BadgeAdmin', 'IconeAdmin', 'TexteAdmin', 'BtnMin', 'BtnFermer',
                     'Nav', 'Rond', 'IconeVerdict', 'Verdict', 'SousVerdict', 'BarreFond', 'Barre', 'Statut',
                     'StatRouge', 'StatOrange', 'StatMods', 'StatUsb', 'StatUsbSous', 'TitreListe', 'CompteListe', 'InfoVersion', 'FiltreLaunchers',
                     'Defile', 'Liste', 'BtnCopier', 'BtnOuvrir', 'BtnRelancer', 'InfoRapport', 'BtnTouches') {
        $ui[$nom] = $w.FindName($nom)
    }
    $ui.Actions = @($ui.BtnTouches, $ui.BtnCopier, $ui.BtnOuvrir, $ui.BtnRelancer)

    $ui.SousTitre.Text = "RAPPORT DE SCREENSHARE · WINDOWS"
    $ui.InfoPc.Text = "$env:COMPUTERNAME / $env:USERNAME"
    $ui.InfoVersion.Text = "v$SS_Version"
    if ($script:SS_Admin) {
        $ui.TexteAdmin.Text = 'administrateur'
        $ui.TexteAdmin.Foreground = (New-Pinceau '#D7DAE0')
    } else {
        $ui.TexteAdmin.Text = 'utilisateur (scan incomplet)'
        $ui.TexteAdmin.Foreground = $script:Pinceaux.ORANGE.C
    }

    # Navigation
    $panneauNav = $ui.Nav
    $ui.Nav = @{}
    $mono = New-Object System.Windows.Media.FontFamily('Cascadia Mono, Consolas')
    $titreNav = {
        param([string]$t, [string]$marge)
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $t; $tb.FontSize = 10; $tb.FontWeight = 'SemiBold'; $tb.Foreground = (New-Pinceau '#565B65'); $tb.Margin = $marge
        [void]$panneauNav.Children.Add($tb)
    }
    & $titreNav 'VUE' '20,4,0,6'
    foreach ($cle in $SS_Categories.Keys) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $w.FindResource('Nav')
        $rb.Tag = $cle
        $g = New-Object System.Windows.Controls.DockPanel
        $cpt = New-Object System.Windows.Controls.StackPanel
        $cpt.Orientation = 'Horizontal'
        [System.Windows.Controls.DockPanel]::SetDock($cpt, 'Right')
        $cr = New-Object System.Windows.Controls.TextBlock; $cr.FontFamily = $mono; $cr.FontSize = 11; $cr.Foreground = $script:Pinceaux.ROUGE.C; $cr.Visibility = 'Collapsed'
        $co = New-Object System.Windows.Controls.TextBlock; $co.FontFamily = $mono; $co.FontSize = 11; $co.Foreground = $script:Pinceaux.ORANGE.C; $co.Margin = '10,0,0,0'; $co.Visibility = 'Collapsed'
        $cz = New-Object System.Windows.Controls.TextBlock; $cz.FontFamily = $mono; $cz.FontSize = 11; $cz.Foreground = (New-Pinceau '#565B65'); $cz.Text = '0'
        foreach ($t in $cr, $co, $cz) { $t.VerticalAlignment = 'Center'; [void]$cpt.Children.Add($t) }
        $lb = New-Object System.Windows.Controls.TextBlock
        $lb.Text = $SS_Categories[$cle]
        $lb.FontSize = 13
        $lb.VerticalAlignment = 'Center'
        [void]$g.Children.Add($cpt); [void]$g.Children.Add($lb)
        $rb.Content = $g
        $rb.Add_Checked({ param($s, $e) if (-not $script:ChangeNav) { Show-Categorie $s.Tag } })
        [void]$panneauNav.Children.Add($rb)
        if ($cle -eq 'Resume') { & $titreNav 'CATÉGORIES' '20,16,0,6' }
        $ui.Nav[$cle] = @{ Bouton = $rb; R = $cr; O = $co; Z = $cz }
    }
    # $ui.Nav est maintenant la table ; on garde le panneau a part
    $script:UI = $ui

    # Menu clic droit
    $menu = New-Object System.Windows.Controls.ContextMenu
    $mCopier = New-Object System.Windows.Controls.MenuItem
    $mCopier.Header = 'Copier la ligne'
    $mCopier.Add_Click({
        $it = $script:ItemClic
        if ($it) { [System.Windows.Clipboard]::SetText(('[{0}] {1} : {2} {3}' -f $it.Source.Niveau, $it.Source.Titre, $it.Source.Detail, $it.Source.Chemin).Trim()) }
    })
    $mOuvrir = New-Object System.Windows.Controls.MenuItem
    $mOuvrir.Header = 'Ouvrir l''emplacement'
    $mOuvrir.Add_Click({ Open-Emplacement $script:ItemClic })
    [void]$menu.Items.Add($mCopier); [void]$menu.Items.Add($mOuvrir)
    $ui.Liste.ContextMenu = $menu
    $ui.Liste.Add_PreviewMouseRightButtonDown({ param($s, $e) $script:ItemClic = Get-ItemSous $e.OriginalSource })
    $ui.Liste.Add_PreviewMouseLeftButtonDown({
        param($s, $e)
        if ($e.ClickCount -eq 2) { Open-Emplacement (Get-ItemSous $e.OriginalSource) }
    })

    # Fenetre
    $ui.BarreTitre.Add_MouseLeftButtonDown({ param($s, $e) if ($e.ButtonState -eq 'Pressed') { try { $script:UI.Fenetre.DragMove() } catch { } } })
    $ui.BtnMin.Add_Click({ $script:UI.Fenetre.WindowState = 'Minimized' })
    $ui.BtnFermer.Add_Click({ $script:UI.Fenetre.Close() })
    $ui.BtnRelancer.Add_Click({ Start-Scan })
    $ui.BtnOuvrir.Add_Click({ if ($script:SS_Fichier -and (Test-Path -LiteralPath $script:SS_Fichier)) { Start-Process notepad.exe -ArgumentList ('"' + $script:SS_Fichier + '"') } })
    $ui.BtnTouches.Add_Click({ Start-TestTouches })
    $ui.BtnCopier.Add_Click({
        [System.Windows.Clipboard]::SetText((Get-TexteRapport))
        $script:UI.Statut.Text = 'Rapport copié dans le presse-papiers'
    })
    $w.Add_Closing({ $script:Annule = $true })
    $w.Add_ContentRendered({
        $script:UI.Fenetre.Topmost = $true
        $script:UI.Fenetre.Activate()
        $script:UI.Fenetre.Topmost = $false
        Start-Scan
        if ($env:SNOWSS_CAPTURE) {
            try {
                if ($env:SNOWSS_CAPTURE_FILTRE) { $script:FiltreLauncher = $env:SNOWSS_CAPTURE_FILTRE }
                if ($env:SNOWSS_CAPTURE_CAT) { Show-Categorie $env:SNOWSS_CAPTURE_CAT }
                Invoke-PompeUi
                $el = $script:UI.Fenetre.Content
                $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(([int]$el.ActualWidth + 28), ([int]$el.ActualHeight + 28), 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
                $rtb.Render($el)
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                $fs = [IO.File]::Create($env:SNOWSS_CAPTURE)
                $enc.Save($fs)
                $fs.Close()
            } catch { [IO.File]::WriteAllText($env:SNOWSS_CAPTURE + '.err', ($_ | Out-String)) }
            $script:UI.Fenetre.Close()
        }
    })

    Update-Verdict
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
    [void]$script:UI.Fenetre.ShowDialog()
    $script:UI = $null
}
