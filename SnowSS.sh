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
#    - rapport .txt + INTERFACE (tableau de bord) ouverte a la fin du scan
#      dans une fenetre du navigateur, fichier .html dans le dossier perso
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
import os, sys, re, io, json, glob, time, zipfile, hashlib, datetime, subprocess, pwd, platform, socket, shutil
import urllib.request, urllib.parse

VERSION = '1.4'
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
        ('Mods', 'Mods'), ('Programmes', 'Programmes'), ('Macros', 'Macros / autoclick'), ('Usb', 'USB'),
        ('Fichiers', 'Fichiers récents'), ('Corbeille', 'Corbeille')]

def add(cat, niv, titre, detail='', chemin='', groupe=''):
    RES.append((cat, niv, titre, detail, chemin, groupe))
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
RE_CHARGEUR = re.compile(r'(?i)(^|/)(PayloadLoader|PayloadSignature|PayloadUpdater|PayloadCache|PayloadDownloader|MemoryFs|MemoryFileSystem|MemoryClassLoader|InMemoryClassLoader|InMemoryJar\w*|RemoteLoader|RemoteClassLoader|Stage2\w*)(\$[^/]*)?\.class$')
RE_DESC_CHARGEUR = re.compile(r'(?i)(payload|fetch(es)? and loads?|downloads? (and loads? )?(the )?client|loads? the client|client itself lives|inject(s|ed|or)?\b)')
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
            mc = RE_CHARGEUR.search(n)
            if mc and mc.group(2) not in r['charg']: r['charg'].append(mc.group(2))
            if n.startswith('imgui/'): r['imgui'] = True
            continue
        if prof == 0:
            try:
                if n in ('fabric.mod.json', 'quilt.mod.json'):
                    t = z.read(n).decode('utf-8', 'replace')
                    m = re.search(r'"id"\s*:\s*"([^"]+)"', t); r['id'] = r['id'] or (m.group(1) if m else None)
                    m = re.search(r'"name"\s*:\s*"([^"]+)"', t); r['nom'] = r['nom'] or (m.group(1) if m else None)
                    m = re.search(r'"description"\s*:\s*"([^"]*)"', t)
                    if m and RE_DESC_CHARGEUR.search(m.group(1)): r['desc'] = m.group(1)
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
        if n.endswith('.jar') and 'imgui-java' in n.lower(): r['imgui'] = True
        if n.endswith('.jar') and prof < 2:
            try: lire_zip(zipfile.ZipFile(io.BytesIO(z.read(n))), r, prof + 1)
            except Exception: pass

def analyse_jar(chemin, nom):
    r = {'id': None, 'nom': None, 'agent': False, 'classes': 0, 'obf': 0, 'uni': 0, 'struct': 0, 'paq': [], 'mod': [], 'err': None, 'charg': [], 'imgui': False, 'desc': None}
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
    if r['charg'] or r['desc']:
        pr = []
        if r['charg']: pr.append('classes ' + ', '.join(r['charg']))
        if r['desc']: pr.append('sa description : « ' + (r['desc'][:120] + '…' if len(r['desc']) > 120 else r['desc']) + ' »')
        if r['imgui']: pr.append('contient ImGui')
        if (r['charg'] and r['desc']) or r['imgui'] or (r['classes'] >= 30 and r['obf'] / float(r['classes']) >= 0.4): niv = 'ROUGE'
        else: monte('ORANGE')
        rs.append("CHARGEUR DE CLIENT CACHÉ : le vrai code est téléchargé au lancement et chargé en mémoire, il n'est pas dans ce jar (" + ' ; '.join(pr) + ')')
    elif r['imgui']: monte('ORANGE'); rs.append('contient ImGui : menu en surimpression utilisé par beaucoup de clients de triche')
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
        info_lancement(pid, args, gd)
        scan_injection(pid, args, ex, gd)
    if nb == 0: add('Minecraft', 'ORANGE', 'Aucun Minecraft lancé', 'Demande au joueur de garder son jeu ouvert pendant le scan.')
    scan_launchers()

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
    motifs = ['~/.minecraft/mods', '~/.minecraft/resourcepacks', '~/.minecraft/labymod-neo/addons',
              '~/.local/share/ModrinthApp/profiles/*/mods', '~/.local/share/com.modrinth.theseus/profiles/*/mods',
              '~/.local/share/ModrinthApp/profiles/*/resourcepacks',
              '~/.local/share/PrismLauncher/instances/*/.minecraft/mods', '~/.local/share/PrismLauncher/instances/*/minecraft/mods',
              '~/.local/share/PrismLauncher/instances/*/.minecraft/resourcepacks',
              '~/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances/*/.minecraft/mods',
              '~/.var/app/org.prismlauncher.PrismLauncher/data/PrismLauncher/instances/*/minecraft/mods',
              '~/.local/share/PolyMC/instances/*/.minecraft/mods', '~/.local/share/multimc/instances/*/.minecraft/mods',
              '~/.local/share/atlauncher/instances/*/mods', '~/.local/share/gdlauncher_carbon/data/instances/*/instance/mods',
              '~/.technic/modpacks/*/mods', '~/.tlauncher/legacy/Minecraft/game/mods', '~/.feather/user-mods/*',
              '~/.lunarclient/profiles/*/*/mods', '~/.var/app/com.modrinth.ModrinthApp/data/ModrinthApp/profiles/*/mods']
    for mo in motifs:
        for d in glob.glob(mo.replace('~', HOME)):
            if os.path.isdir(d): DOSSIERS.append((d, False))
    vus = set(); dossiers = []
    for d, jeu in DOSSIERS:
        if not os.path.isdir(d): continue
        rp = os.path.realpath(d)
        if rp in vus:
            if jeu:
                for x in dossiers:
                    if x['chemin'] == rp: x['jeu'] = True
            continue
        vus.add(rp)
        l = launcher_chemin(rp)
        dossiers.append({'chemin': rp, 'jeu': jeu, 'packs': os.path.basename(rp) == 'resourcepacks', 'launcher': l[0], 'etiquette': fmt_launcher(l)})
    if not dossiers: add('Mods', 'INFO', 'Aucun dossier mods trouvé', "Launcher non reconnu : demande au joueur où sont ses mods.")
    # dossier du jeu lance d'abord, puis tri par launcher et instance
    dossiers.sort(key=lambda x: (not x['jeu'], x['launcher'], x['etiquette'], x['packs']))
    jars = []; par_launcher = {}
    for i, d in enumerate(dossiers):
        tag = '  (JEU LANCÉ)' if d['jeu'] else ''
        rp = d['chemin']
        if d['packs']:
            packs = os.listdir(rp)
            d['entete'] = '%s · packs de textures : %d%s' % (d['etiquette'], len(packs), tag)
            d['alertes'] = [('Pack de textures X-Ray', pk, os.path.join(rp, pk)) for pk in packs if re.search(r'(?i)x-?ray|ore.?(esp|finder)|see.?through', pk)]
            continue
        fich = []
        for racine, sous, fs in os.walk(rp):
            if racine.count(os.sep) - rp.count(os.sep) >= 2: sous[:] = []
            for f in fs: fich.append(os.path.join(racine, f))
        lj = [f for f in fich if f.endswith('.jar')]
        par_launcher[d['launcher']] = par_launcher.get(d['launcher'], 0) + len(lj)
        d['entete'] = '%s : %d mod(s)%s' % (d['etiquette'], len(lj), tag)
        d['alertes'] = [('Fichier bizarre dans un dossier mods', os.path.basename(f), f) for f in fich if re.search(r'(?i)\.(exe|dll|so|zip|rar|7z|class|sh|py)$', f)]
        for f in lj: jars.append((i, os.path.basename(f), f, d))
    NB_JARS = len(jars)
    if par_launcher: add('Mods', 'INFO', 'Mods par launcher', ' · '.join('%s : %d' % kv for kv in par_launcher.items()))
    suivant = [0]
    def entetes_jusqua(n):
        while suivant[0] < min(n, len(dossiers)):
            d = dossiers[suivant[0]]; suivant[0] += 1
            add('Mods', 'INFO', '▸ ' + d['entete'], d['chemin'], d['chemin'], d['launcher'])
            for t, nom, ch in d['alertes']: add('Mods', 'ORANGE', t, '[%s] %s' % (d['etiquette'], nom), ch, d['launcher'])
    print('  ' + C['G'] + 'Calcul des empreintes et vérification Modrinth (%d jars)...' % len(jars) + C['R'])
    sha = {}
    for _, _, f, _ in jars:
        try:
            with open(f, 'rb') as fh: sha[f] = hashlib.sha1(fh.read()).hexdigest()
        except Exception: pass
    infos = modrinth(sorted(set(sha.values())))
    for i, nom, f, d in sorted(jars, key=lambda x: (x[0], x[1].lower())):
        entetes_jusqua(i + 1)
        jeu = d['jeu']
        try: mt = os.path.getmtime(f)
        except Exception: mt = 0
        recent = ((' · modifié le ' + fdate(mt)) if mt >= DEPUIS else '') + ' · [%s]' % d['etiquette']
        if jeu and LANCEMENT and mt > LANCEMENT: add('Mods', 'ORANGE', 'Jar modifié APRÈS le lancement du jeu : ' + nom, 'modifié le ' + fdate(mt), f, d['launcher'])
        info = infos.get(sha.get(f))
        proj = info[0] if info else None
        if proj and proj.get('downloads', 0) >= SEUIL_MODRINTH:
            add('Mods', 'OK', nom, '%s %s · %s téléchargements sur Modrinth%s' % (proj.get('title'), info[1], format(proj.get('downloads', 0), ',').replace(',', ' '), recent), f, d['launcher'])
            if RE_INTERDIT.search(proj.get('slug', '')): add('Mods', 'ORANGE', 'Mod interdit sur la plupart des serveurs : ' + proj.get('title', ''), nom, f, d['launcher'])
            continue
        niv, rs, mid = analyse_jar(f, nom)
        src = "pas sur Modrinth (peut venir de CurseForge ou d'ailleurs)"
        if proj: src = 'sur Modrinth mais peu téléchargé : %s (%d)' % (proj.get('title'), proj.get('downloads', 0))
        titre = nom + ('  [id: %s]' % mid if mid else '')
        if niv: add('Mods', niv, titre, rs + ' · ' + src + recent, f, d['launcher'])
        else: add('Mods', 'INFO', titre, src + ', rien de suspect dedans' + recent, f, d['launcher'])
    entetes_jusqua(len(dossiers))

# ---------------- launchers et clients ----------------
LAUNCHERS_PROC = [(r'(?i)^minecraft-launcher|minecraft launcher', 'Launcher officiel Minecraft'), (r'(?i)lunar', 'Lunar Client'),
                  (r'(?i)feather', 'Feather Client'), (r'(?i)badlion', 'Badlion Client'), (r'(?i)modrinth|theseus', 'Modrinth App'),
                  (r'(?i)prismlauncher', 'Prism Launcher'), (r'(?i)polymc', 'PolyMC'), (r'(?i)multimc', 'MultiMC'),
                  (r'(?i)atlauncher', 'ATLauncher'), (r'(?i)gdlauncher', 'GDLauncher'), (r'(?i)tlauncher', 'TLauncher (launcher cracké)'),
                  (r'(?i)sklauncher', 'SKLauncher (launcher cracké)'), (r'(?i)labymod', 'LabyMod'), (r'(?i)technic', 'Technic Launcher'),
                  (r'(?i)hmcl', 'HMCL'), (r'(?i)portablemc', 'PortableMC'), (r'(?i)legacy.?launcher', 'Legacy Launcher (launcher cracké)')]

def launcher_chemin(p):
    c = (p or '').rstrip('/') + '/'
    regles = [(r'/(?:ModrinthApp|com\.modrinth\.theseus)/profiles/([^/]+)/', 'Modrinth App'), (r'/PrismLauncher/instances/([^/]+)/', 'Prism Launcher'),
              (r'/PolyMC/instances/([^/]+)/', 'PolyMC'), (r'/multimc/instances/([^/]+)/', 'MultiMC'), (r'/atlauncher/instances/([^/]+)/', 'ATLauncher'),
              (r'/gdlauncher[^/]*/(?:data/)?instances/([^/]+)/', 'GDLauncher'), (r'/\.technic/modpacks/([^/]+)/', 'Technic Launcher'),
              (r'/\.lunarclient/profiles/([^/]+/[^/]+)/', 'Lunar Client'), (r'/\.lunarclient/()', 'Lunar Client'),
              (r'/\.feather/user-mods/([^/]+)/', 'Feather Client'), (r'/\.feather/()', 'Feather Client'),
              (r'/\.tlauncher/()', 'TLauncher (launcher cracké)'), (r'/labymod-neo/()', 'LabyMod'), (r'/\.minecraft/()', 'Launcher officiel / .minecraft')]
    for rg, nom in regles:
        m = re.search('(?i)' + rg, c)
        if m: return (nom, m.group(1).replace('/', ' / '))
    return ('Autre dossier', '')

def fmt_launcher(l):
    return '%s · %s' % l if l[1] else l[0]

def client_jeu(cmd):
    c = []
    if re.search(r'(?i)com\.moonsworth|/\.lunarclient/', cmd): c.append('Lunar Client')
    if re.search(r'(?i)/\.feather/|net\.digitalingot', cmd): c.append('Feather Client')
    if re.search(r'(?i)net\.badlion', cmd): c.append('Badlion Client')
    if re.search(r'(?i)net\.labymod|labymod', cmd): c.append('LabyMod')
    m = re.search(r'(?i)--fml\.neoForgeVersion\s+(\S+)', cmd); m2 = re.search(r'(?i)--fml\.forgeVersion\s+(\S+)', cmd)
    if m: c.append('NeoForge ' + m.group(1))
    elif re.search(r'(?i)net\.neoforged', cmd): c.append('NeoForge')
    elif m2: c.append('Forge ' + m2.group(1))
    elif re.search(r'(?i)cpw\.mods|net\.minecraftforge|FMLTweaker', cmd): c.append('Forge')
    if re.search(r'(?i)org\.quiltmc\.loader', cmd):
        m = re.search(r'(?i)quilt-loader[-/](\d[\w.+-]*?)(\.jar|/)', cmd); c.append('Quilt' + (' ' + m.group(1) if m else ''))
    elif re.search(r'(?i)net\.fabricmc\.loader', cmd):
        m = re.search(r'(?i)fabric-loader[-/](\d[\w.+-]*?)(\.jar|/)', cmd); c.append('Fabric' + (' ' + m.group(1) if m else ''))
    if re.search(r'(?i)optifine', cmd): c.append('OptiFine')
    return ' + '.join(c) if c else 'Vanilla (sans chargeur de mods)'

def ppid(pid):
    m = re.search(r'PPid:\s*(\d+)', lire('/proc/%d/status' % pid) or '')
    return int(m.group(1)) if m else 0

def info_lancement(pid, args, gd):
    tout = ' '.join(args)
    add('Minecraft', 'INFO', 'Client : ' + client_jeu(tout), 'PID %d' % pid)
    cur = pid; chaine = []
    for _ in range(5):
        p = ppid(cur)
        if p <= 1: break
        chaine.append(p); cur = p
    launcher = None
    for p in chaine:
        a = cmdline(p); c = comm(p); t = c + ' ' + ' '.join(a)
        if a and os.path.basename(a[0]).startswith('java') and RE_JEU.search(t) and '-jar' not in a: continue
        for rg, nom in LAUNCHERS_PROC:
            if re.search(rg, t): launcher = (nom, p, exe(p) or (a[0] if a else c)); break
        if launcher: break
    direct = chaine[0] if chaine else None
    if launcher:
        add('Minecraft', 'INFO', 'Lancé avec : ' + launcher[0], '%s (PID %d) · %s' % (comm(launcher[1]), launcher[1], launcher[2]), launcher[2])
    elif direct and re.match(r'(?i)^(ba|z|da|fi)?sh$|^(konsole|gnome-terminal.*|kitty|alacritty|xterm|foot|wezterm.*|tilix|terminator|xfce4-terminal|tmux.*|screen)$', comm(direct)):
        add('Minecraft', 'ORANGE', 'Minecraft lancé à la main (%s)' % comm(direct), "Pas lancé par un launcher : la commande Java a été tapée à la main (méthode utilisée pour charger des clients modifiés). Demande au joueur comment il lance son jeu.", exe(direct) or '')
    elif direct and not re.match(r'(?i)^(systemd|init|bwrap|flatpak.*|snap.*)$', comm(direct)):
        e = exe(direct) or ''
        niv = 'ROUGE' if (RE_NOM.search(comm(direct) + ' ' + e) or sur_usb(e)) else 'ORANGE'
        add('Minecraft', niv, 'Lancé par un programme inconnu : ' + comm(direct), "PID %d · %s · ce n'est pas un launcher connu" % (direct, e), e)
    else:
        m = re.search(r'-Dminecraft\.launcher\.brand=(\S+)', tout)
        det = 'le launcher est fermé (normal pour beaucoup de launchers)' + (' · marque déclarée : ' + m.group(1) if m else '')
        add('Minecraft', 'INFO', 'Lancé avec : %s (déduit des dossiers)' % fmt_launcher(launcher_chemin(gd or exe(pid) or '')), det)
    # jars du classpath / agents : client de triche ou jar hors des dossiers du launcher
    vus = set()
    for a in args:
        for j in re.findall(r'(/[^:\s"]+?\.jar)(?=$|[:=\s])', a):
            if j in vus: continue
            vus.add(j); nom = os.path.basename(j)
            if nom == 'theseus.jar': continue
            if RE_NOM.search(nom) and not re.match(r'(?i)^(authlib|brigadier|datafixerupper)', nom):
                add('Minecraft', 'ROUGE', 'Client suspect dans le classpath : ' + nom, 'Le jeu a été lancé avec ce jar : nom de client de triche', j)
            elif re.search(r'(?i)/(downloads|téléchargements|desktop|bureau|tmp)/', j) or sur_usb(j):
                n2, rs, _ = analyse_jar(j, nom)
                add('Minecraft', 'ROUGE' if n2 == 'ROUGE' else 'ORANGE', 'Jar chargé depuis un dossier inhabituel : ' + nom, (rs + ' · ' if rs else '') + 'le jeu charge ce jar hors des dossiers du launcher', j)

def scan_launchers():
    etape('Launchers et clients installés')
    mc = os.path.join(HOME, '.minecraft')
    connus = [('Launcher officiel Minecraft', [mc + '/launcher_profiles.json', '/opt/minecraft-launcher', '/usr/bin/minecraft-launcher']),
              ('Lunar Client', [HOME + '/.lunarclient']), ('Feather Client', [HOME + '/.feather']),
              ('Badlion Client', [HOME + '/.config/Badlion Client', HOME + '/Badlion Client']),
              ('Modrinth App', [HOME + '/.local/share/ModrinthApp', HOME + '/.local/share/com.modrinth.theseus', HOME + '/.var/app/com.modrinth.ModrinthApp']),
              ('Prism Launcher', [HOME + '/.local/share/PrismLauncher', HOME + '/.var/app/org.prismlauncher.PrismLauncher']),
              ('PolyMC', [HOME + '/.local/share/PolyMC']), ('MultiMC', [HOME + '/.local/share/multimc']),
              ('ATLauncher', [HOME + '/.local/share/atlauncher']), ('GDLauncher', [HOME + '/.local/share/gdlauncher_carbon']),
              ('LabyMod', [mc + '/labymod-neo']), ('Technic Launcher', [HOME + '/.technic']),
              ('TLauncher (cracké)', [HOME + '/.tlauncher']), ('SKLauncher (cracké)', [mc + '/sklauncher', HOME + '/.sklauncher'])]
    trouves = [n for n, ps in connus if any(os.path.exists(p) for p in ps)]
    if trouves: add('Minecraft', 'INFO', 'Launchers / clients installés : %d' % len(trouves), ', '.join(trouves))
    else: add('Minecraft', 'INFO', 'Launchers / clients installés', 'Aucun launcher connu trouvé : demande au joueur lequel il utilise.')
    vd = os.path.join(mc, 'versions')
    if os.path.isdir(vd):
        n = 0
        for v in sorted(os.listdir(vd)):
            if re.match(r'(?i)^\d+\.\d+(\.\d+)?([- ](pre|rc|snapshot)[- ]?\d+)?$|^\d\dw\d\d[a-z]$|^fabric-loader-|^quilt-loader-|-forge-|^forge-|^neoforge-|-OptiFine_|^OptiFine|^LabyMod|^Badlion|^lunar', v): continue
            jar = os.path.join(vd, v, v + '.jar')
            niv = 'INFO'; det = 'version personnalisée'
            if RE_NOM.search(v): niv = 'ROUGE'; det = 'nom de client de triche · ' + det
            if os.path.isfile(jar) and os.path.getsize(jar) < 80 << 20:
                n2, rs, _ = analyse_jar(jar, v + '.jar')
                if n2 == 'ROUGE': niv = 'ROUGE'; det = rs + ' · ' + det
                elif n2 and niv == 'INFO' and 'aucun fichier de mod' not in rs: niv = 'ORANGE'; det = rs + ' · ' + det
            add('Minecraft', niv, 'Version de jeu : ' + v, det, os.path.join(vd, v))
            n += 1
            if n >= 25: break
    for fp in (mc + '/launcher_profiles.json',):
        try: js = json.loads(lire(fp) or '{}')
        except Exception: continue
        for k, pr in (js.get('profiles') or {}).items():
            nomp = pr.get('name') or k; ja = pr.get('javaArgs') or ''
            if re.search(r'(?i)-javaagent|-agentpath|-agentlib:(?!jdwp)|-Xbootclasspath|-noverify', ja):
                add('Minecraft', 'ROUGE', 'Profil du launcher avec injection : ' + nomp, 'arguments Java : ' + ja, fp)
            if RE_NOM.search(pr.get('lastVersionId') or ''):
                add('Minecraft', 'ROUGE', 'Profil du launcher sur une version suspecte : ' + nomp, 'version : ' + pr.get('lastVersionId'), fp)

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

# ---------------- macros / autoclickers ----------------
RE_CLIC_AUTO = re.compile(r'(?i)(xautoclick|autoclick|auto-clicker|clicker|xdotool|ydotool)')
RE_MACRO_PROG = re.compile(r'(?i)^(xdotool|ydotool|ydotoold|autokey.*|xmacro.*|xnee|cnee|actiona|actexec|xautoclick|.*autoclick.*|.*clicker.*|input-remapper.*|key-?mapper.*|xbindkeys|sxhkd|evsieve|evdevremapkeys|makima|kmonad|keyd|interception.*|udevmon)$')
RE_SOURIS_PROG = re.compile(r'(?i)^(piper|ratbagd|solaar|openrazer.*|polychromatic.*|ckb-next.*|razercommander|openrgb)$')
RE_NOM_MACRO = re.compile(r'(?i)(?<![a-z0-9])(auto[ _-]?click(er|ing)?|rapid[ _-]?fire|butterfly|jitter[ _-]?click|drag[ _-]?click|spam[ _-]?click|turbo[ _-]?click|clicker|\d{1,2}[ _-]?cps)(?![a-z])')

def analyse_macro(t):
    """Dit si un script (bash, python, AutoKey, input-remapper, Lua...) clique tout seul."""
    if not t: return None
    clic = re.search(r'(?im)(\bxdotool\s+(click|mousedown)|\bydotool\s+click|\bpyautogui\.click|\bmouse\.click\b|\bpynput\b[\s\S]{0,400}\.click|\bBTN_(LEFT|RIGHT)\b|\bPress(AndRelease)?MouseButton\s*\(|^\s*Click\b|\bSend(Input)?\b[^\n]{0,40}\{\s*(Click|LButton))', t)
    boucle = re.search(r'(?im)(^\s*(while|for|until|loop|repeat)\b|\bwhile\s+(true|1|:)|\brepeat\s*\(|\bSetTimer\b|--repeat\s+\d)', t)
    tient = re.search(r'(?i)(IsMouseButtonPressed|GetKeyState\s*\(?\s*"?(LButton|RButton)|is_pressed\(|\bbutton_held\b)', t)
    hasard = re.search(r'(?i)\brandom\b|\$RANDOM|shuf\s', t) and re.search(r'(?i)\bsleep\b|--delay', t)
    bouge = re.search(r'(?i)\bxdotool\s+mousemove_relative|\bMoveMouseRelative\s*\(|\bmouse\.move\(|\bmoveRel\(', t)
    if clic and (boucle or tient):
        r = 'AUTOCLICKER : envoie des clics de souris en boucle'
        if tient: r += " tant qu'un bouton est maintenu"
        if hasard: r += ', avec un délai aléatoire pour paraître humain'
        return ('ROUGE', r)
    if bouge and (boucle or tient): return ('ORANGE', 'déplace la souris tout seul en boucle (anti-recul / visée)')
    if clic: return ('ORANGE', 'envoie des clics de souris')
    return None

def fichiers_profonds(racines, motif, prof=4, maxi=30000):
    ignore = re.compile(r'(?i)^(\.cache|cache|caches|node_modules|\.git|\.npm|\.cargo|\.rustup|\.local/share/steam|steamapps|proc|sys|\.mozilla|\.thunderbird|google-chrome|chromium|\.var)$')
    vus = 0
    for r in racines:
        if not os.path.isdir(r): continue
        for racine, sous, fs in os.walk(r):
            if racine.count(os.sep) - r.count(os.sep) >= prof: sous[:] = []
            sous[:] = [s for s in sous if not ignore.match(s)]
            for f in fs:
                vus += 1
                if vus > maxi: return
                if motif.search(f): yield os.path.join(racine, f)

def scan_macros():
    etape('Macros / autoclick')
    alerte = 0; vus = set()
    # 1. programmes de macro / clic automatique en cours
    for pid in liste_pids():
        c = comm(pid); args = cmdline(pid)
        if not c or not args: continue
        tout = ' '.join(args)
        base = os.path.basename(args[0])
        if RE_CLIC_AUTO.search(c) or RE_CLIC_AUTO.search(base) or re.search(r'\b(xdotool|ydotool)\s+(click|mousedown)', tout):
            alerte += 1; add('Macros', 'ROUGE', 'Clic automatique EN COURS : ' + c, 'PID %d · %s' % (pid, tout[:200]), exe(pid) or ''); continue
        if RE_MACRO_PROG.match(c) or RE_MACRO_PROG.match(base):
            alerte += 1; add('Macros', 'ORANGE', 'Logiciel de macro / remappage EN COURS : ' + c, 'PID %d · %s' % (pid, tout[:200]), exe(pid) or ''); continue
        if RE_SOURIS_PROG.match(c):
            add('Macros', 'INFO', 'Logiciel de souris ouvert : ' + c, "Peut contenir des macros : fais-le ouvrir et montrer les boutons / macros."); continue
        # script (bash, python, lua...) lance par le joueur : on lit son contenu
        if re.match(r'^(ba|z|da|fi)?sh$|^python[0-9.]*$|^lua[0-9.]*$|^node$|^perl$', base):
            for a in args[1:]:
                if a.startswith('-') or not os.path.isfile(a): continue
                ra = os.path.realpath(a)
                if not (ra.startswith(HOME) or ra.startswith('/tmp') or externe(ra)) or ra in vus: break
                vus.add(ra)
                an = analyse_macro(lire(ra) or '')
                if an: alerte += 1; add('Macros', an[0], 'Script EN COURS : ' + os.path.basename(ra), an[1] + ' · PID %d' % pid, ra)
                break
    # 2. scripts sur le disque
    nb = 0
    motif = re.compile(r'(?i)\.(sh|bash|py|lua|ahk|pl|js)$')
    for p in fichiers_profonds([HOME] + [m[0] for m in MONTAGES], motif, prof=4):
        rp = os.path.realpath(p)
        if rp in vus or re.search(r'(?i)/(\.minecraft|site-packages|dist-packages|\.local/lib|\.local/share/(lutris|bottles|flatpak)|\.steam|\.wine|anaconda|miniconda|\.pyenv|venv|\.venv)/', rp): continue
        try:
            if os.path.getsize(rp) > 2 << 20: continue
            mt = os.path.getmtime(rp)
        except Exception: continue
        t = lire(rp) or ''
        if 'click' not in t.lower() and 'BTN_' not in t and 'MouseButton' not in t: continue
        an = analyse_macro(t)
        if not an: continue
        vus.add(rp); nb += 1
        sur = ' (sur une clé USB)' if sur_usb(rp) else ''
        niv = an[0] if (an[0] != 'ROUGE' or mt >= NOW - 30 * 86400 or sur) else 'ORANGE'
        alerte += 1; add('Macros', niv, 'Script de clic automatique' + sur + ' : ' + os.path.basename(rp), an[1] + ' · modifié le ' + fdate(mt), rp)
        if nb >= 40: break
    # 3. configurations de macros (AutoKey, input-remapper, xbindkeys, sxhkd, Solaar)
    confs = []
    for mo in ('.config/autokey/data/**/*.py', '.config/input-remapper*/presets/**/*.json', '.config/input-remapper*/**/*.json',
               '.xbindkeysrc', '.config/sxhkd/sxhkdrc', '.config/solaar/rules.yaml', '.config/keyd/*.conf', '.config/makima/*.toml'):
        confs += glob.glob(os.path.join(HOME, mo), recursive=True)
    confs += glob.glob('/etc/keyd/*.conf') + glob.glob('/etc/interception/**/*.yaml', recursive=True)
    for p in sorted(set(confs)):
        if os.path.realpath(p) in vus: continue
        t = lire(p) or ''
        if not t: continue
        an = analyse_macro(t)
        noms = sorted(set(m.group(0).lower() for m in RE_NOM_MACRO.finditer(t)))[:6]
        if re.search(r'(?i)repeat\s*\(', t) and re.search(r'BTN_(LEFT|RIGHT)|mouse\s*\(', t): an = ('ROUGE', 'macro input-remapper qui répète des clics (repeat + BTN_LEFT)')
        elif not an and re.search(r'(?i)MouseClick|BTN_LEFT|BTN_RIGHT|xdotool\s+click', t): an = ('ORANGE', 'macro qui envoie des clics de souris')
        if an:
            alerte += 1; add('Macros', an[0], 'Macro configurée : ' + os.path.relpath(p, HOME) if p.startswith(HOME) else 'Macro configurée : ' + p, an[1] + (' · noms : ' + ', '.join(noms) if noms else ''), p)
        elif noms:
            alerte += 1; add('Macros', 'ORANGE', 'Macro au nom suspect : ' + os.path.basename(p), 'noms trouvés : ' + ', '.join(noms), p)
        else:
            add('Macros', 'INFO', 'Configuration de macros / remappage : ' + os.path.basename(p), "Pas de clic automatique trouvé dedans.", p)
    # 4. fausses souris / faux claviers crees par un programme (uinput)
    blocs = (lire('/proc/bus/input/devices') or '').split('\n\n')
    for b in blocs:
        m1 = re.search(r'N: Name="([^"]*)"', b); m2 = re.search(r'S: Sysfs=(\S+)', b); m3 = re.search(r'H: Handlers=(.*)', b)
        if not (m1 and m2 and m3) or '/virtual/' not in m2.group(1): continue
        nom = m1.group(1); h = m3.group(1)
        if 'mouse' not in h and 'kbd' not in h: continue
        genre = 'souris' if 'mouse' in h else 'clavier'
        if re.search(r'(?i)ydotool|xdotool|py-evdev|uinput|autoclick|clicker|remapper|macro|evsieve|makima|kmonad|keyd', nom):
            alerte += 1; add('Macros', 'ROUGE' if genre == 'souris' else 'ORANGE', 'Fausse %s créée par un programme : %s' % (genre, nom), 'Un logiciel peut cliquer / taper à la place du joueur via ce périphérique virtuel.')
        elif re.search(r'(?i)steam|xwayland|virtualbox|vmware|qemu|spice|sunshine|kde ?connect|gamescope|wacom|power|sleep|video bus', nom):
            add('Macros', 'INFO', 'Périphérique virtuel connu : ' + nom, genre)
        else:
            alerte += 1; add('Macros', 'ORANGE', 'Périphérique virtuel inconnu (%s) : %s' % (genre, nom), 'Créé par un programme et non par une vraie souris/clavier : demande au joueur ce que c\'est.')
    if ROOT:
        for pid in liste_pids():
            try: fds = os.listdir('/proc/%d/fd' % pid)
            except Exception: continue
            for fd in fds:
                try:
                    if os.readlink('/proc/%d/fd/%s' % (pid, fd)) == '/dev/uinput':
                        c = comm(pid)
                        niv = 'INFO' if re.match(r'(?i)^(steam|sunshine|kdeconnectd|gamescope|solaar|systemd)', c) else 'ORANGE'
                        if niv == 'ORANGE': alerte += 1
                        add('Macros', niv, 'Programme qui peut simuler souris/clavier : ' + c, 'PID %d a ouvert /dev/uinput' % pid, exe(pid) or '')
                        break
                except Exception: pass
    # 5. outils installes
    for b, niv in (('xautoclick', 'ORANGE'), ('autokey-gtk', 'ORANGE'), ('autokey-qt', 'ORANGE'), ('actiona', 'ORANGE'), ('ydotool', 'ORANGE'),
                   ('input-remapper-gtk', 'INFO'), ('xdotool', 'INFO'), ('xnee', 'INFO'), ('cnee', 'INFO')):
        ch = shutil.which(b)
        if ch:
            if niv == 'ORANGE': alerte += 1
            add('Macros', niv, 'Installé : ' + b, 'Outil capable de cliquer / taper automatiquement.', ch)
    if alerte == 0: add('Macros', 'OK', 'Macros / autoclick', 'Aucun autoclicker, script de clic ni macro suspecte trouvé.')
    add('Macros', 'INFO', 'Macros dans la mémoire de la souris', "Les macros enregistrées DANS la souris ne sont pas lisibles depuis le PC : fais montrer le logiciel de la souris.")

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
        RES.insert(avant, ('Usb', 'ORANGE' if sus else 'INFO', 'Clé USB montée : ' + mp, '%s (%s) · %d fichier(s), %d jar(s)' % (dev, fs, nf, nj), mp, ''))
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
for f in (scan_systeme, scan_minecraft, scan_mods, scan_log, scan_programmes, scan_macros, scan_usb, scan_fichiers, bilan_usb):
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
HORO = datetime.datetime.now().strftime('%Y-%m-%d_%H-%M')
def donner_au_joueur(f):
    if ROOT and os.environ.get('SUDO_USER'):
        try: p = pwd.getpwnam(UTILISATEUR); os.chown(f, p.pw_uid, p.pw_gid)
        except Exception: pass
fichier = os.path.join(HOME, 'SnowSS_%s.txt' % HORO)
try:
    with open(fichier, 'w', encoding='utf-8') as fh: fh.write('\n'.join(rapport) + '\n')
    donner_au_joueur(fichier)
    print('  ' + C['T'] + 'Rapport enregistré : ' + fichier + C['R'])
except Exception as e:
    print('  Rapport non enregistré : %s' % e)

# ---------------- interface : tableau de bord ----------------
HTML_MODELE = r'''<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SnowFall SS</title>
<style>
:root{--bg:#0c0d10;--pan:#111317;--row:#14161b;--hov:#1a1d23;--line:#23262d;--line2:#2c3038;--txt:#d7dae0;--fort:#f1f3f6;--mut:#7b818c;--fai:#565b65;
--r:#e5484d;--o:#e2a336;--ok:#46a758;--i:#6b7280;--acc:#8ab4f8;--mono:ui-monospace,"JetBrains Mono","DejaVu Sans Mono","Liberation Mono",monospace}
*{box-sizing:border-box}html,body{margin:0;height:100%}
body{background:var(--bg);color:var(--txt);font:13px/1.5 Inter,system-ui,-apple-system,"Segoe UI",Ubuntu,Cantarell,"Noto Sans",sans-serif;display:flex;flex-direction:column;-webkit-font-smoothing:antialiased}
::selection{background:#8ab4f833}
header{display:flex;align-items:stretch;border-bottom:1px solid var(--line);background:var(--pan);flex-wrap:wrap}
.marque{display:flex;flex-direction:column;justify-content:center;padding:12px 20px;border-right:1px solid var(--line);min-width:236px}
.marque b{color:var(--fort);font-size:14px;font-weight:600;letter-spacing:.2px}
.marque span{color:var(--fai);font:11px var(--mono);text-transform:uppercase;letter-spacing:.8px}
.meta{display:flex;gap:28px;align-items:center;padding:0 20px;flex:1;flex-wrap:wrap}
.meta div{display:flex;flex-direction:column;padding:8px 0}
.meta small{color:var(--fai);font-size:10px;text-transform:uppercase;letter-spacing:.9px}
.meta code{font:12px var(--mono);color:var(--txt)}
.verd{display:flex;flex-direction:column;justify-content:center;padding:10px 22px;border-left:1px solid var(--line);min-width:280px;position:relative}
.verd::before{content:"";position:absolute;left:0;top:0;bottom:0;width:3px;background:var(--c)}
.verd small{color:var(--fai);font-size:10px;text-transform:uppercase;letter-spacing:.9px}
.verd b{color:var(--c);font-size:15px;font-weight:600;letter-spacing:.4px}
.verd span{color:var(--mut);font-size:12px}
.verd.ROUGE{--c:var(--r)}.verd.ORANGE{--c:var(--o)}.verd.OK{--c:var(--ok)}
main{flex:1;display:flex;min-height:0}
nav{width:236px;flex:none;background:var(--pan);border-right:1px solid var(--line);overflow:auto;padding:10px 0}
nav .tit{padding:8px 20px 6px;color:var(--fai);font-size:10px;text-transform:uppercase;letter-spacing:.9px}
nav button{display:flex;align-items:center;gap:10px;width:100%;padding:7px 20px;border:0;border-left:2px solid transparent;background:none;color:var(--mut);font:inherit;text-align:left;cursor:pointer}
nav button:hover{color:var(--txt);background:var(--hov)}
nav button.on{color:var(--fort);border-left-color:var(--acc);background:var(--hov)}
nav .n{margin-left:auto;display:flex;gap:10px;font:11px var(--mono)}
nav .n .r{color:var(--r)}nav .n .o{color:var(--o)}nav .n .z{color:var(--fai)}
section{flex:1;display:flex;flex-direction:column;min-width:0}
.bar{display:flex;gap:10px;align-items:center;padding:10px 20px;border-bottom:1px solid var(--line);flex-wrap:wrap}
.bar input{flex:1;min-width:200px;height:30px;padding:0 10px;border-radius:4px;border:1px solid var(--line2);background:var(--bg);color:var(--txt);font:inherit;outline:none}
.bar input:focus{border-color:var(--acc)}
.seg{display:flex;border:1px solid var(--line2);border-radius:4px;overflow:hidden}
.seg button{height:28px;padding:0 11px;border:0;border-right:1px solid var(--line2);background:none;color:var(--mut);font:inherit;font-size:12px;cursor:pointer}
.seg button:last-child{border-right:0}.seg button:hover{color:var(--txt)}.seg button.on{background:var(--hov);color:var(--fort)}
.puces{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 10px}
.puce{height:26px;padding:0 10px;border-radius:4px;border:1px solid var(--line2);background:none;color:var(--mut);font:inherit;font-size:12px;cursor:pointer}
.puce b{font:500 11px var(--mono);margin-left:6px;color:var(--fai)}
.puce:hover{color:var(--txt);border-color:var(--mut)}.puce.on{color:var(--fort);border-color:var(--acc);background:var(--hov)}
.btn{height:30px;padding:0 12px;border-radius:4px;border:1px solid var(--line2);background:var(--pan);color:var(--txt);font:inherit;font-size:12px;cursor:pointer}
.btn:hover{border-color:var(--mut)}
#liste{flex:1;overflow:auto;padding:18px 20px 40px}
h2{display:flex;align-items:baseline;gap:10px;margin:0 0 10px;font-size:12px;font-weight:600;color:var(--fort);text-transform:uppercase;letter-spacing:.9px}
h2 small{color:var(--fai);font:11px var(--mono);text-transform:none;letter-spacing:0}
.stats{display:grid;grid-template-columns:repeat(4,1fr);border:1px solid var(--line);border-radius:4px;margin-bottom:22px;background:var(--pan)}
.stat{padding:14px 16px;border-right:1px solid var(--line)}.stat:last-child{border-right:0}
.stat b{display:block;font:500 24px/1.2 var(--mono);color:var(--fort)}
.stat span{color:var(--fai);font-size:11px;text-transform:uppercase;letter-spacing:.8px}
.stat.r b{color:var(--r)}.stat.o b{color:var(--o)}.stat.ok b{color:var(--ok)}
.tab{border:1px solid var(--line);border-radius:4px;overflow:hidden}
.ln{display:grid;grid-template-columns:112px 1fr;border-bottom:1px solid var(--line);background:var(--row)}
.ln:last-child{border-bottom:0}.ln:hover{background:var(--hov)}
.ln.cat{grid-template-columns:112px 150px 1fr}
.sev{display:flex;align-items:flex-start;gap:8px;padding:10px 14px;font:600 10px/19px var(--mono);letter-spacing:.8px;color:var(--c)}
.sev::before{content:"";flex:none;width:7px;height:7px;margin-top:6px;border-radius:1px;background:var(--c)}
.ROUGE{--c:var(--r)}.ORANGE{--c:var(--o)}.OK{--c:var(--ok)}.INFO{--c:var(--i)}
.ln.ROUGE{box-shadow:inset 2px 0 0 var(--r)}
.cg{padding:10px 14px 10px 0;color:var(--mut);font-size:12px;line-height:19px}
.co{padding:10px 14px 10px 0;min-width:0}
.ti{color:var(--fort);word-break:break-word}
.de{color:var(--mut);margin-top:2px;word-break:break-word}
.ch{margin-top:4px;font:11.5px var(--mono);color:var(--acc);word-break:break-all;cursor:copy;opacity:.85}
.ch:hover{opacity:1;text-decoration:underline}
.vide{padding:28px;text-align:center;color:var(--fai);border:1px solid var(--line);border-radius:4px;background:var(--row)}
footer{display:flex;gap:20px;padding:7px 20px;color:var(--fai);font:11px var(--mono);border-top:1px solid var(--line);background:var(--pan);flex-wrap:wrap}
#toast{position:fixed;bottom:40px;right:20px;background:var(--pan);border:1px solid var(--line2);color:var(--txt);padding:8px 14px;border-radius:4px;font-size:12px;opacity:0;transition:opacity .15s;pointer-events:none}
@media (max-width:860px){main{flex-direction:column}nav{width:auto;display:flex;overflow-x:auto;padding:0;border-right:0;border-bottom:1px solid var(--line)}nav .tit{display:none}
 nav button{width:auto;flex:none;border-left:0;border-bottom:2px solid transparent;padding:10px 14px}nav button.on{border-bottom-color:var(--acc)}
 .marque,.verd{min-width:0;width:100%;border:0}.meta{gap:16px}.stats{grid-template-columns:repeat(2,1fr)}.stat:nth-child(2){border-right:0}.stat:nth-child(-n+2){border-bottom:1px solid var(--line)}
 .ln,.ln.cat{grid-template-columns:1fr}.sev{padding-bottom:0}.cg,.co{padding-left:14px}.cg{padding-top:0;padding-bottom:0}#liste,.bar{padding-left:16px;padding-right:16px}}
@media print{nav,.bar,footer,#toast{display:none}body,header,.ln,.stats,.tab{background:#fff!important;color:#000}.ti{color:#000}#liste{overflow:visible}}
</style></head><body>
<header>
 <div class="marque"><b>SnowFall SS</b><span>Rapport de screenshare · Linux</span></div>
 <div class="meta" id="meta"></div>
 <div class="verd" id="verd"></div>
</header>
<main><nav id="nav"></nav><section>
<div class="bar"><input id="q" placeholder="Rechercher : mod, chemin, appareil, processus…" autocomplete="off">
<div class="seg" id="seg"><button class="on" data-n="">Tout</button><button data-n="ROUGE">Alerte</button><button data-n="ORANGE">À vérifier</button><button data-n="OK">OK</button><button data-n="INFO">Info</button></div>
<button class="btn" id="copier">Copier le rapport</button><button class="btn" id="imprimer">Exporter PDF</button></div>
<div id="liste"></div></section></main>
<footer id="pied"></footer><div id="toast"></div>
<script>
const D=__DATA__;
const LV={ROUGE:'ALERTE',ORANGE:'À VÉRIFIER',OK:'OK',INFO:'INFO'};
const NOMS={};for(const c of D.cats)NOMS[c[0]]=c[1];
let cat='Resume',niv='',q='',lanc='';
const $=s=>document.querySelector(s);
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>'&#'+c.charCodeAt(0)+';');
const compte=(c,n)=>D.res.filter(r=>(!c||r[0]===c)&&r[1]===n).length;
function toast(t){const e=$('#toast');e.textContent=t;e.style.opacity=1;clearTimeout(toast.t);toast.t=setTimeout(()=>e.style.opacity=0,1400)}
function copier(t,msg){const fin=()=>toast(msg);const vieux=()=>{const a=document.createElement('textarea');a.value=t;document.body.appendChild(a);a.select();try{document.execCommand('copy')}catch(e){}a.remove();fin()};
 if(navigator.clipboard&&navigator.clipboard.writeText)navigator.clipboard.writeText(t).then(fin,vieux);else vieux()}
function menu(){let h='<div class="tit">Vue</div>';
 const bouton=(k,nm)=>{const c=k==='Resume'?null:k,R=compte(c,'ROUGE'),O=compte(c,'ORANGE');
  return '<button class="'+(k===cat&&!q?'on':'')+'" data-c="'+k+'"><span>'+esc(nm)+'</span><span class="n">'+(R?'<span class="r">'+R+'</span>':'')+(O?'<span class="o">'+O+'</span>':'')+(!R&&!O?'<span class="z">0</span>':'')+'</span></button>'};
 h+=bouton('Resume','Résumé')+'<div class="tit">Catégories</div>';
 for(const c of D.cats)if(D.res.some(r=>r[0]===c[0]))h+=bouton(c[0],c[1]);
 $('#nav').innerHTML=h;
 for(const b of document.querySelectorAll('#nav button'))b.onclick=()=>{cat=b.dataset.c;q='';$('#q').value='';menu();liste()}}
function ligne(r,avecCat){
 return '<div class="ln '+r[1]+(avecCat?' cat':'')+'"><div class="sev">'+(LV[r[1]]||r[1])+'</div>'+(avecCat?'<div class="cg">'+esc(NOMS[r[0]]||r[0])+'</div>':'')
  +'<div class="co"><div class="ti">'+esc(r[2])+'</div>'+(r[3]?'<div class="de">'+esc(r[3])+'</div>':'')
  +(r[4]&&String(r[3]).indexOf(r[4])<0?'<div class="ch" data-p="'+esc(r[4])+'" title="Copier le chemin">'+esc(r[4])+'</div>':'')+'</div></div>'}
const tableau=(rs,avecCat,vide)=>rs.length?'<div class="tab">'+rs.map(r=>ligne(r,avecCat)).join('')+'</div>':'<div class="vide">'+vide+'</div>';
function liste(){const ql=q.toLowerCase();let h='';
 const ok=r=>(!niv||r[1]===niv)&&(!ql||(r[2]+' '+r[3]+' '+r[4]).toLowerCase().indexOf(ql)>=0);
 if(ql){const rs=D.res.filter(ok);h='<h2>Recherche<small>'+rs.length+' résultat(s)</small></h2>'+tableau(rs,true,'Aucun résultat.')}
 else if(cat==='Resume'){
  h='<div class="stats"><div class="stat r"><b>'+compte(null,'ROUGE')+'</b><span>Alertes</span></div><div class="stat o"><b>'+compte(null,'ORANGE')+'</b><span>À vérifier</span></div><div class="stat ok"><b>'+compte(null,'OK')+'</b><span>Contrôles OK</span></div><div class="stat"><b>'+D.res.length+'</b><span>Entrées</span></div></div>';
  const imp=D.res.filter(r=>(r[1]==='ROUGE'||r[1]==='ORANGE')&&ok(r)).sort((a,b)=>(a[1]==='ROUGE'?0:1)-(b[1]==='ROUGE'?0:1));
  h+='<h2>Points à examiner avec le joueur<small>'+imp.length+'</small></h2>'+tableau(imp,true,'Aucune alerte ni point à vérifier'+(niv?' avec ce filtre':'')+'.')}
 else{
  let puces='';
  if(cat==='Mods'){
   const g={};for(const r of D.res)if(r[0]==='Mods'&&r[5]){if(!(r[5] in g))g[r[5]]=0;if(/\.jar$/i.test(r[4]||'')&&!/^(▸|Jar modifié|Mod interdit)/.test(r[2]))g[r[5]]++}
   const noms=Object.keys(g);if(lanc&&!(lanc in g))lanc='';
   if(noms.length){let tot=0;for(const k of noms)tot+=g[k];
    puces='<div class="puces">'+[['','Tous les launchers',tot]].concat(noms.map(k=>[k,k,g[k]])).map(x=>'<button class="puce'+(x[0]===lanc?' on':'')+'" data-l="'+esc(x[0])+'">'+esc(x[1])+'<b>'+x[2]+'</b></button>').join('')+'</div>'}}
  const rs=D.res.filter(r=>r[0]===cat&&ok(r)&&(cat!=='Mods'||!lanc||r[5]===lanc));
  h='<h2>'+esc(NOMS[cat]||cat)+'<small>'+rs.length+' entrée(s)</small></h2>'+puces+tableau(rs,false,'Rien à afficher avec ce filtre.')}
 $('#liste').innerHTML=h;$('#liste').scrollTop=0;
 for(const b of document.querySelectorAll('.puce'))b.onclick=()=>{lanc=b.dataset.l;liste()};
 for(const e of document.querySelectorAll('.ch'))e.onclick=()=>copier(e.dataset.p,'Chemin copié')}
const v=D.verdict;$('#verd').className='verd '+v[2];$('#verd').innerHTML='<small>Verdict</small><b>'+esc(v[0])+'</b><span>'+esc(v[1])+'</span>';
$('#meta').innerHTML=[['Machine',D.pc],['Session',D.user],['Date',D.date],['Droits',D.root?'root':'utilisateur (incomplet)'],['Version','v'+D.version]].map(x=>'<div><small>'+x[0]+'</small><code>'+esc(x[1])+'</code></div>').join('');
$('#pied').innerHTML='<span>Lecture seule · aucune modification effectuée</span><span>Rapport texte : '+esc(D.fichier)+'</span>';
document.title='SnowFall SS · '+v[0];
for(const c of document.querySelectorAll('#seg button'))c.onclick=()=>{niv=c.dataset.n;for(const x of document.querySelectorAll('#seg button'))x.classList.toggle('on',x===c);liste()};
$('#q').oninput=e=>{q=e.target.value.trim();menu();liste()};
$('#copier').onclick=()=>copier(D.rapport,'Rapport copié');$('#imprimer').onclick=()=>window.print();
menu();liste();
</script></body></html>
'''

def page_html(donnees):
    js = json.dumps(donnees, ensure_ascii=False).replace('</', '<\\/').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    return HTML_MODELE.replace('__DATA__', js)

def env_session():
    """Variables d'affichage de la session graphique du joueur, pour ouvrir la fenetre en son nom."""
    cles = ('DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'XDG_SESSION_TYPE', 'XDG_CURRENT_DESKTOP', 'LANG')
    env = {k: os.environ[k] for k in cles if os.environ.get(k)}
    try: uid = pwd.getpwnam(UTILISATEUR).pw_uid
    except Exception: uid = os.getuid()
    if ROOT or not (env.get('DISPLAY') or env.get('WAYLAND_DISPLAY')):
        meilleur = 0; trouve = {}
        for pid in liste_pids():
            try:
                if os.stat('/proc/%d' % pid).st_uid != uid: continue
            except Exception: continue
            d = lire('/proc/%d/environ' % pid, True)
            if not d: continue
            e = {}
            for x in d.split(b'\0'):
                k, _, val = x.decode('utf-8', 'replace').partition('=')
                if k in cles and val: e[k] = val
            score = (2 if ('DISPLAY' in e or 'WAYLAND_DISPLAY' in e) else 0) + (1 if 'DBUS_SESSION_BUS_ADDRESS' in e else 0)
            if score > meilleur: meilleur, trouve = score, e
            if score == 3: break
        env.update(trouve)
    if 'XDG_RUNTIME_DIR' not in env and os.path.isdir('/run/user/%d' % uid): env['XDG_RUNTIME_DIR'] = '/run/user/%d' % uid
    return env

def ouvrir_interface(f):
    if os.environ.get('SNOWSS_NOGUI'): return False
    env = env_session()
    if not (env.get('DISPLAY') or env.get('WAYLAND_DISPLAY')): return False
    url = 'file://' + urllib.parse.quote(f)
    essais = []
    for b in ('google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser', 'brave-browser', 'brave', 'microsoft-edge', 'vivaldi'):
        ch = shutil.which(b)
        if ch: essais.append([ch, '--app=' + url, '--window-size=1280,820']); break
    for b in ('xdg-open', 'gio', 'firefox'):
        ch = shutil.which(b)
        if ch: essais.append([ch, 'open', url] if b == 'gio' else [ch, url])
    base = ['env', '-i', 'PATH=' + os.environ.get('PATH', '/usr/local/bin:/usr/bin:/bin'), 'HOME=' + HOME,
            'USER=' + UTILISATEUR, 'LOGNAME=' + UTILISATEUR] + ['%s=%s' % kv for kv in env.items()]
    pref = []
    if ROOT and UTILISATEUR != 'root':
        pref = ['runuser', '-u', UTILISATEUR, '--'] if shutil.which('runuser') else ['sudo', '-u', UTILISATEUR]
    for c in essais:
        try:
            p = subprocess.Popen(pref + base + c, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True, cwd=HOME if os.path.isdir(HOME) else '/')
            time.sleep(2)
            if p.poll() is None or p.returncode == 0: return True
        except Exception:
            pass
    return False

donnees = {'version': VERSION, 'date': datetime.datetime.now().strftime('%d/%m/%Y %H:%M'), 'pc': socket.gethostname(),
           'user': UTILISATEUR, 'root': ROOT, 'verdict': list(verdict), 'cats': [list(c) for c in CATS],
           'res': [list(r) for r in RES], 'rapport': '\n'.join(rapport), 'fichier': fichier}
fhtml = os.path.join(HOME, 'SnowSS_%s.html' % HORO)
try:
    with open(fhtml, 'w', encoding='utf-8') as fh: fh.write(page_html(donnees))
    donner_au_joueur(fhtml)
    if ouvrir_interface(fhtml): print('  ' + C['T'] + 'Interface ouverte dans une fenêtre du navigateur : ' + fhtml + C['R'] + '\n')
    else: print('  ' + C['T'] + 'Interface : ouvre ce fichier dans ton navigateur : ' + fhtml + C['R'] + '\n')
except Exception as e:
    print('  Interface non créée : %s\n' % e)
SNOWSS_FIN_PYTHON
