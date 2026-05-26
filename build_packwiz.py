#!/usr/bin/env python3
"""Reconstruye un pack packwiz desde un .mrpack (Modrinth) en el directorio actual."""
import zipfile, json, os, re, sys, urllib.request, urllib.parse
from urllib.parse import urlparse, unquote

MRPACK = sys.argv[1]
OUT = os.getcwd()

z = zipfile.ZipFile(MRPACK)
idx = json.loads(z.read('modrinth.index.json'))
files = idx['files']

# --- parse project/version id from CDN url ---
def parse_ids(url):
    # https://cdn.modrinth.com/data/<proj>/versions/<ver>/<file>
    m = re.match(r'https://cdn\.modrinth\.com/data/([^/]+)/versions/([^/]+)/', url)
    return (m.group(1), m.group(2)) if m else (None, None)

for f in files:
    pid, vid = parse_ids(f['downloads'][0])
    f['_pid'], f['_vid'] = pid, vid

# --- fetch slug/title/type from Modrinth API in chunks ---
pids = sorted({f['_pid'] for f in files if f['_pid']})
meta = {}
def chunks(l, n):
    for i in range(0, len(l), n): yield l[i:i+n]
for c in chunks(pids, 100):
    q = urllib.parse.quote(json.dumps(c))
    url = f'https://api.modrinth.com/v2/projects?ids={q}'
    req = urllib.request.Request(url, headers={'User-Agent': 'packwiz-rebuild/1.0 (local)'})
    try:
        data = json.loads(urllib.request.urlopen(req, timeout=30).read())
        for p in data:
            meta[p['id']] = {'slug': p.get('slug'), 'title': p.get('title'),
                             'type': p.get('project_type')}
    except Exception as e:
        print('WARN API:', e)

def side_of(env):
    if not env: return 'both'
    c, s = env.get('client','required'), env.get('server','required')
    if c != 'unsupported' and s == 'unsupported': return 'client'
    if s != 'unsupported' and c == 'unsupported': return 'server'
    return 'both'

def stem(fn):
    return re.sub(r'\.(jar|zip|litemod)$', '', fn)

def toml_str(s):
    """TOML basic string: keep Unicode literal, escape only \\, \" and controls."""
    out = []
    for ch in s:
        if ch == '\\': out.append('\\\\')
        elif ch == '"': out.append('\\"')
        elif ch == '\n': out.append('\\n')
        elif ch == '\t': out.append('\\t')
        elif ch == '\r': out.append('\\r')
        elif ord(ch) < 0x20: out.append('\\u%04x' % ord(ch))
        else: out.append(ch)
    return '"' + ''.join(out) + '"'

# --- generate .pw.toml metadata files ---
used = {}
count = 0
for f in files:
    path = f['path']                 # e.g. mods/Adorn-...jar
    folder = os.path.dirname(path) or 'mods'
    fname = os.path.basename(path)
    pid, vid = f['_pid'], f['_vid']
    m = meta.get(pid, {})
    slug = m.get('slug') or stem(fname).lower()
    title = m.get('title') or stem(fname)
    side = side_of(f.get('env'))
    sha512 = f['hashes']['sha512']
    url = f['downloads'][0]
    # unique metafile name within folder
    base = re.sub(r'[^a-z0-9._-]', '-', slug.lower())
    key = (folder, base)
    if key in used:
        used[key]+=1; base = f'{base}-{used[key]}'
    else:
        used[key]=0
    metapath = os.path.join(OUT, folder, base + '.pw.toml')
    os.makedirs(os.path.dirname(metapath), exist_ok=True)
    content = f'''name = {toml_str(title)}
filename = {toml_str(fname)}
side = "{side}"

[download]
hash-format = "sha512"
hash = "{sha512}"
url = "{url}"

[update]
[update.modrinth]
mod-id = "{pid}"
version = "{vid}"
'''
    with open(metapath, 'w') as fh:
        fh.write(content)
    count += 1
print(f'Generados {count} archivos .pw.toml')

# --- extract overrides into repo root ---
ov = [n for n in z.namelist() if n.startswith('overrides/') and not n.endswith('/')]
for n in ov:
    rel = n[len('overrides/'):]
    dest = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with z.open(n) as src, open(dest, 'wb') as out:
        out.write(src.read())
print(f'Extraidos {len(ov)} archivos de overrides')

# --- write pack.toml ---
deps = idx.get('dependencies', {})
mc = deps.get('minecraft', '')
versions_lines = []
if mc: versions_lines.append(f'minecraft = "{mc}"')
if 'fabric-loader' in deps: versions_lines.append(f'fabric = "{deps["fabric-loader"]}"')
if 'quilt-loader' in deps: versions_lines.append(f'quilt = "{deps["quilt-loader"]}"')
if 'forge' in deps: versions_lines.append(f'forge = "{deps["forge"]}"')
if 'neoforge' in deps: versions_lines.append(f'neoforge = "{deps["neoforge"]}"')

name = idx.get('name','Modpack')
version = idx.get('versionId','1.0.0')
# strip trailing version from name if duplicated
name_clean = re.sub(r'\s+'+re.escape(version)+r'\s*$', '', name).strip() or name
packtoml = f'''name = "{name_clean}"
author = "Jandro5vq"
version = "{version}"
pack-format = "packwiz:1.1.0"

[index]
file = "index.toml"

[versions]
{chr(10).join(versions_lines)}
'''
with open(os.path.join(OUT,'pack.toml'),'w') as fh:
    fh.write(packtoml)
print('pack.toml escrito:')
print(packtoml)
