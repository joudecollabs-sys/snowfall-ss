#!/usr/bin/env bash
# =====================================================================
#  SnowFall SS (Linux) v1.0 - outil de screenshare du staff SnowFall
#
#  CE QUE FAIT CE SCRIPT (lecture seule) :
#    - Minecraft lance : version, dossier, agents Java, LD_PRELOAD,
#      bibliotheques .so injectees, debogueur attache, jars ouverts/supprimes
#    - mods : SHA-1 de chaque jar compare a Modrinth, jars inconnus fouilles,
#      mods charges au lancement mais supprimes depuis (logs/latest.log)
#    - programmes : autoclickers / macros / injecteurs ouverts
#    - USB : appareils branches (souris, claviers, cartes Arduino...),
#      cles montees (contenu fouille), branchements/debranchements recents
#    - fichiers recents, corbeille, fichiers ouverts depuis une cle
#    - rapport .txt enregistre dans le dossier personnel
#
#  CE QU'IL NE FAIT PAS :
#    - il ne modifie, ne supprime et ne lance AUCUN fichier
#    - il n'envoie RIEN, sauf les empreintes SHA-1 des jars a api.modrinth.com
#
#  Lancement :  curl -fsSL URL_RAW | sudo bash     (sudo = scan complet)
# =====================================================================
if ! command -v python3 >/dev/null 2>&1; then
  echo "SnowFall SS a besoin de python3. Installe-le (ex : sudo apt install python3) puis relance."
  exit 1
fi
exec python3 - "$@" <<'SNOWSS_FIN_PYTHON'
import os, sys, re, io, json, glob, time, zipfile, hashlib, datetime, subprocess, pwd, platform, socket
import urllib.request, urllib.parse

VERSION = '1.0'
HEURES = 48
SEUIL_MODRINTH = 2000
MIN_AVANT_SCAN = 30
NOW = time.time()
DEPUIS = NOW - HEURES * 3600
UA = 'SnowFall-SS-Linux/' + VERSION
ROOT = (os.geteuid() == 0)
UTILISATEUR = os.environ.get('SUDO_USER') or pwd.getpwuid(os.getuid()).pw_name
try:
    HOME = pwd.getpwnam(UTILISATEUR).pw_dir
except Exception:
    HOME = os.path.expanduser('~')

C = {'ROUGE': '\033[91m', 'ORANGE': '\033[93m', 'OK': '\033[92m', 'INFO': '\033[37m',
     'T': '\033[96m', 'B': '\033[1m', 'R': '\033[0m', 'G': '\033[90m'}
RES = []
CATS = [('Systeme', 'Système'), ('Minecraft', 'Minecraft'), ('Injection', 'Injection dans le jeu'),
        ('Mods', 'Mods'), ('Programmes', 'Programmes'), ('Usb', 'USB'),
        ('Fichiers', 'Fichiers récents'), ('Corbeille', 'Corbeille')]

def add(cat, niv, titre, detail='', chemin=''):
    RES.append((cat, niv, titre, detail, chemin))
    d = ('  ' + C['G'] + detail + C['R']) if detail else ''
    print('  {}[{:<6}]{} {}{}'.format(C[niv], niv, C['R'], titre, d))

def etape(t):
    print('\n' + C['T'] + C['B'] + '=== ' + t + ' ===' + C['R'])

def fdate(ts):
    return datetime.datetime.fromtimestamp(ts).strftime('%d/%m/%Y %H:%M') if ts else '?'

def fduree(s):
    s = int(max(0, s)); h = s // 3600; m = (s % 3600) // 60
    if h == 0: return '%d min' % m
    if h < 24: return '%d h %d min' % (h, m)
    return '%d j %d h' % (h // 24, h % 24)

def ftaille(o):
    if o >= 1 << 30: return '%.1f Go' % (o / float(1 << 30))
    if o >= 1 << 20: return '%.1f Mo' % (o / float(1 << 20))
    return '%d Ko' % (o // 1024)

def lire(p, binaire=False):
    try:
        with open(p, 'rb') as f:
            d = f.read()
        return d if binaire else d.decode('utf-8', 'replace')
    except Exception:
        return None

# ---------------- signatures ----------------
PAQUETS = ['meteordevelopment/', 'net/wurstclient/', 'net/ccbluex/', 'org/rusherhack/', 'thunder/hack/',
           'bleach/hack/', 'org/bleachhack/', 'me/zeroeightsix/kami/', 'com/lambda/client/', 'dev/boze/',
           'me/earth/earthhack/', 'me/alpha432/oyvey/', 'me/deftware/', 'dev/lvstrng/argon/', 'net/impactclient/']
RE_MODULE = re.compile(r'(?i)(^|/)(KillAura|TriggerBot|AimAssist|AimBot|AutoClicker|CrystalAura|AutoCrystal|AnchorAura|AutoAnchor|AutoHitCrystal|AutoDoubleHand|AutoInventoryTotem|HoverTotem|Scaffold|Nuker|Reach|Velocity|AntiKnockback|NoFall|Flight|Criticals|Tracers|XRay|SelfDestruct|AutoPot|ShieldDisabler|AutoMace|ElytraFly|LegitTotem|AutoWeb)(Module|Hack|Feature|Mod)?\.class$')
RE_STRUCT = re.compile(r'(?i)/modules?/(combat|movement|render|player|misc|world|exploit|ghost|crystal)/')
RE_NOM = re.compile(r'(?i)(meteor|wurst|aristois|liquidbounce|rusherhack|thunderhack|bleachhack|kami|salhack|inertia|boze|doomsday|argon|prestige|vape|phobos|konas|earthhack|oyvey|shoreline|nullpoint|cornos|coffee.?client|auto.?click|killaura|trigger.?bot|aim.?assist|ghost.?client|cheat|hack|x-?ray|injector|self.?destruct)')
RE_INTERDIT = re.compile(r'(?i)(x-?ray|baritone|freecam|seed-?cracker|auto-?click|meteor|wurst|elytra-?fly|auto-?totem)')
RE_PROG = re.compile(r'(?i)(auto.?click|clicker|macro|xdotool|ydotool|autokey|xautoclick|cheat|inject|scanmem|gameconqueror|frida|ghost.?client|jattach)')
RE_JEU = re.compile(r'(?i)minecraft|fabric|forge|quilt|lunar|feather|badlion|labymod')
RE_SO_NORMAL = re.compile(r'(?i)(lwjgl|glfw|openal|jemalloc|jna|jinput|sqlite|zstd|netty|lz4|(opus|rnnoise|speex|lame)4j|discord|nvidia|mesa|libGL|libEGL|libvulkan|libdrm|libX|libxcb|libwayland|libpulse|libasound|libpipewire|mangohud|gamemode|obs|steam|libgtk|libgdk|libglib|libdbus|libsystemd|libudev|libfreetype|libfontconfig|libz\.|libssl|libcrypto)')
MARQUES = {'046d': 'Logitech', '1532': 'Razer', '1038': 'SteelSeries', '1b1c': 'Corsair', '0951': 'HyperX / Kingston',
           '03f0': 'HP / HyperX', '3151': 'MonsGeek / Akko', '258a': 'SinoWealth (générique)', '09da': 'A4Tech / Bloody',
           '1e7d': 'Roccat', '054c': 'Sony', '05ac': 'Apple', '045e': 'Microsoft', '0e8d': 'MediaTek', '1462': 'MSI',
           '0b05': 'ASUS', '2516': 'Cooler Master', '04d9': 'Holtek (générique)', '093a': 'PixArt', '0781': 'SanDisk',
           '090c': 'Silicon Motion', '13fe': 'Phison', '058f': 'Alcor', '8564': 'Transcend', '18d1': 'Google / Android',
           '04e8': 'Samsung', '2717': 'Xiaomi', '8087': 'Intel', '0bda': 'Realtek', '3434': 'Keychron', '342d': 'Glorious'}
MICRO = {'2341': 'Arduino', '2a03': 'Arduino', '1b4f': 'SparkFun', '16c0': 'Teensy / V-USB', '239a': 'Adafruit',
         '2e8a': 'Raspberry Pi Pico', '1a86': 'CH340 (clone Arduino)', '10c4': 'Silicon Labs CP210x', '0403': 'FTDI',
         '303a': 'Espressif ESP32', '0483': 'STMicro', '1209': 'pid.codes (open hardware)', '2886': 'Seeed', '1fc9': 'NXP'}

# ---------------- cles USB montees ----------------
def montages_externes():
    res = []
    for l in (lire('/proc/mounts') or '').splitlines():
        p = l.split()
        if len(p) < 3: continue
        mp = p[1].replace('\\040', ' ')
        if re.match(r'^/(media|run/media|mnt)/', mp) and p[2] not in ('autofs', 'tmpfs', 'overlay'):
            res.append((mp, p[0], p[2]))
    return res
MONTAGES = montages_externes()
def sur_usb(chemin):
    return any(chemin == m[0] or chemin.startswith(m[0] + '/') for m in MONTAGES)
def externe(chemin):
    return bool(re.match(r'^/(media|run/media|mnt)/', chemin or ''))

# ---------------- analyse des jars ----------------
def lire_zip(z, r, prof):
    for info in z.infolist():
        n = info.filename
        if n.endswith('.class'):
            r['classes'] += 1
            simple = n.rsplit('/', 1)[-1][:-6].split('$')[0]
            if len(simple) <= 2 or re.fullmatch(r'[Il1]+', simple) or re.fullmatch(r'[O0o]+', simple): r['obf'] += 1
            if re.search(r'[^\x20-\x7e]', n): r['uni'] += 1
            ln = n.lower()
            for pq in PAQUETS:
                if ln.startswith(pq) and pq not in r['paq']: r['paq'].append(pq)
            m = RE_MODULE.search(n)
            if m and m.group(2) not in r['mod']: r['mod'].append(m.group(2))
            if RE_STRUCT.search(n): r['struct'] += 1
            continue
        if prof == 0:
            try:
                if n in ('fabric.mod.json', 'quilt.mod.json'):
                    t = z.read(n).decode('utf-8', 'replace')
                    m = re.search(r'"id"\s*:\s*"([^"]+)"', t); r['id'] = r['id'] or (m.group(1) if m else None)
                    m = re.search(r'"name"\s*:\s*"([^"]+)"', t); r['nom'] = r['nom'] or (m.group(1) if m else None)
                    continue
                if n in ('META-INF/mods.toml', 'META-INF/neoforge.mods.toml'):
                    t = z.read(n).decode('utf-8', 'replace')
                    m = re.search(r'modId\s*=\s*"([^"]+)"', t); r['id'] = r['id'] or (m.group(1) if m else None)
                    continue
                if n in ('mcmod.info', 'litemod.json'):
                    t = z.read(n).decode('utf-8', 'replace')
                    m = re.search(r'"(?:modid|name)"\s*:\s*"([^"]+)"', t); r['id'] = r['id'] or (m.group(1) if m else None)
                    continue
                if n == 'META-INF/MANIFEST.MF':
                    if re.search(r'(?im)^(Premain-Class|Agent-Class|Launcher-Agent-Class):', z.read(n).decode('utf-8', 'replace')): r['agent'] = True
                    continue
            except Exception:
                pass
        if n.endswith('.jar') and prof < 2:
            try: lire_zip(zipfile.ZipFile(io.BytesIO(z.read(n))), r, prof + 1)
            except Exception: pass

def analyse_jar(chemin, nom):
    r = {'id': None, 'nom': None, 'agent': False, 'classes': 0, 'obf': 0, 'uni': 0, 'struct': 0, 'paq': [], 'mod': [], 'err': None}
    try:
        with zipfile.ZipFile(chemin) as z: lire_zip(z, r, 0)
    except Exception:
        r['err'] = 'jar illisible ou corrompu'
    niv = None; rs = []
    def monte(n):
        nonlocal niv
        if n == 'ROUGE' or niv is None: niv = n if niv != 'ROUGE' else 'ROUGE'
    if r['paq']: niv = 'ROUGE'; rs.append("code d'un client de triche connu (" + ', '.join(r['paq']) + ')')
    if len(r['mod']) >= 3 or (r['mod'] and r['struct'] >= 3): niv = 'ROUGE'; rs.append('modules de triche : ' + ', '.join(r['mod']))
    elif r['mod']: monte('ORANGE'); rs.append('nom de classe suspect : ' + ', '.join(r['mod']))
    elif r['struct'] >= 3: monte('ORANGE'); rs.append('structure de client de triche (modules/combat...)')
    if r['classes'] >= 30 and r['obf'] / float(r['classes']) >= 0.4: monte('ORANGE'); rs.append('code obfusqué (%d %% des classes)' % (100 * r['obf'] / r['classes']))
    if r['uni']: monte('ORANGE'); rs.append('noms de classes avec des caractères bizarres')
    if r['agent']: monte('ORANGE'); rs.append('jar fait pour être injecté (agent Java)')
    if r['err']: monte('ORANGE'); rs.append(r['err'])
    elif not r['id']: monte('ORANGE'); rs.append('aucun fichier de mod (ni fabric.mod.json ni mods.toml)')
    m = RE_NOM.search('%s %s %s' % (nom, r['id'] or '', r['nom'] or ''))
    if m: monte('ORANGE'); rs.append("nom suspect ('%s')" % m.group(1))
    return niv, ' ; '.join(rs), r['id']

def mod_id_rapide(chemin):
    try:
        with zipfile.ZipFile(chemin) as z:
            for n in ('fabric.mod.json', 'quilt.mod.json'):
                if n in z.namelist():
                    m = re.search(r'"id"\s*:\s*"([^"]+)"', z.read(n).decode('utf-8', 'replace'))
                    if m: return m.group(1)
    except Exception:
        pass
    return None

def modrinth(hashes):
    out = {}
    if not hashes: return out
    try:
        vers = {}
        for i in range(0, len(hashes), 100):
            body = json.dumps({'hashes': hashes[i:i + 100], 'algorithm': 'sha1'}).encode()
            req = urllib.request.Request('https://api.modrinth.com/v2/version_files', data=body,
                                         headers={'Content-Type': 'application/json', 'User-Agent': UA})
            vers.update(json.load(urllib.request.urlopen(req, timeout=30)))
        ids = sorted(set(v['project_id'] for v in vers.values()))
        proj = {}
        for i in range(0, len(ids), 100):
            q = urllib.parse.quote(json.dumps(ids[i:i + 100]))
            req = urllib.request.Request('https://api.modrinth.com/v2/projects?ids=' + q, headers={'User-Agent': UA})
            for p in json.load(urllib.request.urlopen(req, timeout=30)): proj[p['id']] = p
        for h, v in vers.items(): out[h] = (proj.get(v['project_id']), v.get('version_number'))
    except Exception as e:
        add('Mods', 'ORANGE', 'Modrinth injoignable', "les mods n'ont pas pu être comparés : %s" % e)
    return out

# ---------------- processus ----------------
def liste_pids():
    return [int(p) for p in os.listdir('/proc') if p.isdigit()]
def cmdline(pid):
    d = lire('/proc/%d/cmdline' % pid, True)
    return [a.decode('utf-8', 'replace') for a in d.split(b'\0') if a] if d else []
def comm(pid):
    return (lire('/proc/%d/comm' % pid) or '').strip()
def exe(pid):
    try: return os.readlink('/proc/%d/exe' % pid)
    except Exception: return None
BOOT = 0
for l in (lire('/proc/stat') or '').splitlines():
    if l.startswith('btime '): BOOT = int(l.split()[1])
def debut_process(pid):
    s = lire('/proc/%d/stat' % pid)
    if not s: return None
    try: return BOOT + int(s.rsplit(')', 1)[1].split()[19]) / os.sysconf('SC_CLK_TCK')
    except Exception: return None
def valeur_arg(args, nom):
    for i, a in enumerate(args):
        if a == nom and i + 1 < len(args): return args[i + 1]
        if a.startswith(nom + '='): return a.split('=', 1)[1]
    return None

# =====================================================================
JEUX = []          # (pid, dossier du jeu, heure de lancement)
DOSSIERS = []      # (chemin, jeu?)
LANCEMENT = None
NB_JARS = 0

def scan_systeme():
    etape('Système')
    add('Systeme', 'INFO', 'Date du scan', datetime.datetime.now().strftime('%d/%m/%Y %H:%M:%S'))
    add('Systeme', 'INFO', 'PC / session', '%s / %s' % (socket.gethostname(), UTILISATEUR))
    distro = ''
    for l in (lire('/etc/os-release') or '').splitlines():
        if l.startswith('PRETTY_NAME='): distro = l.split('=', 1)[1].strip('"')
    add('Systeme', 'INFO', 'Linux', '%s (noyau %s)' % (distro or 'inconnu', platform.release()))
    if BOOT:
        if NOW - BOOT < 900: add('Systeme', 'ORANGE', 'PC redémarré il y a moins de 15 min', 'Démarré le %s : un redémarrage efface certaines traces.' % fdate(BOOT))
        else: add('Systeme', 'INFO', 'Démarrage du PC', '%s (il y a %s)' % (fdate(BOOT), fduree(NOW - BOOT)))
    if ROOT: add('Systeme', 'OK', 'Mode root', 'Oui : scan complet.')
    else: add('Systeme', 'INFO', 'Mode root', "NON : relance avec sudo pour lire le journal du noyau et les autres sessions.")
    add('Systeme', 'INFO', "Version de l'outil", 'SnowFall SS Linux v' + VERSION)

def scan_minecraft():
    global LANCEMENT
    etape('Minecraft lancé')
    nb = 0
    for pid in liste_pids():
        args = cmdline(pid)
        if not args or not os.path.basename(args[0]).startswith('java'): continue
        tout = ' '.join(args)
        if not RE_JEU.search(tout): continue
        nb += 1
        ex = exe(pid) or args[0]
        debut = debut_process(pid)
        if debut and (LANCEMENT is None or debut < LANCEMENT): LANCEMENT = debut
        add('Minecraft', 'INFO', 'Minecraft %s (PID %d)' % (valeur_arg(args, '--version') or '?', pid), 'lancé le %s avec %s' % (fdate(debut), ex), ex)
        if sur_usb(ex): add('Minecraft', 'ROUGE', 'Java lancé depuis une clé USB', ex, ex)
        gd = valeur_arg(args, '--gameDir')
        if gd:
            add('Minecraft', 'INFO', 'Dossier du jeu', gd, gd)
            if sur_usb(gd): add('Minecraft', 'ROUGE', 'Dossier du jeu sur une clé USB', gd, gd)
            DOSSIERS.append((os.path.join(gd, 'mods'), True)); DOSSIERS.append((os.path.join(gd, 'resourcepacks'), True))
        JEUX.append((pid, gd, debut))
        scan_injection(pid, args, ex, gd)
    if nb == 0: add('Minecraft', 'ORANGE', 'Aucun Minecraft lancé', 'Demande au joueur de garder son jeu ouvert pendant le scan.')

def scan_injection(pid, args, ex, gd):
    etape('Injection dans le jeu (PID %d)' % pid)
    rien = True
    for a in args:
        if a.startswith('-javaagent:'):
            ch = a[len('-javaagent:'):]
            m = re.match(r'(.*?\.jar)', ch); ch = m.group(1) if m else ch
            if os.path.basename(ch) == 'theseus.jar' and os.path.exists(ch) and os.path.getsize(ch) < 2 << 20:
                add('Injection', 'OK', 'Agent Java du Modrinth App', 'theseus.jar : agent normal du launcher', ch); continue
            rien = False
            niv = 'ROUGE' if (re.search(r'(?i)/(tmp|downloads|téléchargements|desktop|bureau)/', ch) or sur_usb(ch)) else 'ORANGE'
            det = 'Un agent Java peut modifier le jeu au lancement'
            if os.path.exists(ch):
                n2, rs, _ = analyse_jar(ch, os.path.basename(ch))
                if n2 == 'ROUGE': niv = 'ROUGE'
                if rs: det += ' · ' + rs
            else:
                niv = 'ROUGE'; det += " · le fichier n'existe plus (supprimé après le lancement ?)"
            add('Injection', niv, 'Agent Java injecté au lancement : ' + os.path.basename(ch), det, ch)
        elif a.startswith('-agentpath:') or (a.startswith('-agentlib:') and not a.startswith('-agentlib:jdwp')):
            rien = False; add('Injection', 'ROUGE', 'Agent natif chargé dans le jeu', a)
        elif a.startswith('-agentlib:jdwp'):
            rien = False; add('Injection', 'ORANGE', 'Débogueur Java activé (jdwp)', a)
        elif a.startswith('-Xbootclasspath/'):
            rien = False; add('Injection', 'ORANGE', 'Classes ajoutées au démarrage de Java (-Xbootclasspath)', a)
        elif a in ('-noverify', '-Xverify:none'):
            rien = False; add('Injection', 'ORANGE', 'Vérification du code Java désactivée', a)
        elif a.startswith('-Dfabric.addMods='):
            rien = False; extra = a.split('=', 1)[1]
            add('Injection', 'ORANGE', 'Mods chargés depuis un autre dossier (-Dfabric.addMods)', extra)
            for x in re.split(r'[:;]', extra):
                if x: DOSSIERS.append((x, True))
    # variables d'environnement d'injection
    env = lire('/proc/%d/environ' % pid, True)
    if env is None:
        add('Injection', 'INFO', "Environnement du jeu", "Illisible : relance avec sudo.")
    else:
        for v in env.split(b'\0'):
            v = v.decode('utf-8', 'replace')
            if v.startswith('LD_PRELOAD=') and v[11:].strip():
                rien = False; add('Injection', 'ROUGE', 'Bibliothèque forcée dans le jeu (LD_PRELOAD)', v)
            elif v.split('=', 1)[0] in ('JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS') and ('agent' in v or 'bootclasspath' in v):
                rien = False; add('Injection', 'ROUGE', 'Agent Java caché dans une variable d\'environnement', v)
    # debogueur / injecteur attache
    st = lire('/proc/%d/status' % pid) or ''
    m = re.search(r'TracerPid:\s*(\d+)', st)
    if m and m.group(1) != '0':
        rien = False; t = int(m.group(1))
        add('Injection', 'ROUGE', 'Un programme est attaché au jeu (ptrace)', '%s (PID %d) contrôle la mémoire du jeu : débogueur ou injecteur' % (comm(t) or '?', t), exe(t) or '')
    # bibliotheques .so chargees
    javahome = os.path.dirname(os.path.dirname(os.path.realpath(ex))) if ex else ''
    maps = lire('/proc/%d/maps' % pid)
    if maps is None:
        add('Injection', 'INFO', 'Bibliothèques du jeu', 'Illisibles : relance avec sudo.')
    else:
        vues = set(); nb = 0
        for l in maps.splitlines():
            p = l.split(None, 5)
            if len(p) < 6: continue
            ch = p[5].strip()
            if '.so' not in ch or ch in vues: continue
            vues.add(ch); nb += 1
            supprime = ch.endswith('(deleted)')
            c = ch.replace(' (deleted)', '')
            if supprime and not re.search(r'(?i)lwjgl|jna|/tmp/\.?(java|hsperf)', c):
                rien = False; add('Injection', 'ROUGE', 'Bibliothèque injectée puis supprimée : ' + os.path.basename(c), c, c); continue
            if re.match(r'^/(usr|lib|lib64|nix/store|snap|app|opt/java|etc)/', c) or (javahome and c.startswith(javahome)) or RE_SO_NORMAL.search(c):
                continue
            rien = False
            niv = 'ROUGE' if (re.search(r'(?i)/(tmp|downloads|téléchargements|desktop|bureau)/', c) or sur_usb(c)) else 'ORANGE'
            add('Injection', niv, 'Bibliothèque inhabituelle dans le jeu : ' + os.path.basename(c), c, c)
        if rien: add('Injection', 'OK', 'Bibliothèques du jeu', '%d bibliothèques vérifiées, aucune étrangère.' % nb)
    # jars ouverts par le jeu
    try:
        fds = os.listdir('/proc/%d/fd' % pid)
    except Exception:
        fds = []; add('Injection', 'INFO', 'Fichiers ouverts par le jeu', 'Illisibles : relance avec sudo.')
    for fd in fds:
        try: cible = os.readlink('/proc/%d/fd/%s' % (pid, fd))
        except Exception: continue
        if '.jar' not in cible: continue
        if cible.endswith('(deleted)'):
            add('Injection', 'ROUGE', 'Jar chargé par le jeu puis SUPPRIMÉ : ' + os.path.basename(cible.replace(' (deleted)', '')), 'Le fichier a été effacé pendant que le jeu tournait (self-destruct ?) · ' + cible)
        elif sur_usb(cible) or re.search(r'(?i)/(tmp|downloads|téléchargements|desktop|bureau)/', cible):
            n2, rs, _ = analyse_jar(cible, os.path.basename(cible))
            add('Injection', n2 or 'ORANGE', 'Jar ouvert par le jeu hors des dossiers habituels : ' + os.path.basename(cible), (rs + ' · ' if rs else '') + cible, cible)

def scan_mods():
    global NB_JARS
    etape('Mods')
    motifs = ['~/.minecraft/mods', '~/.minecraft/resourcepacks',
              '~/.local/share/ModrinthApp/profiles/*/mods', '~/.local/share/com.modrinth.theseus/profiles/*/mods',
              '~/.local/share/PrismLauncher/instances/*/.minecraft/mods', '~/.local/share/PrismLauncher/instances/*/minecraft/mods',
              '~/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances/*/.minecraft/mods',
              '~/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances/*/minecraft/mods',
              '~/.local/share/multimc/instances/*/.minecraft/mods', '~/.local/share/atlauncher/instances/*/mods',
              '~/.lunarclient/profiles/*/*/mods', '~/.var/app/com.modrinth.ModrinthApp/data/ModrinthApp/profiles/*/mods']
    for mo in motifs:
        for d in glob.glob(mo.replace('~', HOME)):
            if os.path.isdir(d): DOSSIERS.append((d, False))
    vus = set(); jars = []
    for d, jeu in DOSSIERS:
        if not os.path.isdir(d): continue
        rp = os.path.realpath(d)
        if rp in vus: continue
        vus.add(rp)
        tag = ' (jeu lancé)' if jeu else ''
        if os.path.basename(rp) == 'resourcepacks':
            packs = os.listdir(rp)
            add('Mods', 'INFO', 'Packs de textures%s : %d' % (tag, len(packs)), rp, rp)
            for pk in packs:
                if re.search(r'(?i)x-?ray|ore.?(esp|finder)|see.?through', pk): add('Mods', 'ORANGE', 'Pack de textures X-Ray', pk, os.path.join(rp, pk))
            continue
        fich = []
        for racine, sous, fs in os.walk(rp):
            if racine.count(os.sep) - rp.count(os.sep) >= 2: sous[:] = []
            for f in fs: fich.append(os.path.join(racine, f))
        lj = [f for f in fich if f.endswith('.jar')]
        add('Mods', 'INFO', 'Dossier mods%s : %d jar(s)' % (tag, len(lj)), rp, rp)
        for f in fich:
            if re.search(r'(?i)\.(exe|dll|so|zip|rar|7z|class|sh|py)$', f): add('Mods', 'ORANGE', 'Fichier bizarre dans un dossier mods', os.path.basename(f), f)
        for f in lj: jars.append((f, jeu))
    NB_JARS = len(jars)
    if not jars and not vus: add('Mods', 'INFO', 'Aucun dossier mods trouvé', "Launcher non reconnu : demande au joueur où sont ses mods.")
    print('  ' + C['G'] + 'Calcul des empreintes et vérification Modrinth (%d jars)...' % len(jars) + C['R'])
    sha = {}
    for f, _ in jars:
        try:
            with open(f, 'rb') as fh: sha[f] = hashlib.sha1(fh.read()).hexdigest()
        except Exception: pass
    infos = modrinth(sorted(set(sha.values())))
    for f, jeu in sorted(jars):
        nom = os.path.basename(f)
        try: mt = os.path.getmtime(f)
        except Exception: mt = 0
        recent = (' · modifié le ' + fdate(mt)) if mt >= DEPUIS else ''
        if jeu and LANCEMENT and mt > LANCEMENT: add('Mods', 'ORANGE', 'Jar modifié APRÈS le lancement du jeu : ' + nom, 'modifié le ' + fdate(mt), f)
        info = infos.get(sha.get(f))
        proj = info[0] if info else None
        if proj and proj.get('downloads', 0) >= SEUIL_MODRINTH:
            add('Mods', 'OK', nom, '%s %s · %s téléchargements sur Modrinth%s' % (proj.get('title'), info[1], format(proj.get('downloads', 0), ',').replace(',', ' '), recent), f)
            if RE_INTERDIT.search(proj.get('slug', '')): add('Mods', 'ORANGE', 'Mod interdit sur la plupart des serveurs : ' + proj.get('title', ''), nom, f)
            continue
        niv, rs, mid = analyse_jar(f, nom)
        src = "pas sur Modrinth (peut venir de CurseForge ou d'ailleurs)"
        if proj: src = 'sur Modrinth mais peu téléchargé : %s (%d)' % (proj.get('title'), proj.get('downloads', 0))
        titre = nom + ('  [id: %s]' % mid if mid else '')
        if niv: add('Mods', niv, titre, rs + ' · ' + src + recent, f)
        else: add('Mods', 'INFO', titre, src + ', rien de suspect dedans' + recent, f)

def scan_log():
    for pid, gd, _ in JEUX:
        if not gd: continue
        t = lire(os.path.join(gd, 'logs', 'latest.log'))
        if not t: continue
        charges = []; dans = False
        for l in t.splitlines():
            if re.search(r'Loading \d+ mods:', l): dans = True; charges = []; continue
            if dans:
                m = re.match(r'^\t- ([A-Za-z0-9_\-\.]+) ', l)
                if m: charges.append(m.group(1)); continue
                if l.startswith('\t'): continue
                dans = False
        if not charges: continue
        presents = set()
        for f in glob.glob(os.path.join(gd, 'mods', '*.jar')):
            i = mod_id_rapide(f)
            if i: presents.add(i.lower())
        manquants = [c for c in charges if not re.match(r'^(minecraft|java|fabricloader|quilt_loader|mixinextras)$', c) and c.lower() not in presents]
        if manquants: add('Injection', 'ROUGE', 'Mods chargés par le jeu mais supprimés depuis : ' + ', '.join(manquants), "Le log du jeu les montre au lancement, mais leur jar n'est plus là")
        else: add('Injection', 'OK', 'Mods du log du jeu', '%d mods chargés au lancement, tous encore présents.' % len(charges))
        m = re.search(r'(?i)\b(meteor ?client|wurst|aristois|liquidbounce|rusherhack|thunderhack|bleachhack|boze|doomsday|prestige ?client|vape|phobos|konas|earthhack|self.?destruct)\b', t)
        if m: add('Injection', 'ORANGE', 'Nom de client de triche dans le log du jeu : ' + m.group(0), os.path.join(gd, 'logs', 'latest.log'))

def scan_programmes():
    etape('Programmes')
    rien = True
    for pid in liste_pids():
        c = comm(pid); a = ' '.join(cmdline(pid)[:3])
        if not c: continue
        if RE_PROG.search(c) or RE_PROG.search(os.path.basename(a.split(' ')[0]) if a else ''):
            rien = False; add('Programmes', 'ORANGE', 'Programme suspect ouvert : ' + c, 'PID %d · %s' % (pid, a), exe(pid) or '')
        elif re.match(r'(?i)^(piper|solaar|openrazer|polychromatic|ratbag|ckb-next|input-remapper)', c):
            add('Programmes', 'INFO', 'Logiciel souris/clavier : ' + c, "Peut faire des macros : demande au joueur de l'ouvrir.")
    if rien: add('Programmes', 'OK', 'Programmes ouverts', 'Aucun autoclicker / injecteur connu en cours.')
    # historique du terminal : uniquement les lignes suspectes
    trouve = 0
    for h in ('.bash_history', '.zsh_history', '.local/share/fish/fish_history'):
        t = lire(os.path.join(HOME, h))
        if not t: continue
        for l in t.splitlines()[-3000:]:
            l2 = l.split(';', 1)[-1] if h == '.zsh_history' else l
            if re.search(r'(?i)(xdotool\s+click|ydotool\s+click|frida|gdb\s+-p|jattach|scanmem|ptrace)', l2) or (re.search(r'(?i)java\s', l2) and RE_NOM.search(l2)):
                trouve += 1
                if trouve <= 15: add('Programmes', 'ORANGE', 'Commande suspecte dans l\'historique du terminal', l2.strip()[:200])
    if trouve == 0: add('Programmes', 'OK', 'Historique du terminal', 'Aucune commande suspecte.')

def type_usb(classes, protos, nom):
    n = (nom or '').lower()
    souris = '02' in protos; clavier = '01' in protos
    if souris and clavier:
        if re.search(r'receiver|dongle|wireless|unifying|lightspeed|2\.4', n): return 'Récepteur sans fil (souris/clavier)'
        if re.search(r'keyboard|kbd', n): return 'Clavier'
        if re.search(r'mouse', n): return 'Souris'
        return 'Souris / clavier'
    if souris: return 'Souris'
    if clavier: return 'Clavier'
    if '08' in classes: return 'Clé / disque USB'
    if '01' in classes: return 'Audio'
    if '0e' in classes: return 'Webcam'
    if 'e0' in classes: return 'Adaptateur Bluetooth / sans fil'
    if '03' in classes:
        if re.search(r'controller|gamepad|dualsense|dualshock|xbox', n): return 'Manette'
        return 'Périphérique HID'
    if '02' in classes or '0a' in classes: return 'Port série'
    return 'Autre'

def scan_usb():
    etape('USB')
    nb = 0
    for d in sorted(glob.glob('/sys/bus/usb/devices/*')):
        vid = (lire(d + '/idVendor') or '').strip()
        if not vid: continue
        if (lire(d + '/bDeviceClass') or '').strip() == '09': continue
        pid_ = (lire(d + '/idProduct') or '').strip()
        nom = ((lire(d + '/manufacturer') or '').strip() + ' ' + (lire(d + '/product') or '').strip()).strip() or 'appareil sans nom'
        classes = set(); protos = set()
        for itf in glob.glob(d + '/*:*'):
            c = (lire(itf + '/bInterfaceClass') or '').strip()
            if c: classes.add(c)
            if c == '03': protos.add((lire(itf + '/bInterfaceProtocol') or '').strip())
        t = type_usb(classes, protos, nom)
        marque = MICRO.get(vid) or MARQUES.get(vid)
        titre = '%s : %s' % (t, nom) + (' (%s)' % marque if marque else '')
        det = 'branché maintenant · VID:PID %s:%s · port %s' % (vid, pid_, os.path.basename(d))
        niv = 'INFO'
        if vid in MICRO:
            niv = 'ROUGE' if ('03' in classes) else 'ORANGE'
            det = ('Carte programmable qui se fait passer pour une souris/un clavier : autoclicker matériel possible · ' if niv == 'ROUGE' else 'Carte programmable (Arduino ou similaire) : à faire montrer · ') + det
        elif vid == '09da' and 'Souris' in t:
            niv = 'ORANGE'; det = 'Souris Bloody : macros intégrées possibles · ' + det
        elif ('Souris' in t or 'Récepteur' in t) and vid in ('046d', '1532', '1038', '1b1c', '1e7d', '2516', '3434', '342d'):
            det = "Souris de marque : macros possibles via son logiciel · " + det
        nb += 1; add('Usb', niv, titre, det)
    if nb == 0: add('Usb', 'INFO', 'Appareils USB', 'Aucun appareil USB lisible.')
    # cles montees : contenu fouille
    if not MONTAGES: add('Usb', 'OK', 'Clés USB montées', 'Aucune clé USB montée en ce moment.')
    for mp, dev, fs in MONTAGES:
        nf = 0; nj = 0; ne = 0; sus = False; avant = len(RES)
        for racine, sous, fichiers in os.walk(mp):
            if racine.count(os.sep) - mp.count(os.sep) >= 5: sous[:] = []
            for s in sous:
                if re.match(r'(?i)^(\.minecraft|mods|versions|\.lunarclient)$', s): sus = True; add('Usb', 'ORANGE', 'Dossier Minecraft sur la clé : ' + s, os.path.join(racine, s))
            for f in fichiers:
                nf += 1
                if nf > 20000: break
                p = os.path.join(racine, f)
                if f.lower().endswith('.jar'):
                    nj += 1; sus = True
                    if nj <= 60:
                        n2, rs, _ = analyse_jar(p, f)
                        add('Usb', n2 or 'ORANGE', 'Jar sur la clé : ' + f, rs or "rien de suspect dedans, mais un jar sur une clé mérite d'être regardé", p)
                elif re.search(r'(?i)\.(exe|dll|so|sh|appimage|bat|py)$', f):
                    if RE_NOM.search(f) or RE_PROG.search(f): sus = True; add('Usb', 'ORANGE', 'Programme suspect sur la clé : ' + f, p, p)
                    elif ne < 30: ne += 1; add('Usb', 'INFO', 'Programme sur la clé : ' + f, p, p)
        RES.insert(avant, ('Usb', 'ORANGE' if sus else 'INFO', 'Clé USB montée : ' + mp, '%s (%s) · %d fichier(s), %d jar(s)' % (dev, fs, nf, nj), mp))
    # journal du noyau : branchements / debranchements
    log = ''
    for cmd in (['journalctl', '-k', '--since', '-%dh' % HEURES, '-o', 'short-unix', '--no-pager', '-q'], ['dmesg', '--time-format', 'iso']):
        try:
            log = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30).stdout.decode('utf-8', 'replace')
            if log.strip(): break
        except Exception:
            pass
    if not log.strip():
        add('Usb', 'INFO', 'Journal des branchements USB', 'Illisible : relance avec sudo.')
    ports = {}; retraits = []
    for l in log.splitlines():
        m = re.match(r'^\s*\[?([0-9.]+)\]?\s', l)
        ts = None
        if m:
            try: ts = float(m.group(1))
            except Exception: ts = None
        if ts is None:
            m2 = re.match(r'^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)', l)
            if m2:
                try: ts = time.mktime(time.strptime(m2.group(1), '%Y-%m-%dT%H:%M:%S'))
                except Exception: ts = None
        mp_ = re.search(r'usb (\d+-[\d.]+): (.*)$', l)
        if not mp_ or ts is None: continue
        port, msg = mp_.group(1), mp_.group(2)
        m3 = re.search(r'idVendor=([0-9a-f]{4}), idProduct=([0-9a-f]{4})', msg)
        if m3: ports[port] = {'vid': m3.group(1), 'pid': m3.group(2), 'nom': '', 'arrivee': ts}; continue
        m3 = re.match(r'(Product|Manufacturer): (.*)', msg)
        if m3 and port in ports: ports[port]['nom'] = (ports[port]['nom'] + ' ' + m3.group(2)).strip(); continue
        if 'USB disconnect' in msg:
            i = ports.get(port, {})
            retraits.append((ts, port, i.get('vid', '?'), i.get('pid', '?'), i.get('nom', '') or 'appareil'))
    vus = set(); nr = 0
    for ts, port, vid, pid_, nom in sorted(retraits, reverse=True):
        if ts < DEPUIS or (vid, pid_, nom) in vus: continue
        vus.add((vid, pid_, nom)); nr += 1
        marque = MICRO.get(vid) or MARQUES.get(vid) or ''
        quand = '%s (il y a %s)' % (fdate(ts), fduree(NOW - ts))
        det = 'VID:PID %s:%s · port %s · retiré le %s' % (vid, pid_, port, quand)
        if LANCEMENT and ts > LANCEMENT: det += ' · retiré PENDANT que Minecraft tournait'
        if NOW - ts <= MIN_AVANT_SCAN * 60:
            add('Usb', 'ROUGE', 'Débranché %d min AVANT le scan : %s%s' % ((NOW - ts) // 60, nom, ' (%s)' % marque if marque else ''), 'Demande au joueur de le rebrancher et de le montrer · ' + det)
        elif vid in MICRO:
            add('Usb', 'ROUGE', 'Carte programmable débranchée récemment : ' + nom, det)
        else:
            add('Usb', 'INFO', 'Débranché récemment : %s%s' % (nom, ' (%s)' % marque if marque else ''), det)
    if nr == 0 and log.strip(): add('Usb', 'OK', 'Journal des branchements USB', 'Aucun appareil débranché depuis %d h.' % HEURES)
    # fichiers ouverts depuis une cle (GTK recently-used)
    t = lire(os.path.join(HOME, '.local/share/recently-used.xbel')) or ''
    no = 0
    for m in re.finditer(r'href="file://([^"]+)"[^>]*?modified="([^"]+)"', t):
        p = urllib.parse.unquote(m.group(1))
        if not externe(p): continue
        try: ts = time.mktime(time.strptime(m.group(2)[:19], '%Y-%m-%dT%H:%M:%S'))
        except Exception: ts = 0
        if ts and ts < NOW - 30 * 86400: continue
        no += 1
        niv = 'ROUGE' if (re.search(r'(?i)\.(jar|sh|appimage|so|exe)$', p) or RE_NOM.search(p) or RE_PROG.search(p)) else ('ORANGE' if ts >= DEPUIS else 'INFO')
        add('Usb', niv, 'Ouvert depuis une clé USB : ' + os.path.basename(p), 'le %s · %s' % (fdate(ts), p), p)
    if no == 0: add('Usb', 'OK', 'Activité depuis une clé USB', 'Aucun fichier ouvert depuis une clé.')

def scan_fichiers():
    etape('Fichiers récents')
    rien = True
    lieux = [os.path.join(HOME, x) for x in ('Downloads', 'Téléchargements', 'Desktop', 'Bureau', 'Documents')] + ['/tmp']
    for l in lieux:
        if not os.path.isdir(l): continue
        n = 0
        for racine, sous, fs in os.walk(l):
            if racine.count(os.sep) - l.count(os.sep) >= 2: sous[:] = []
            for f in fs:
                if not re.search(r'(?i)\.(jar|sh|appimage|so|exe)$', f): continue
                p = os.path.join(racine, f)
                if re.search(r'(?i)lwjgl|jna|hsperf|/\.minecraft/|modrinth|prism', p): continue
                try: mt = os.path.getmtime(p)
                except Exception: continue
                if mt < DEPUIS: continue
                n += 1
                if n > 25: break
                rien = False
                det = '%s · %s' % (fdate(mt), p)
                if RE_NOM.search(f) or RE_PROG.search(f): add('Fichiers', 'ORANGE', 'Nom suspect : ' + f, det, p)
                else: add('Fichiers', 'INFO', f, det, p)
    if rien: add('Fichiers', 'OK', 'Fichiers récents', 'Aucun .jar / programme récent (moins de %d h).' % HEURES)
    etape('Corbeille')
    rien = True
    for info in glob.glob(os.path.join(HOME, '.local/share/Trash/info/*.trashinfo')):
        t = lire(info) or ''
        m1 = re.search(r'Path=(.*)', t); m2 = re.search(r'DeletionDate=(.*)', t)
        if not m1: continue
        p = urllib.parse.unquote(m1.group(1).strip())
        if not re.search(r'(?i)\.(jar|so|sh|appimage|exe)$', p): continue
        try: ts = time.mktime(time.strptime(m2.group(1).strip()[:19], '%Y-%m-%dT%H:%M:%S'))
        except Exception: ts = 0
        if ts and ts < DEPUIS: continue
        rien = False
        niv = 'ORANGE' if (re.search(r'(?i)/mods/', p) or RE_NOM.search(p) or RE_PROG.search(p)) else 'INFO'
        add('Corbeille', niv, 'Supprimé récemment : ' + os.path.basename(p), 'le %s · venait de %s' % (fdate(ts), p))
    if rien: add('Corbeille', 'OK', 'Corbeille', 'Aucun jar / programme supprimé depuis %d h.' % HEURES)

def bilan_usb():
    etape('Ce que la clé USB a fait au jeu')
    n = 0
    ext = lambda s: bool(re.search(r'/(media|run/media|mnt)/', s or ''))
    for r in list(RES):
        if r[0] in ('Injection', 'Minecraft') and r[1] in ('ROUGE', 'ORANGE') and (ext(r[3]) or ext(r[4])):
            n += 1; add('Usb', 'ROUGE', 'La clé USB agit sur le jeu : ' + r[2], r[3], r[4])
    for pid in liste_pids():
        e = exe(pid) or ''
        if ext(e):
            n += 1; add('Usb', 'ROUGE', 'Programme de la clé USB en cours : ' + (comm(pid) or '?'), 'PID %d · %s' % (pid, e), e)
    for pid, gd, _ in JEUX:
        m = re.search(r'PPid:\s*(\d+)', lire('/proc/%d/status' % pid) or '')
        if m:
            pe = exe(int(m.group(1))) or ''
            if ext(pe):
                n += 1; add('Usb', 'ROUGE', 'Minecraft a été lancé par un programme de la clé USB', pe, pe)
    if n == 0: add('Usb', 'OK', 'Ce que la clé USB a fait au jeu', 'Rien chargé ni injecté dans Minecraft depuis une clé USB.')

# =====================================================================
print(C['T'] + C['B'] + '\n  ❄  SnowFall SS (Linux) v' + VERSION + C['R'] + C['G'] + '  ·  outil de screenshare du staff  ·  lecture seule' + C['R'])
for f in (scan_systeme, scan_minecraft, scan_mods, scan_log, scan_programmes, scan_usb, scan_fichiers, bilan_usb):
    try:
        f()
    except Exception as e:
        add('Systeme', 'ORANGE', 'Erreur pendant le scan (%s)' % f.__name__, str(e))

rouges = [r for r in RES if r[1] == 'ROUGE']; oranges = [r for r in RES if r[1] == 'ORANGE']
if rouges: verdict = ('SUSPECT', '%d alerte(s) rouge et %d orange : triche probable' % (len(rouges), len(oranges)), 'ROUGE')
elif oranges: verdict = ('À VÉRIFIER', '%d point(s) orange à regarder avec le joueur' % len(oranges), 'ORANGE')
else: verdict = ('RIEN DE SUSPECT', 'Un scan propre ne prouve pas à 100 % que le joueur est clean.', 'OK')
noms = dict(CATS)
etape('Résumé')
for r in rouges + oranges:
    print('  {}[{:<6}]{} {} › {}  {}{}{}'.format(C[r[1]], r[1], C['R'], noms.get(r[0], r[0]), r[2], C['G'], r[3], C['R']))
print('\n  ' + C[verdict[2]] + C['B'] + 'VERDICT : ' + verdict[0] + C['R'] + '  ·  ' + verdict[1])

rapport = ['SnowFall SS (Linux) v%s - rapport de screenshare' % VERSION,
           'Date : %s  ·  PC : %s  ·  session : %s' % (datetime.datetime.now().strftime('%d/%m/%Y %H:%M:%S'), socket.gethostname(), UTILISATEUR),
           'VERDICT : %s  ·  %s' % (verdict[0], verdict[1])]
for cle, nom in CATS:
    lignes = [r for r in RES if r[0] == cle]
    if not lignes: continue
    rapport += ['', '=== %s ===' % nom]
    for r in lignes:
        rapport.append('[%s] %s : %s' % (r[1], r[2], r[3]))
        if r[4] and r[4] not in r[3]: rapport.append('        -> ' + r[4])
fichier = os.path.join(HOME, 'SnowSS_%s.txt' % datetime.datetime.now().strftime('%Y-%m-%d_%H-%M'))
try:
    with open(fichier, 'w', encoding='utf-8') as fh: fh.write('\n'.join(rapport) + '\n')
    if ROOT and os.environ.get('SUDO_USER'):
        try: p = pwd.getpwnam(UTILISATEUR); os.chown(fichier, p.pw_uid, p.pw_gid)
        except Exception: pass
    print('  ' + C['T'] + 'Rapport enregistré : ' + fichier + C['R'] + '\n')
except Exception as e:
    print('  Rapport non enregistré : %s\n' % e)
SNOWSS_FIN_PYTHON
