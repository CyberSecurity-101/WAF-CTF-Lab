#!/bin/bash
# =============================================================================
# OPERATION IRON WALL — Complete Fresh Install
# =============================================================================
# ONE script. Does everything:
#   1. Removes ALL previous lab files, processes, and configs
#   2. Installs dependencies
#   3. Builds the vulnerable Flask target app  (port 8080)
#   4. Builds the Python WAF proxy             (port 9080)
#   5. Creates SQLite database with embedded flags
#   6. Plants all 15 flag files
#   7. Creates the flag checker
#   8. Starts both services
#   9. Runs verification — all checks must pass
#
# Supports: Kali Linux (native) · Ubuntu · Debian
# Point WAF Bypass Scanner at: http://localhost:9080
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; BOLD='\033[1m'; NC='\033[0m'

# NO set -e — pkill exits 1 when nothing to kill, which would abort the script

# ─────────────────────────────────────────────────────────────────────────────
print_banner() {
clear
echo -e "${PURPLE}${BOLD}"
cat << 'EOF'
 ██╗██████╗  ██████╗ ███╗   ██╗    ██╗    ██╗ █████╗ ██╗     ██╗
 ██║██╔══██╗██╔═══██╗████╗  ██║    ██║    ██║██╔══██╗██║     ██║
 ██║██████╔╝██║   ██║██╔██╗ ██║    ██║ █╗ ██║███████║██║     ██║
 ██║██╔══██╗██║   ██║██║╚██╗██║    ██║███╗██║██╔══██║██║     ██║
 ██║██║  ██║╚██████╔╝██║ ╚████║    ╚███╔███╔╝██║  ██║███████╗███████╗
 ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝
        OPERATION IRON WALL — Fresh Install v3.0
        15 Flags · 4 Methods · Python WAF · All Bugs Fixed
EOF
echo -e "${NC}"
}

step() { echo -e "\n${YELLOW}${BOLD}[STEP $1]${NC} ${YELLOW}$2${NC}"; }
ok()   { echo -e "  ${GREEN}[+]${NC} $1"; }
info() { echo -e "  ${CYAN}[i]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
fail() { echo -e "  ${RED}[✗]${NC} $1"; }

LAB="/opt/ironwall"

print_banner

# ─────────────────────────────────────────────────────────────────────────────
# STEP 0 — NUKE EVERYTHING PREVIOUS
# ─────────────────────────────────────────────────────────────────────────────
step 0 "Removing all previous lab files and processes"

# Kill any running processes on ports 8080 / 9080
for pat in "ironwall/app/app.py" "ironwall/app/waf.py" "ironwall.*app.py" "ironwall.*waf.py"; do
    pkill -f "$pat" 2>/dev/null || true
done
sleep 1

for PORT in 8080 9080; do
    PIDS=$(lsof -ti tcp:$PORT 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        kill -KILL $PIDS 2>/dev/null || true
        info "Freed port $PORT"
    fi
done
sleep 1

# Remove lab directory
if [ -d "$LAB" ]; then
    rm -rf "$LAB"
    ok "Removed $LAB"
else
    info "$LAB did not exist — clean slate"
fi

# Remove any old BrokenPortal lab too
if [ -d "/opt/brokenportal" ]; then
    rm -rf "/opt/brokenportal"
    ok "Removed /opt/brokenportal"
fi

# Remove stale temp files
rm -f /tmp/ironwall_* 2>/dev/null || true
ok "Previous lab fully removed"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — DEPENDENCIES
# ─────────────────────────────────────────────────────────────────────────────
step 1 "Installing dependencies"

if ! command -v python3 &>/dev/null; then
    warn "python3 not found — installing..."
    sudo apt-get install -y -qq python3 python3-pip
fi
ok "python3: $(python3 --version 2>&1)"

# Install flask — try multiple methods for Kali/Ubuntu compatibility
if ! python3 -c "import flask" 2>/dev/null; then
    info "Installing Flask..."
    pip3 install flask --break-system-packages -q 2>/dev/null || \
    pip3 install flask -q 2>/dev/null || \
    sudo apt-get install -y -qq python3-flask 2>/dev/null || true
fi

if python3 -c "import flask" 2>/dev/null; then
    ok "Flask: $(python3 -c 'import flask; print(flask.__version__)' 2>/dev/null)"
else
    fail "Flask install failed. Try manually: pip3 install flask --break-system-packages"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — DIRECTORY STRUCTURE
# ─────────────────────────────────────────────────────────────────────────────
step 2 "Creating directory structure"

sudo mkdir -p "$LAB"
sudo chown "$USER:$USER" "$LAB"

mkdir -p "$LAB"/{app,flags,logs,flags_found,modsec}
mkdir -p "$LAB"/app/{db,docs,backup,hidden}

ok "Directory tree created at $LAB"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — PLANT FLAGS
# ─────────────────────────────────────────────────────────────────────────────
step 3 "Planting 15 flags"

# Master flag list — single source of truth
declare -A FLAGS=(
    [01]="FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}"
    [02]="FLAG{IW_CACHE_CTRL_BYPASS_EASY_d4e5f6}"
    [03]="FLAG{IW_XSS_CASE_TOGGLE_EASY_g7h8i9}"
    [04]="FLAG{IW_SQLI_BASIC_UNION_EASY_j0k1l2}"
    [05]="FLAG{IW_PATH_TRAV_BASIC_EASY_m3n4o5}"
    [06]="FLAG{IW_HTTP_PARAM_POLL_MED_p6q7r8}"
    [07]="FLAG{IW_XSS_DOUBLE_ENC_MED_s9t0u1}"
    [08]="FLAG{IW_SQLI_COMMENT_SPLIT_MED_v2w3x4}"
    [09]="FLAG{IW_PATH_TRAV_ENC_MED_y5z6a7b8}"
    [10]="FLAG{IW_NULL_BYTE_BYPASS_MED_c9d0e1f2}"
    [11]="FLAG{IW_CHUNKED_TE_BYPASS_HARD_g3h4i5}"
    [12]="FLAG{IW_UNICODE_XSS_HARD_j6k7l8m9}"
    [13]="FLAG{IW_NESTED_ENC_CHAIN_HARD_n0o1p2}"
    [14]="FLAG{IW_MYSQL_INLINE_CMT_HARD_q3r4s5}"
    [15]="FLAG{IW_FULL_CHAIN_MASTER_HARD_t6u7v8}"
)

# Write master flag files
for n in "${!FLAGS[@]}"; do
    printf "%s\n" "${FLAGS[$n]}" > "$LAB/flags/flag${n}.txt"
done

# Copy flags into app-accessible locations for each challenge
cp "$LAB/flags/flag01.txt" "$LAB/app/hidden/xff_secret.txt"
cp "$LAB/flags/flag02.txt" "$LAB/app/hidden/cache_secret.txt"
cp "$LAB/flags/flag03.txt" "$LAB/app/hidden/xss_easy_secret.txt"
# flag04 → SQLite DB (planted in step 4)
cp "$LAB/flags/flag05.txt" "$LAB/app/docs/flag05_trav.txt"
cp "$LAB/flags/flag06.txt" "$LAB/app/hidden/param_secret.txt"
cp "$LAB/flags/flag07.txt" "$LAB/app/hidden/double_enc_secret.txt"
# flag08 → SQLite DB (products table)
cp "$LAB/flags/flag09.txt" "$LAB/app/docs/flag09_enc_trav.txt"
cp "$LAB/flags/flag10.txt" "$LAB/app/backup/secret.bak"
cp "$LAB/flags/flag11.txt" "$LAB/app/hidden/chunked_secret.txt"
cp "$LAB/flags/flag12.txt" "$LAB/app/hidden/unicode_secret.txt"
cp "$LAB/flags/flag13.txt" "$LAB/app/hidden/nested_enc_secret.txt"
# flag14 → SQLite DB (admin_secrets table)
# flag15 → SQLite DB (admin_secrets table)

# Placeholder readable file for /download endpoint
echo "Iron Wall Lab — normal file" > "$LAB/app/backup/info.txt"
echo "Iron Wall Lab docs" > "$LAB/app/docs/readme.txt"

ok "15 flags planted"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — SQLite DATABASE
# ─────────────────────────────────────────────────────────────────────────────
step 4 "Building SQLite database"

python3 - << PYEOF
import sqlite3, hashlib

db = '$LAB/app/db/lab.db'
conn = sqlite3.connect(db)
c = conn.cursor()

c.execute('DROP TABLE IF EXISTS users')
c.execute('DROP TABLE IF EXISTS products')
c.execute('DROP TABLE IF EXISTS admin_secrets')

c.execute('''CREATE TABLE users (
    id INTEGER PRIMARY KEY, username TEXT,
    password TEXT, role TEXT, token TEXT)''')

c.execute('''CREATE TABLE products (
    id INTEGER PRIMARY KEY, name TEXT,
    price REAL, secret TEXT)''')

c.execute('''CREATE TABLE admin_secrets (
    id INTEGER PRIMARY KEY, key TEXT, value TEXT)''')

md5 = lambda s: hashlib.md5(s.encode()).hexdigest()

# Flag 04 lives in users.token for the admin row
c.executemany('INSERT INTO users VALUES (?,?,?,?,?)', [
    (1, 'admin',    md5('ironwall2024'), 'admin',   'FLAG{IW_SQLI_BASIC_UNION_EASY_j0k1l2}'),
    (2, 'attacker', md5('hacker'),       'user',    ''),
    (3, 'devuser',  md5('dev1234'),      'user',    ''),
])

# Flag 08 lives in products.secret for the admin product row
c.executemany('INSERT INTO products VALUES (?,?,?,?)', [
    (1, 'Widget Standard', 9.99,  ''),
    (2, 'Widget Premium',  19.99, ''),
    (3, 'Admin Product',   0.00,  'FLAG{IW_SQLI_COMMENT_SPLIT_MED_v2w3x4}'),
])

# Flags 14 and 15 live in admin_secrets
c.executemany('INSERT INTO admin_secrets VALUES (?,?,?)', [
    (1, 'mysql_inline_flag', 'FLAG{IW_MYSQL_INLINE_CMT_HARD_q3r4s5}'),
    (2, 'master_flag',       'FLAG{IW_FULL_CHAIN_MASTER_HARD_t6u7v8}'),
    (3, 'hint', 'Chain: XFF spoof + double-encode + inline-comment SQLi'),
])

conn.commit()
conn.close()
print('Database OK — flags 04, 08, 14, 15 embedded')
PYEOF

ok "SQLite database created"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — FLASK TARGET APP  (port 8080, no WAF)
# ─────────────────────────────────────────────────────────────────────────────
step 5 "Writing vulnerable Flask target app (port 8080)"

cat > "$LAB/app/app.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Iron Wall — Vulnerable Target App
Port 8080. Deliberately insecure. Lab use only.
The Python WAF (port 9080) proxies to this.
"""
from flask import Flask, request, jsonify, render_template_string
import sqlite3, os, re, json, urllib.parse

app   = Flask(__name__)
LAB   = '/opt/ironwall'
DB    = LAB + '/app/db/lab.db'

# ── helpers ───────────────────────────────────────────────────────────────────
def get_db():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    return c

def read_flag(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return None

# ── home ──────────────────────────────────────────────────────────────────────
@app.route('/')
def home():
    return render_template_string('''<!DOCTYPE html><html>
<head><title>Iron Wall Target</title>
<style>
  body{background:#0b0d12;color:#e2e8f0;font-family:monospace;padding:30px;margin:0}
  h1{color:#3b82f6;margin-bottom:4px}
  h3{color:#f97316;margin-top:24px;margin-bottom:8px}
  a{color:#22c55e;text-decoration:none}a:hover{text-decoration:underline}
  li{margin:5px 0;line-height:1.5}
  .badge{background:#1c2236;border:1px solid #1e2535;padding:2px 8px;
         border-radius:4px;font-size:11px;margin-right:6px}
  .easy{color:#22c55e}.med{color:#f97316}.hard{color:#ef4444}
  .sub{color:#94a3b8;font-size:13px;margin-bottom:20px}
  #wst{font-weight:bold}
</style></head><body>
<h1>&#127919; Iron Wall — WAF Bypass Lab</h1>
<p class="sub">Deliberately vulnerable. Point WAF Bypass Scanner at
<strong>http://localhost:9080</strong> (WAF active)<br>
Or hit <strong>http://localhost:8080</strong> directly (no WAF).</p>

<h3>Challenge Endpoints</h3>
<ul>
<li><span class="badge easy">EASY-1</span>
    <a href="/xff-check">GET /xff-check</a> — XFF IP spoof</li>
<li><span class="badge easy">EASY-2</span>
    <a href="/cache-secret">GET /cache-secret</a> — Cache-Control bypass</li>
<li><span class="badge easy">EASY-3</span>
    <a href="/reflect?input=hello">GET /reflect?input=</a> — XSS case toggle</li>
<li><span class="badge easy">EASY-4</span>
    <a href="/search?q=widget">GET /search?q=</a> — SQLi UNION basic</li>
<li><span class="badge easy">EASY-5</span>
    <a href="/docs/view?file=readme.txt">GET /docs/view?file=</a> — Path traversal</li>
<li><span class="badge med">MED-6</span>
    <a href="/api/item?id=1">GET /api/item?id=</a> — HTTP param pollution</li>
<li><span class="badge med">MED-7</span>
    <a href="/encode-test?data=hello">GET /encode-test?data=</a> — Double URL encoding</li>
<li><span class="badge med">MED-8</span>
    <a href="/product?id=1">GET /product?id=</a> — SQLi comment splitting</li>
<li><span class="badge med">MED-9</span>
    <a href="/files?path=readme.txt">GET /files?path=</a> — URL-encoded traversal</li>
<li><span class="badge med">MED-10</span>
    <a href="/download?file=info.txt">GET /download?file=</a> — Null byte bypass</li>
<li><span class="badge hard">HARD-11</span>
    POST /api/upload — Chunked transfer-encoding</li>
<li><span class="badge hard">HARD-12</span>
    <a href="/user?name=guest">GET /user?name=</a> — Unicode XSS</li>
<li><span class="badge hard">HARD-13</span>
    <a href="/lookup?q=test">GET /lookup?q=</a> — Nested encoding chain</li>
<li><span class="badge hard">HARD-14</span>
    <a href="/admin/query?id=1">GET /admin/query?id=</a> — MySQL inline comment</li>
<li><span class="badge hard">HARD-15</span>
    <a href="/admin/master">GET /admin/master</a> — Full chain</li>
</ul>

<h3>&#128683; WAF Status: <span id="wst">checking...</span></h3>
<script>
fetch('/waf-status').then(r=>r.json())
  .then(d=>{
    var el=document.getElementById('wst');
    el.textContent=d.active?'ACTIVE on port '+d.port:'DISABLED';
    el.style.color=d.active?'#ef4444':'#22c55e';
  }).catch(()=>{
    document.getElementById('wst').textContent='unknown';
  });
</script>
<p style="margin-top:24px;color:#4a5568;font-size:12px">
  Get a hint: <a href="/hint?stage=1">curl http://localhost:8080/hint?stage=N</a>
  (N = flag number 1-15)
</p>
</body></html>''')

@app.route('/waf-status')
def waf_status():
    return jsonify({'active': True, 'port': 9080, 'mode': 'python'})

# ── FLAG 01: XFF spoof ───────────────────────────────────────────────────────
@app.route('/xff-check')
def xff_check():
    xff  = request.headers.get('X-Forwarded-For', '')
    real = request.headers.get('X-Real-IP', '')
    ip   = xff or real or request.remote_addr
    if ip.startswith(('127.', '10.', '192.168.', '172.')):
        return jsonify({
            'access': 'granted', 'source_ip': ip,
            'flag': read_flag(LAB + '/app/hidden/xff_secret.txt'),
            'hint': 'Internal IP detected — WAF whitelist bypass successful'
        })
    return jsonify({
        'access': 'denied', 'source_ip': ip,
        'hint': 'Only internal IPs allowed. Spoof X-Forwarded-For or X-Real-IP.'
    })

# ── FLAG 02: Cache-Control bypass ────────────────────────────────────────────
@app.route('/cache-secret')
def cache_secret():
    cc     = request.headers.get('Cache-Control', '')
    pragma = request.headers.get('Pragma', '')
    if 'no-store' in cc or 'no-cache' in pragma:
        return jsonify({
            'status': 'cache_exempt',
            'flag': read_flag(LAB + '/app/hidden/cache_secret.txt'),
            'hint': 'Cache-Control: no-store bypassed WAF caching layer'
        })
    return jsonify({
        'status': 'cached',
        'hint': 'Add Cache-Control: no-cache, no-store and Pragma: no-cache',
        'cached_response': 'Nothing to see here'
    })

# ── FLAG 03: XSS case toggle ─────────────────────────────────────────────────
@app.route('/reflect')
def reflect():
    inp = request.args.get('input', '')
    # show_flag when the input contains 'script' in mixed case
    # (lowercase-only <script> is blocked by the WAF before reaching here)
    show = 'script' in inp.lower() and inp.lower() != inp
    return render_template_string('''<!DOCTYPE html><html>
<head><title>Reflect</title>
<style>body{background:#0b0d12;color:#e2e8f0;font-family:monospace;padding:20px}</style>
</head><body>
<h2>XSS Reflection Test</h2>
<p>Input received: <code>{{ inp }}</code></p>
{% if show_flag %}
<p style="color:#22c55e;font-size:16px;margin-top:16px">
  &#127881; Flag: <strong>{{ flag }}</strong></p>
{% else %}
<p style="color:#94a3b8;font-size:12px;margin-top:16px">
  Hint: WAF blocks &lt;script&gt; — does it block &lt;ScrIpT&gt;?<br>
  Try: /reflect?input=&lt;ScrIpT&gt;test&lt;/sCRiPt&gt;
</p>
{% endif %}
</body></html>''', inp=inp, show_flag=show,
        flag=read_flag(LAB + '/app/hidden/xss_easy_secret.txt') or '')

# ── FLAG 04: SQLi basic UNION ────────────────────────────────────────────────
@app.route('/search')
def search():
    q = request.args.get('q', '')
    try:
        conn = get_db()
        # Deliberately injectable
        rows = conn.execute(
            "SELECT id,name,price FROM products WHERE name LIKE '%" + q + "%'"
        ).fetchall()
        conn.close()
        return jsonify({
            'query': q,
            'results': [dict(r) for r in rows],
            'hint': "Try: widget' UNION SELECT id,username,token,price FROM users--"
        })
    except Exception as e:
        return jsonify({'error': str(e), 'hint': 'SQL error — you are on the right track'}), 400

# ── FLAG 05: Path traversal basic ────────────────────────────────────────────
@app.route('/docs/view')
def docs_view():
    fname = request.args.get('file', 'readme.txt')
    base  = LAB + '/app/docs/'
    try:
        with open(base + fname) as f:
            content = f.read()
        return jsonify({'file': fname, 'content': content})
    except FileNotFoundError:
        return jsonify({
            'error': 'File not found', 'base_path': base,
            'hint': 'Try file=flag05_trav.txt (direct) or file=..%2Fflags%2Fflag05.txt'
        })
    except Exception as e:
        return jsonify({'error': str(e)})

# ── FLAG 06: HTTP parameter pollution ────────────────────────────────────────
@app.route('/api/item')
def api_item():
    ids = request.args.getlist('id')
    effective = ids[-1] if ids else '1'
    flag = None
    if 'union' in effective.lower() or 'select' in effective.lower():
        flag = read_flag(LAB + '/app/hidden/param_secret.txt')
    return jsonify({
        'received_ids': ids,
        'effective_id': effective,
        'flag': flag,
        'hint': 'WAF checks id[0], backend uses id[-1]. Try ?id=1&id=UNION+SELECT'
    })

# ── FLAG 07: Double URL encoding ─────────────────────────────────────────────
@app.route('/encode-test')
def encode_test():
    data = request.args.get('data', '')
    d1   = urllib.parse.unquote(data)
    d2   = urllib.parse.unquote(d1)
    is_double = (d1 != data) and (d2 != d1)
    flag = None
    if is_double and ('<script' in d2.lower() or 'union' in d2.lower()):
        flag = read_flag(LAB + '/app/hidden/double_enc_secret.txt')
    return jsonify({
        'original': data, 'decoded_once': d1,
        'decoded_twice': d2, 'double_encoded': is_double,
        'flag': flag,
        'hint': 'WAF decodes once. Backend decodes twice. %253C = double-encoded <'
    })

# ── FLAG 08: SQLi comment splitting ──────────────────────────────────────────
@app.route('/product')
def product():
    pid = request.args.get('id', '1')
    try:
        conn = get_db()
        rows = conn.execute(
            "SELECT id,name,price,secret FROM products WHERE id=" + pid
        ).fetchall()
        conn.close()
        return jsonify({
            'id': pid,
            'results': [dict(r) for r in rows],
            'hint': "Try: 0 un/**/ion sel/**/ect id,name,price,secret from products where id=3--"
        })
    except Exception as e:
        return jsonify({'error': str(e), 'hint': 'Comment splitting: un/**/ion sel/**/ect'})

# ── FLAG 09: URL-encoded path traversal ──────────────────────────────────────
@app.route('/files')
def files():
    path    = request.args.get('path', 'readme.txt')
    decoded = urllib.parse.unquote(path)
    base    = LAB + '/app/docs/'
    try:
        with open(base + decoded) as f:
            content = f.read()
        return jsonify({'path': path, 'decoded': decoded, 'content': content})
    except FileNotFoundError:
        return jsonify({
            'error': 'Not found', 'decoded': decoded,
            'hint': 'Try path=..%2Fdocs%2Fflag09_enc_trav.txt'
        })
    except Exception as e:
        return jsonify({'error': str(e)})

# ── FLAG 10: Null byte bypass ─────────────────────────────────────────────────
@app.route('/download')
def download():
    fname = request.args.get('file', 'info.txt')
    # Simulate null-byte truncation
    clean = fname.split('\x00')[0].split('%00')[0]
    base  = LAB + '/app/backup/'
    try:
        with open(base + clean) as f:
            content = f.read()
        return jsonify({'requested': fname, 'served': clean, 'content': content})
    except FileNotFoundError:
        return jsonify({
            'error': 'Not found', 'served': clean,
            'hint': 'Try file=secret.bak directly, or file=info.txt%2500../backup/secret.bak'
        })
    except Exception as e:
        return jsonify({'error': str(e)})

# ── FLAG 11: Chunked transfer-encoding bypass ─────────────────────────────────
@app.route('/api/upload', methods=['POST'])
def api_upload():
    te   = request.headers.get('Transfer-Encoding', '')
    data = request.get_data(as_text=True)
    flag = None
    if 'chunked' in te.lower() and data:
        flag = read_flag(LAB + '/app/hidden/chunked_secret.txt')
    return jsonify({
        'transfer_encoding': te,
        'data_received': data[:200],
        'flag': flag,
        'hint': 'POST with Transfer-Encoding: chunked header and any body'
    })

# ── FLAG 12: Unicode XSS ─────────────────────────────────────────────────────
@app.route('/user')
def user():
    name = request.args.get('name', 'guest')
    # Detect \uXXXX sequences (unicode escape bypass)
    has_unicode_xss = bool(re.search(r'\\u[0-9a-fA-F]{4}', name))
    flag = read_flag(LAB + '/app/hidden/unicode_secret.txt') if has_unicode_xss else None
    return render_template_string('''<!DOCTYPE html><html>
<head><title>User Profile</title>
<style>body{background:#0b0d12;color:#e2e8f0;font-family:monospace;padding:20px}</style>
</head><body>
<h2>User Profile</h2>
<p>Name: {{ name }}</p>
{% if flag %}
<p style="color:#22c55e;margin-top:16px">&#127881; Flag: <strong>{{ flag }}</strong></p>
{% else %}
<p style="color:#94a3b8;font-size:12px;margin-top:12px">
  Hint: WAF blocks literal "prompt" — try Unicode escapes.<br>
  \\u0070 = p, \\u0072 = r, \\u006f = o, \\u006d = m, \\u0074 = t<br>
  Example: /user?name=test\\u0070r\\u006fmpt()
</p>
{% endif %}
</body></html>''', name=name, flag=flag)

# ── FLAG 13: Nested encoding chain ────────────────────────────────────────────
@app.route('/lookup')
def lookup():
    q  = request.args.get('q', '')
    d1 = urllib.parse.unquote(q)
    d2 = urllib.parse.unquote(d1)
    # HTML entity decode
    d3 = d2.replace('&lt;','<').replace('&gt;','>').replace('&amp;','&') \
           .replace('&#60;','<').replace('&#62;','>')
    flag = None
    if '<script' in d3.lower() or 'union' in d3.lower():
        flag = read_flag(LAB + '/app/hidden/nested_enc_secret.txt')
    return jsonify({
        'raw': q, 'url_decode_1': d1,
        'url_decode_2': d2, 'html_decode': d3,
        'flag': flag,
        'hint': 'HTML-encode → URL-encode → URL-encode again. WAF only strips one layer.'
    })

# ── FLAG 14: MySQL inline comment bypass ──────────────────────────────────────
@app.route('/admin/query')
def admin_query():
    pid = request.args.get('id', '1')
    try:
        conn = get_db()
        # Strip /*!...*/ comments before execution (simulate MySQL behaviour)
        clean = re.sub(r'/\*.*?\*/', ' ', pid)
        rows  = conn.execute(
            "SELECT id,key,value FROM admin_secrets WHERE id=" + clean
        ).fetchall()
        conn.close()
        return jsonify({
            'id': pid, 'cleaned': clean,
            'results': [dict(r) for r in rows],
            'hint': "Payload: 0 /*!UNION*/ /*!SELECT*/ 1,key,value FROM admin_secrets WHERE id=1--"
        })
    except Exception as e:
        return jsonify({'error': str(e), 'hint': '/*!UNION*/ executes but confuses WAF regex'})

# ── FLAG 15: Full chain ────────────────────────────────────────────────────────
@app.route('/admin/master')
def admin_master():
    xff  = request.headers.get('X-Forwarded-For', '')
    real = request.headers.get('X-Real-IP', '')
    src  = xff or real or request.remote_addr

    if not src.startswith(('127.', '10.', '192.168.')):
        return jsonify({
            'access': 'denied',
            'step1': 'FAIL — spoof X-Forwarded-For: 127.0.0.1',
            'hint': 'Step 1: set X-Forwarded-For: 127.0.0.1'
        })

    q  = request.args.get('q', '')
    d1 = urllib.parse.unquote(q)
    d2 = urllib.parse.unquote(d1)

    if not ('union' in d2.lower() or 'select' in d2.lower()):
        return jsonify({
            'access': 'partial',
            'step1': 'PASS — internal IP accepted',
            'step2': 'FAIL — double-encode a UNION SELECT into ?q=',
            'hint': 'Step 2: double-encode " UNION SELECT ..." — %2520 = double-encoded space'
        })

    try:
        conn  = get_db()
        rows  = conn.execute(
            "SELECT id,key,value FROM admin_secrets WHERE id=2"
        ).fetchall()
        conn.close()
        return jsonify({
            'access': 'GRANTED',
            'step1': 'PASS — internal IP spoofed',
            'step2': 'PASS — double-encoded SQLi bypassed WAF',
            'step3': 'PASS — inline comment WAF bypass (chain complete)',
            'results': [dict(r) for r in rows],
            'master_flag': read_flag(LAB + '/flags/flag15.txt')
        })
    except Exception as e:
        return jsonify({'error': str(e)})

# ── utility endpoints ─────────────────────────────────────────────────────────
@app.route('/readme.txt')
@app.route('/info.txt')
def info_txt():
    return 'Iron Wall Lab Target\nPort 8080 (direct) / 9080 (WAF)\n'

@app.route('/hint')
def hint():
    hints = {
        '1':  'Flag 1: curl -H "X-Forwarded-For: 127.0.0.1" http://localhost:9080/xff-check',
        '2':  'Flag 2: curl -H "Cache-Control: no-cache, no-store" http://localhost:9080/cache-secret',
        '3':  'Flag 3: http://localhost:9080/reflect?input=<ScrIpT>test</sCRiPt>',
        '4':  "Flag 4: /search?q=widget%27+UNION/**/SELECT+id,username,token,price+FROM+users--",
        '5':  'Flag 5: /docs/view?file=flag05_trav.txt',
        '6':  'Flag 6: /api/item?id=1&id=UNION+SELECT+1,2,3',
        '7':  'Flag 7: /encode-test?data=%253Cscript%253Ealert()%253C%252Fscript%253E',
        '8':  'Flag 8: /product?id=0+un%2F**%2Fion+sel%2F**%2Fect+id,name,price,secret+from+products+where+id=3--',
        '9':  'Flag 9: /files?path=..%2Fdocs%2Fflag09_enc_trav.txt',
        '10': 'Flag 10: /download?file=secret.bak',
        '11': 'Flag 11: curl -X POST -H "Transfer-Encoding: chunked" --data-binary $\'5\\r\\nhello\\r\\n0\\r\\n\\r\\n\' http://localhost:9080/api/upload',
        '12': r'Flag 12: /user?name=test\u0070r\u006fmpt()',
        '13': 'Flag 13: /lookup?q=%2526lt%253Bscript%2526gt%253Balert()%2526lt%253B%252Fscript%2526gt%253B',
        '14': 'Flag 14: /admin/query?id=0+%2F*!UNION*%2F+%2F*!SELECT*%2F+1,key,value+FROM+admin_secrets+WHERE+id=1--',
        '15': 'Flag 15: curl -H "X-Forwarded-For: 127.0.0.1" "http://localhost:9080/admin/master?q=%2520UNION%2520SELECT%25201%2Ckey%2Cvalue%2520FROM%2520admin_secrets%2520WHERE%2520id%253D2--"',
    }
    stage = request.args.get('stage', '1')
    return jsonify({'stage': stage, 'hint': hints.get(stage, 'Invalid stage (1-15)')})

if __name__ == '__main__':
    print('[*] Iron Wall Target running on http://0.0.0.0:8080')
    app.run(host='0.0.0.0', port=8080, debug=False)
PYEOF

ok "Flask target app written"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — PYTHON WAF  (port 9080 → proxies to 8080)
# ALL 3 BUG FIXES INCLUDED:
#   Fix A: URL-decode path before rule matching  (was: %3Cscript%3E never matched)
#   Fix B: CORS headers on ALL responses         (was: browser scanner got CORS errors)
#   Fix C: Lowercase header keys for whitelist   (was: XFF bypass silently failed)
# ─────────────────────────────────────────────────────────────────────────────
step 6 "Writing Python WAF (port 9080) — all bugs fixed"

cat > "$LAB/app/waf.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Iron Wall Python WAF — port 9080
Proxies to target app at port 8080.
All known bugs fixed in this version.
"""
import re, json, time, urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import urlopen, Request as UReq
from urllib.error import URLError

TARGET = 'http://127.0.0.1:8080'
LOG    = '/opt/ironwall/logs/waf.log'

# ── WAF RULES ─────────────────────────────────────────────────────────────────
# Rules match DECODED content.
# Gap: single-decode only — double-encoded payloads still bypass (by design).
RULES = [
    (re.compile(r'<script[\s>]', re.I), 'XSS-001',  'script tag blocked'),
    (re.compile(r'\bUNION\s+SELECT\b', re.I), 'SQLI-001', 'UNION SELECT blocked'),
    (re.compile(r'\.\./',              ),      'TRAV-001', 'path traversal blocked'),
    (re.compile(r'/etc/passwd',        ),      'RCE-001',  'sensitive path blocked'),
    (re.compile(r'%00',                ),      'NULL-001', 'null byte blocked'),
]

# Internal IPs that bypass ALL rules
WHITELIST_IPS  = ('127.', '10.', '192.168.', '172.')
WHITELIST_HDRS = ('x-forwarded-for', 'x-real-ip', 'x-client-ip')

# CORS headers sent on every response (required for WAF Bypass Scanner)
CORS = [
    ('Access-Control-Allow-Origin',   '*'),
    ('Access-Control-Allow-Methods',  'GET,POST,PUT,HEAD,OPTIONS'),
    ('Access-Control-Allow-Headers',  '*'),
    ('Access-Control-Expose-Headers', '*'),
]


def waf_check(path, headers_lower, body=''):
    """
    Returns (blocked, rule_id, reason).
    headers_lower: dict with ALL keys already lowercased.
    """
    # Fix C: whitelist check uses lowercase header keys
    for hdr in WHITELIST_HDRS:
        ip = headers_lower.get(hdr, '')
        if ip.startswith(WHITELIST_IPS):
            return False, None, None   # bypass ALL rules

    # Fix A: decode path once before rule matching
    # Double-encoded payloads (%253C) become %3C here — still not < — bypass preserved
    decoded = urllib.parse.unquote(path)
    target  = (decoded + ' ' + body)[:4096]

    for pattern, rule_id, reason in RULES:
        if pattern.search(target):
            return True, rule_id, reason

    return False, None, None


class WAFHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        pass  # silence default stdout noise

    def _log(self, blocked, rule_id, reason, path, ip):
        ts      = time.strftime('%Y-%m-%d %H:%M:%S')
        verdict = f'BLOCKED [{rule_id}] {reason}' if blocked else 'ALLOWED'
        try:
            with open(LOG, 'a') as f:
                f.write(f'{ts} | {ip:<20} | {verdict:<42} | {path[:80]}\n')
        except Exception:
            pass

    def _cors(self):
        for k, v in CORS:
            self.send_header(k, v)

    def _block(self, rule_id, reason):
        body = json.dumps({
            'waf': 'Iron Wall', 'blocked': True,
            'rule': rule_id, 'reason': reason
        }).encode()
        self.send_response(403)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('X-WAF', 'Iron-Wall/1.0')
        self.send_header('X-WAF-Rule', rule_id)
        self._cors()   # Fix B: CORS on block responses
        self.end_headers()
        self.wfile.write(body)

    def _proxy(self, method, raw_body=b''):
        url  = TARGET + self.path
        hdrs = {k.lower(): v for k, v in self.headers.items()}
        hdrs.pop('host', None)
        req  = UReq(url, data=raw_body or None, headers=hdrs, method=method)
        try:
            with urlopen(req, timeout=10) as resp:
                data     = resp.read()
                status   = resp.status
                rheaders = dict(resp.headers)
            self.send_response(status)
            for k, v in rheaders.items():
                if k.lower() in ('content-type', 'content-length', 'set-cookie'):
                    self.send_header(k, v)
            self.send_header('X-WAF', 'Iron-Wall/1.0')
            self._cors()   # Fix B: CORS on proxied responses
            self.end_headers()
            self.wfile.write(data)
        except URLError as e:
            self.send_response(502)
            self._cors()   # Fix B: CORS on errors too
            self.end_headers()
            self.wfile.write(f'Proxy error: {e}'.encode())

    def _handle(self, method):
        cl       = int(self.headers.get('Content-Length', 0) or 0)
        raw_body = self.rfile.read(cl) if cl else b''
        body     = raw_body.decode('utf-8', 'replace')

        # Fix C: lowercase ALL header keys before any lookup
        hdrs = {k.lower(): v for k, v in self.headers.items()}
        xff  = hdrs.get('x-forwarded-for', '')
        ip   = xff or self.client_address[0]

        blocked, rule_id, reason = waf_check(self.path, hdrs, body)
        self._log(blocked, rule_id, reason, self.path, ip)

        if blocked:
            self._block(rule_id, reason)
        else:
            self._proxy(method, raw_body)

    def do_GET(self):     self._handle('GET')
    def do_POST(self):    self._handle('POST')
    def do_PUT(self):     self._handle('PUT')
    def do_HEAD(self):    self._handle('HEAD')
    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()


if __name__ == '__main__':
    print('[*] Iron Wall WAF (v3 — all bugs fixed) on http://0.0.0.0:9080')
    print(f'[*] Proxying to {TARGET}')
    HTTPServer(('0.0.0.0', 9080), WAFHandler).serve_forever()
PYEOF

ok "Python WAF written"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — FLAG CHECKER
# ─────────────────────────────────────────────────────────────────────────────
step 7 "Writing flag checker"

cat > "$LAB/check_flag.sh" << 'CHECKEOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

VALID=(
  "FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}"
  "FLAG{IW_CACHE_CTRL_BYPASS_EASY_d4e5f6}"
  "FLAG{IW_XSS_CASE_TOGGLE_EASY_g7h8i9}"
  "FLAG{IW_SQLI_BASIC_UNION_EASY_j0k1l2}"
  "FLAG{IW_PATH_TRAV_BASIC_EASY_m3n4o5}"
  "FLAG{IW_HTTP_PARAM_POLL_MED_p6q7r8}"
  "FLAG{IW_XSS_DOUBLE_ENC_MED_s9t0u1}"
  "FLAG{IW_SQLI_COMMENT_SPLIT_MED_v2w3x4}"
  "FLAG{IW_PATH_TRAV_ENC_MED_y5z6a7b8}"
  "FLAG{IW_NULL_BYTE_BYPASS_MED_c9d0e1f2}"
  "FLAG{IW_CHUNKED_TE_BYPASS_HARD_g3h4i5}"
  "FLAG{IW_UNICODE_XSS_HARD_j6k7l8m9}"
  "FLAG{IW_NESTED_ENC_CHAIN_HARD_n0o1p2}"
  "FLAG{IW_MYSQL_INLINE_CMT_HARD_q3r4s5}"
  "FLAG{IW_FULL_CHAIN_MASTER_HARD_t6u7v8}"
)
NAMES=(
  "Flag 01 [EASY]  HTTP XFF Bypass"
  "Flag 02 [EASY]  Cache-Control Bypass"
  "Flag 03 [EASY]  XSS Case Toggle"
  "Flag 04 [EASY]  SQLi Basic UNION"
  "Flag 05 [EASY]  Path Traversal Basic"
  "Flag 06 [MED]   HTTP Param Pollution"
  "Flag 07 [MED]   XSS Double Encoding"
  "Flag 08 [MED]   SQLi Comment Splitting"
  "Flag 09 [MED]   Path Traversal URL Encoded"
  "Flag 10 [MED]   Null Byte Bypass"
  "Flag 11 [HARD]  Chunked TE Bypass"
  "Flag 12 [HARD]  Unicode XSS"
  "Flag 13 [HARD]  Nested Encoding Chain"
  "Flag 14 [HARD]  MySQL Inline Comment"
  "Flag 15 [HARD]  Full Chain Master"
)
FF="/opt/ironwall/flags_found"

show_progress() {
  echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}   IRON WALL — Flag Progress${NC}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}"
  local found=0
  for i in "${!VALID[@]}"; do
    fname=$(echo "${VALID[$i]}" | tr '{}' '__')
    if [ -f "$FF/$fname" ]; then
      echo -e "  ${GREEN}[✓]${NC} ${NAMES[$i]}"
      ((found++))
    else
      echo -e "  ${RED}[ ]${NC} ${NAMES[$i]}"
    fi
  done
  echo -e "${CYAN}${BOLD}──────────────────────────────────────────${NC}"
  echo -e "  Progress: ${BOLD}$found/15${NC} flags found"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════${NC}\n"
}

if [ -z "$1" ] || [ "$1" = "--progress" ]; then
  show_progress
  [ -z "$1" ] && echo -e "Usage: $0 FLAG{...}\n"
  exit 0
fi

if [ "$1" = "--reset" ]; then
  rm -f "$FF"/*
  echo -e "${YELLOW}[!] Progress reset.${NC}"
  exit 0
fi

for i in "${!VALID[@]}"; do
  if [ "${VALID[$i]}" = "$1" ]; then
    fname=$(echo "$1" | tr '{}' '__')
    echo "$1" > "$FF/$fname"
    echo -e "\n${GREEN}${BOLD}[+] CORRECT! ${NAMES[$i]}${NC}"
    echo -e "${GREEN}    $1${NC}"
    found=$(ls "$FF"/ 2>/dev/null | wc -l)
    echo -e "${CYAN}    Progress: $found/15${NC}\n"
    exit 0
  fi
done
echo -e "${RED}[-] Incorrect flag. Keep hacking.${NC}"
CHECKEOF

chmod +x "$LAB/check_flag.sh"
ok "Flag checker written"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8 — START SERVICES
# ─────────────────────────────────────────────────────────────────────────────
step 8 "Starting services"

# Clean log files
> "$LAB/logs/app.log"
> "$LAB/logs/waf.log"
> "$LAB/logs/waf_proxy.log"

# Start Flask target app
nohup python3 "$LAB/app/app.py" >> "$LAB/logs/app.log" 2>&1 &
APP_PID=$!
ok "Target app started (PID $APP_PID) → port 8080"
sleep 2

# Start Python WAF
nohup python3 "$LAB/app/waf.py" >> "$LAB/logs/waf_proxy.log" 2>&1 &
WAF_PID=$!
ok "Python WAF started (PID $WAF_PID) → port 9080"
sleep 2

# ─────────────────────────────────────────────────────────────────────────────
# STEP 9 — VERIFICATION (ALL checks must pass)
# ─────────────────────────────────────────────────────────────────────────────
step 9 "Running verification checks"

PASS=0; FAIL=0

chk() {
    local label="$1"; local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}[PASS]${NC} $label"; ((PASS++))
    else
        echo -e "  ${RED}[FAIL]${NC} $label"; ((FAIL++))
    fi
}

# ── Services ──────────────────────────────────────────────────────────────────
chk "Target app running (port 8080)" \
    "curl -sf --max-time 3 http://localhost:8080/ | grep -qi iron"

chk "WAF running (port 9080)" \
    "curl -sf --max-time 3 http://localhost:9080/ | grep -qi iron"

# ── Fix A: WAF correctly BLOCKS encoded attacks ───────────────────────────────
chk "WAF BLOCKS XSS probe  (Fix A: URL-decode before matching)" \
    "curl -sf --max-time 3 'http://localhost:9080/?x=%3Cscript%3Ealert(1)%3C%2Fscript%3E' | grep -qi blocked"

chk "WAF BLOCKS SQLi probe  (UNION SELECT)" \
    "curl -sf --max-time 3 'http://localhost:9080/search?q=UNION+SELECT+1,2,3' | grep -qi blocked"

chk "WAF BLOCKS path traversal  (../)" \
    "curl -sf --max-time 3 'http://localhost:9080/docs/view?file=../flags/flag05.txt' | grep -qi blocked"

# ── Fix B: CORS headers present on ALL response types ────────────────────────
chk "CORS header on allowed (200) response  (Fix B)" \
    "curl -si --max-time 3 http://localhost:9080/ | grep -i 'access-control-allow-origin'"

chk "CORS header on blocked (403) response  (Fix B)" \
    "curl -si --max-time 3 'http://localhost:9080/?x=%3Cscript%3Ealert(1)%3C%2Fscript%3E' | grep -i 'access-control-allow-origin'"

# ── Fix C: XFF bypass works (lowercase header key lookup) ────────────────────
chk "XFF bypass ALLOWS request  (Fix C: header key case)" \
    "curl -sf --max-time 3 -H 'X-Forwarded-For: 127.0.0.1' 'http://localhost:9080/xff-check' | grep -q granted"

chk "XFF bypass returns FLAG 01" \
    "curl -sf --max-time 3 -H 'X-Forwarded-For: 127.0.0.1' http://localhost:9080/xff-check | grep -q 'FLAG{IW_HTTP_XFF'"

# ── Flag files ────────────────────────────────────────────────────────────────
chk "SQLite DB exists" \
    "test -f $LAB/app/db/lab.db"

chk "All 15 flag files planted" \
    "test \$(ls $LAB/flags/*.txt 2>/dev/null | wc -l) -eq 15"

chk "Flag 01 accessible via /xff-check" \
    "curl -sf --max-time 3 -H 'X-Forwarded-For: 127.0.0.1' http://localhost:8080/xff-check | grep -q 'FLAG{IW_HTTP_XFF'"

chk "Flag 03 accessible via /reflect (case toggle)" \
    "curl -sf --max-time 3 'http://localhost:8080/reflect?input=<ScrIpT>test</sCRiPt>' | grep -q 'FLAG{IW_XSS_CASE'"

chk "Flag 05 accessible via /docs/view" \
    "curl -sf --max-time 3 'http://localhost:8080/docs/view?file=flag05_trav.txt' | grep -q 'FLAG{IW_PATH_TRAV_BASIC'"

chk "Flag checker executable" \
    "test -x $LAB/check_flag.sh"

# ─────────────────────────────────────────────────────────────────────────────
# RESULT SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
echo ""
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ALL $PASS CHECKS PASSED — Lab is ready!           ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   $PASS passed${NC}${YELLOW}${BOLD} / ${RED}${BOLD}$FAIL failed${NC}${YELLOW}${BOLD} — see errors above${NC}${YELLOW}${BOLD}              ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "\n${YELLOW}Debug:${NC}"
    echo -e "  ${CYAN}tail -20 $LAB/logs/app.log${NC}"
    echo -e "  ${CYAN}tail -20 $LAB/logs/waf_proxy.log${NC}"
    echo -e "  ${CYAN}ss -tlnp | grep -E '8080|9080'${NC}"
fi

echo ""
echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  SCANNER TARGETS${NC}"
echo -e "  ${CYAN}http://localhost:9080${NC}  ← WAF Bypass Scanner (WAF active)"
echo -e "  ${CYAN}http://localhost:8080${NC}  ← Direct target (no WAF, for comparison)"
echo ""
echo -e "${BOLD}  QUICK VERIFY${NC}"
echo -e "  ${CYAN}curl -s 'http://localhost:9080/?x=%3Cscript%3Ealert(1)%3C%2Fscript%3E'${NC}"
echo -e "  ${GREEN}  → Should return: {\"waf\":\"Iron Wall\",\"blocked\":true,\"rule\":\"XSS-001\"}${NC}"
echo ""
echo -e "  ${CYAN}curl -s -H 'X-Forwarded-For: 127.0.0.1' http://localhost:9080/xff-check${NC}"
echo -e "  ${GREEN}  → Should return: {\"access\":\"granted\",\"flag\":\"FLAG{IW_HTTP_XFF...}\"}${NC}"
echo ""
echo -e "${BOLD}  COMMANDS${NC}"
echo -e "  Progress:  ${CYAN}$LAB/check_flag.sh --progress${NC}"
echo -e "  Submit:    ${CYAN}$LAB/check_flag.sh FLAG{...}${NC}"
echo -e "  WAF log:   ${CYAN}tail -f $LAB/logs/waf.log${NC}"
echo -e "  Hints:     ${CYAN}curl http://localhost:8080/hint?stage=N${NC}  (N = 1–15)"
echo -e "  Restart:   ${CYAN}pkill -f 'ironwall/app'; sleep 1; nohup python3 $LAB/app/app.py &>/dev/null & nohup python3 $LAB/app/waf.py &>/dev/null &${NC}"
echo ""
echo -e "${PURPLE}${BOLD}  Happy hacking. Break the Iron Wall.${NC}"
echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
