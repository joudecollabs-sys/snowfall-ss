# =====================================================================
#  SnowFall SS v3.3 - outil de screenshare du staff SnowFall
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
$SS_Version       = '3.3'

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
    Injection  = 'Injection / stream-proof'
    Mods       = 'Mods'
    Programmes = 'Programmes'
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

function Initialize-Natif {
    if (-not ('SnowNatif' -as [type])) { Add-Type -TypeDefinition $SS_CodeNatif -ErrorAction Stop }
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
        Invoke-ScanInjection $p $cmd
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

    $script:SS_NbJars = $jars.Count
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
    if ($liste.Count -eq 0) { Add-Res Usb INFO 'Appareils USB' 'Aucun appareil USB trouvé (ou liste illisible).'; return }

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
        $script:UI.Rond.Background = $p.F
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
        Invoke-ScanProgrammes
        Invoke-ScanStreamProof
        Invoke-ScanUsb
        Invoke-ScanPeripheriques
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
        if ($r -gt 0) { $niv = 'ROUGE' } elseif ($o -gt 0) { $niv = 'ORANGE' } else { $niv = $null }
        if ($niv) {
            $p = $script:Pinceaux[$niv]
            $n.Pastille.Visibility = 'Visible'
            $n.Pastille.Background = $p.F
            $n.Compte.Foreground = $p.C
            $n.Compte.Text = [string]($r + $o)
        } else {
            $n.Pastille.Visibility = 'Collapsed'
        }
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
        $titre = $r.Titre
        if ($Cle -eq 'Resume' -and $r.Cat -ne 'Resume') { $titre = $SS_Categories[$r.Cat] + '  ›  ' + $titre }
        $chemin = ''; $vis = 'Collapsed'
        if ($r.Chemin -and -not "$($r.Detail)".Contains($r.Chemin)) { $chemin = $r.Chemin; $vis = 'Visible' }
        $items.Add([pscustomobject]@{
            Titre = $titre; Detail = "$($r.Detail)"; Chemin = $chemin; CheminVis = $vis
            Couleur = $p.C; FondPill = $p.F; NiveauTexte = $r.Niveau; Source = $r
        })
    }
    $script:UI.Liste.ItemsSource = $items
    $script:UI.TitreListe.Text = $SS_Categories[$Cle]
    $script:UI.CompteListe.Text = ('{0} élément(s)' -f $rows.Count)
    if (-not $memeCat) { $script:UI.Defile.ScrollToTop() }
    $script:ChangeNav = $true
    try { $script:UI.Nav[$Cle].Bouton.IsChecked = $true } finally { $script:ChangeNav = $false }
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
        Title="SnowFall SS" Width="1260" Height="820" MinWidth="1000" MinHeight="640"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Display" UseLayoutRounding="True">
  <Window.Resources>
    <FontFamily x:Key="Icones">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>

    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#C3CEE0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="GroupName" Value="Nav"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="10" Padding="14,11">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#131C2F"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1A2640"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="#DCE6F5"/>
      <Setter Property="Background" Value="#141E33"/>
      <Setter Property="BorderBrush" Value="#24324F"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="10,0,0,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="10" Padding="18,10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
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
      <Setter Property="Background" Value="#6EC1FF"/>
      <Setter Property="BorderBrush" Value="#6EC1FF"/>
      <Setter Property="Foreground" Value="#06101F"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style x:Key="BtnFenetre" TargetType="Button">
      <Setter Property="Foreground" Value="#8B9AB5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="8">
              <TextBlock Text="{TemplateBinding Content}" FontFamily="{StaticResource Icones}" FontSize="11"
                         Foreground="{TemplateBinding Foreground}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1A2540"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Stat" TargetType="Border">
      <Setter Property="Background" Value="#0F1729"/>
      <Setter Property="BorderBrush" Value="#1C2740"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="14"/>
      <Setter Property="Padding" Value="20,16"/>
      <Setter Property="Margin" Value="0,0,12,0"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Racine" CornerRadius="18" Background="#0A0F1A" BorderBrush="#1E2A42" BorderThickness="1" Margin="14">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.6" Color="#000000"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="70"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <!-- Barre de titre -->
      <Grid x:Name="BarreTitre" Background="Transparent" Margin="22,0,14,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Border Width="40" Height="40" CornerRadius="12">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#6EC1FF" Offset="0"/>
                <GradientStop Color="#3D7BFF" Offset="1"/>
              </LinearGradientBrush>
            </Border.Background>
            <TextBlock Text="❄" FontSize="22" Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" FontFamily="Segoe UI Symbol"/>
          </Border>
          <StackPanel Margin="14,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="SnowFall SS" FontSize="19" FontWeight="SemiBold" Foreground="#F2F6FC"/>
            <TextBlock x:Name="SousTitre" Text="Outil de screenshare du staff" FontSize="12" Foreground="#7D8CA8"/>
          </StackPanel>
        </StackPanel>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,14,0">
          <Border Background="#121B2E" CornerRadius="9" Padding="12,6" Margin="0,0,8,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE7F4;" FontFamily="{StaticResource Icones}" FontSize="13" Foreground="#7D8CA8" VerticalAlignment="Center"/>
              <TextBlock x:Name="InfoPc" Margin="8,0,0,0" FontSize="12.5" Foreground="#C3CEE0" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
          <Border x:Name="BadgeAdmin" CornerRadius="9" Padding="12,6">
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="IconeAdmin" Text="&#xE83D;" FontFamily="{StaticResource Icones}" FontSize="13" VerticalAlignment="Center"/>
              <TextBlock x:Name="TexteAdmin" Margin="8,0,0,0" FontSize="12.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
        </StackPanel>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnMin" Style="{StaticResource BtnFenetre}" Content="&#xE921;"/>
          <Button x:Name="BtnFermer" Style="{StaticResource BtnFenetre}" Content="&#xE8BB;"/>
        </StackPanel>
      </Grid>

      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="236"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Navigation -->
        <DockPanel Margin="16,6,10,18">
          <TextBlock DockPanel.Dock="Top" Text="CATÉGORIES" FontSize="11" FontWeight="SemiBold" Foreground="#5F6E8A" Margin="14,0,0,10"/>
          <Border DockPanel.Dock="Bottom" Background="#0F1729" BorderBrush="#1C2740" BorderThickness="1" CornerRadius="12" Padding="14,12">
            <StackPanel>
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE72E;" FontFamily="{StaticResource Icones}" FontSize="13" Foreground="#4FD69C" VerticalAlignment="Center"/>
                <TextBlock Text="Lecture seule" Margin="8,0,0,0" FontSize="12.5" FontWeight="SemiBold" Foreground="#C3CEE0"/>
              </StackPanel>
              <TextBlock Text="Rien n'est modifié, supprimé ou envoyé (sauf les empreintes des mods à Modrinth)." TextWrapping="Wrap" FontSize="11.5" Foreground="#6F7E9A" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
          <StackPanel x:Name="Nav"/>
        </DockPanel>

        <!-- Contenu -->
        <Grid Grid.Column="1" Margin="8,6,24,18">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- Verdict -->
          <Border CornerRadius="16" BorderBrush="#1E2A42" BorderThickness="1" Padding="26,22">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#13203A" Offset="0"/>
                <GradientStop Color="#0D1526" Offset="1"/>
              </LinearGradientBrush>
            </Border.Background>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Border x:Name="Rond" Width="76" Height="76" CornerRadius="38" VerticalAlignment="Center">
                <TextBlock x:Name="IconeVerdict" FontFamily="{StaticResource Icones}" FontSize="32" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel Grid.Column="1" Margin="22,0,0,0" VerticalAlignment="Center">
                <TextBlock Text="VERDICT" FontSize="11" FontWeight="SemiBold" Foreground="#6F7E9A"/>
                <TextBlock x:Name="Verdict" FontSize="30" FontWeight="Bold" Margin="0,2,0,0"/>
                <TextBlock x:Name="SousVerdict" FontSize="13.5" Foreground="#9AA8C2" TextWrapping="Wrap" Margin="0,2,0,0"/>
                <Grid Margin="0,16,0,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <Grid Height="6" VerticalAlignment="Center">
                    <Border x:Name="BarreFond" Background="#1A2540" CornerRadius="3"/>
                    <Border x:Name="Barre" HorizontalAlignment="Left" Width="0" CornerRadius="3"/>
                  </Grid>
                  <TextBlock x:Name="Statut" Grid.Column="1" Margin="14,0,0,0" FontSize="12" Foreground="#7D8CA8" MinWidth="260" TextTrimming="CharacterEllipsis"/>
                </Grid>
              </StackPanel>
            </Grid>
          </Border>

          <!-- Stats -->
          <UniformGrid Grid.Row="1" Columns="4" Margin="0,14,-12,0">
            <Border Style="{StaticResource Stat}">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Ellipse Width="8" Height="8" Fill="#FF5C6C" VerticalAlignment="Center"/>
                  <TextBlock Text="Alertes rouges" Margin="8,0,0,0" FontSize="12.5" Foreground="#8B9AB5"/>
                </StackPanel>
                <TextBlock x:Name="StatRouge" Text="0" FontSize="30" FontWeight="Bold" Foreground="#FF5C6C" Margin="0,6,0,0"/>
                <TextBlock Text="triche quasi certaine" FontSize="11.5" Foreground="#5F6E8A"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Stat}">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Ellipse Width="8" Height="8" Fill="#FFB547" VerticalAlignment="Center"/>
                  <TextBlock Text="Alertes orange" Margin="8,0,0,0" FontSize="12.5" Foreground="#8B9AB5"/>
                </StackPanel>
                <TextBlock x:Name="StatOrange" Text="0" FontSize="30" FontWeight="Bold" Foreground="#FFB547" Margin="0,6,0,0"/>
                <TextBlock Text="à vérifier avec le joueur" FontSize="11.5" Foreground="#5F6E8A"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Stat}">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Ellipse Width="8" Height="8" Fill="#6EC1FF" VerticalAlignment="Center"/>
                  <TextBlock Text="Mods analysés" Margin="8,0,0,0" FontSize="12.5" Foreground="#8B9AB5"/>
                </StackPanel>
                <TextBlock x:Name="StatMods" Text="0" FontSize="30" FontWeight="Bold" Foreground="#E6EDF7" Margin="0,6,0,0"/>
                <TextBlock Text="comparés à Modrinth" FontSize="11.5" Foreground="#5F6E8A"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Stat}">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <Ellipse Width="8" Height="8" Fill="#4FD69C" VerticalAlignment="Center"/>
                  <TextBlock Text="Appareils USB branchés" Margin="8,0,0,0" FontSize="12.5" Foreground="#8B9AB5"/>
                </StackPanel>
                <TextBlock x:Name="StatUsb" Text="0" FontSize="30" FontWeight="Bold" Foreground="#E6EDF7" Margin="0,6,0,0"/>
                <TextBlock x:Name="StatUsbSous" Text="0 dans l'historique" FontSize="11.5" Foreground="#5F6E8A"/>
              </StackPanel>
            </Border>
          </UniformGrid>

          <!-- Titre de section -->
          <DockPanel Grid.Row="2" Margin="2,22,0,12">
            <TextBlock x:Name="CompteListe" DockPanel.Dock="Right" FontSize="12.5" Foreground="#6F7E9A" VerticalAlignment="Bottom"/>
            <TextBlock x:Name="TitreListe" Text="Résumé" FontSize="18" FontWeight="SemiBold" Foreground="#F2F6FC"/>
          </DockPanel>

          <!-- Resultats -->
          <ScrollViewer x:Name="Defile" Grid.Row="3" VerticalScrollBarVisibility="Auto" Padding="0,0,6,0">
            <ItemsControl x:Name="Liste">
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Border x:Name="Carte" Background="#0F1729" BorderBrush="#1C2740" BorderThickness="1" CornerRadius="12" Margin="0,0,0,8" Cursor="Hand">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="4"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <Border Background="{Binding Couleur}" CornerRadius="12,0,0,12"/>
                      <Grid Grid.Column="1" Margin="16,12,16,13">
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                          <TextBlock Text="{Binding Titre}" Foreground="#E6EDF7" FontSize="14" FontWeight="SemiBold" TextWrapping="Wrap"/>
                          <TextBlock Text="{Binding Detail}" Foreground="#8E9CB7" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                          <TextBlock Text="{Binding Chemin}" Visibility="{Binding CheminVis}" Foreground="#56678A" FontFamily="Consolas" FontSize="11.5" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                        <Border Grid.Column="1" VerticalAlignment="Top" Background="{Binding FondPill}" CornerRadius="8" Padding="10,3" Margin="14,0,0,0">
                          <TextBlock Text="{Binding NiveauTexte}" Foreground="{Binding Couleur}" FontSize="11" FontWeight="Bold"/>
                        </Border>
                      </Grid>
                    </Grid>
                  </Border>
                  <DataTemplate.Triggers>
                    <Trigger SourceName="Carte" Property="IsMouseOver" Value="True">
                      <Setter TargetName="Carte" Property="Background" Value="#142037"/>
                      <Setter TargetName="Carte" Property="BorderBrush" Value="#2A3A5C"/>
                    </Trigger>
                  </DataTemplate.Triggers>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
          </ScrollViewer>

          <!-- Pied -->
          <DockPanel Grid.Row="4" Margin="0,14,0,0">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="BtnCopier" Style="{StaticResource Btn}" Content="Copier le rapport"/>
              <Button x:Name="BtnOuvrir" Style="{StaticResource Btn}" Content="Ouvrir le rapport"/>
              <Button x:Name="BtnRelancer" Style="{StaticResource BtnPrimaire}" Content="Relancer le scan"/>
            </StackPanel>
            <StackPanel VerticalAlignment="Center">
              <TextBlock Text="Double-clic sur une carte : ouvrir l'emplacement  ·  clic droit : copier" FontSize="11.5" Foreground="#56678A"/>
              <TextBlock x:Name="InfoRapport" FontSize="11.5" Foreground="#6F7E9A" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
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
        ROUGE  = @{ C = (New-Pinceau '#FF5C6C'); F = (New-Pinceau '#2EFF5C6C') }
        ORANGE = @{ C = (New-Pinceau '#FFB547'); F = (New-Pinceau '#2EFFB547') }
        OK     = @{ C = (New-Pinceau '#4FD69C'); F = (New-Pinceau '#294FD69C') }
        INFO   = @{ C = (New-Pinceau '#8FA3C4'); F = (New-Pinceau '#1F8FA3C4') }
        ACCENT = @{ C = (New-Pinceau '#6EC1FF'); F = (New-Pinceau '#296EC1FF') }
    }

    $w = [Windows.Markup.XamlReader]::Parse($SS_Xaml)
    $ui = @{ Fenetre = $w }
    foreach ($nom in 'Racine', 'BarreTitre', 'SousTitre', 'InfoPc', 'BadgeAdmin', 'IconeAdmin', 'TexteAdmin', 'BtnMin', 'BtnFermer',
                     'Nav', 'Rond', 'IconeVerdict', 'Verdict', 'SousVerdict', 'BarreFond', 'Barre', 'Statut',
                     'StatRouge', 'StatOrange', 'StatMods', 'StatUsb', 'StatUsbSous', 'TitreListe', 'CompteListe',
                     'Defile', 'Liste', 'BtnCopier', 'BtnOuvrir', 'BtnRelancer', 'InfoRapport') {
        $ui[$nom] = $w.FindName($nom)
    }
    $ui.Actions = @($ui.BtnCopier, $ui.BtnOuvrir, $ui.BtnRelancer)

    $ui.SousTitre.Text = "Outil de screenshare du staff  ·  v$SS_Version"
    $ui.InfoPc.Text = "$env:COMPUTERNAME  ·  $env:USERNAME"
    if ($script:SS_Admin) {
        $p = $script:Pinceaux.OK
        $ui.TexteAdmin.Text = 'Administrateur'
    } else {
        $p = $script:Pinceaux.ORANGE
        $ui.TexteAdmin.Text = 'Pas administrateur : scan incomplet'
    }
    $ui.BadgeAdmin.Background = $p.F
    $ui.TexteAdmin.Foreground = $p.C
    $ui.IconeAdmin.Foreground = $p.C

    # Navigation
    $panneauNav = $ui.Nav
    $ui.Nav = @{}
    $police = New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
    foreach ($cle in $SS_Categories.Keys) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $w.FindResource('Nav')
        $rb.Tag = $cle
        $g = New-Object System.Windows.Controls.Grid
        foreach ($largeur in 'Auto', '*', 'Auto') {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = (New-Object System.Windows.GridLengthConverter).ConvertFromString($largeur)
            $g.ColumnDefinitions.Add($cd)
        }
        $ic = New-Object System.Windows.Controls.TextBlock
        $ic.Text = [string][char]$SS_Icones[$cle]
        $ic.FontFamily = $police
        $ic.FontSize = 15
        $ic.VerticalAlignment = 'Center'
        $lb = New-Object System.Windows.Controls.TextBlock
        $lb.Text = $SS_Categories[$cle]
        $lb.FontSize = 13.5
        $lb.Margin = '12,0,0,0'
        $lb.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($lb, 1)
        $pas = New-Object System.Windows.Controls.Border
        $pas.CornerRadius = 8
        $pas.Padding = '8,1'
        $pas.Visibility = 'Collapsed'
        $pas.VerticalAlignment = 'Center'
        $cp = New-Object System.Windows.Controls.TextBlock
        $cp.FontSize = 11.5
        $cp.FontWeight = 'Bold'
        $pas.Child = $cp
        [System.Windows.Controls.Grid]::SetColumn($pas, 2)
        [void]$g.Children.Add($ic); [void]$g.Children.Add($lb); [void]$g.Children.Add($pas)
        $rb.Content = $g
        $rb.Add_Checked({ param($s, $e) if (-not $script:ChangeNav) { Show-Categorie $s.Tag } })
        [void]$panneauNav.Children.Add($rb)
        if ($cle -eq 'Resume') {
            $sep = New-Object System.Windows.Controls.Border
            $sep.Height = 1; $sep.Background = (New-Pinceau '#1C2740'); $sep.Margin = '10,6,10,10'
            [void]$panneauNav.Children.Add($sep)
        }
        $ui.Nav[$cle] = @{ Bouton = $rb; Pastille = $pas; Compte = $cp }
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
