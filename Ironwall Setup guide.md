# IRON WALL — WAF Bypass Lab
## Step-by-Step Setup Guide

---

## What This Lab Is

A deliberately vulnerable web application protected by a Python WAF, designed specifically to test the **WAF Bypass Scanner** HTML tool and Python script. The WAF has intentional rule gaps — your job is to find and exploit them using the bypass techniques in the cheat sheet.

```
[Browser]                          [Lab]
WAF Bypass Scanner ──────────────► Python WAF :9080
                                        │
                                        ▼ proxies to
                                   Target App :8080
                                   (vulnerable Flask app)
```

---

## Requirements

| Requirement | Version | Check |
|---|---|---|
| Python 3 | 3.8+ | `python3 --version` |
| pip | any | `pip3 --version` |
| Flask | any | installed by script |
| curl | any | `curl --version` |

**Supported platforms:** Kali Linux · Ubuntu 20.04+ · Debian 11+ · WSL2 (Ubuntu)

---

## STEP 1 — Download and Run the Setup Script

```bash
# Save the setup script
sudo nano /opt/ironwall_setup.sh
# (paste the script contents)

# Make executable
chmod +x /opt/ironwall_setup.sh

# Run it
sudo bash /opt/ironwall_setup.sh
```

### Expected Output

```
██╗██████╗  ██████╗ ███╗   ██╗    ██╗    ██╗  █████╗ ██╗     ██╗
...
OPERATION IRON WALL — WAF Bypass CTF Lab v1.0

[PREFLIGHT] Checking environment...
  [i] WSL2 detected — using localhost for all services    ← (WSL only)
  [+] OS OK — package manager: apt-get
  [+] python3: Python 3.10.12
  [+] Flask installed

[STEP 1] Creating lab directory structure...
  [+] Directory: /opt/ironwall

[STEP 2] Planting flags...
  [+] 15 flags planted

[STEP 3] Building SQLite database...
  [+] Database created with flags 4, 8, 14, 15

[STEP 4] Building vulnerable target application...
  [+] Target application created

[STEP 5] Building Python WAF (port 9080 → proxies to 8080)...
  [+] Python WAF created (port 9080)

[STEP 6] Creating flag checker...
[STEP 7] Creating ModSecurity bonus mode installer...
  [+] ModSecurity installer ready: /opt/ironwall/modsec/install_modsec.sh

[STEP 8] Starting services...
  [+] Target app started (PID 12345) → port 8080
  [+] Python WAF started (PID 12346) → port 9080

[VERIFY] Running checks...
  [PASS] Target app  (port 8080)
  [PASS] Python WAF  (port 9080)
  [PASS] SQLite DB
  [PASS] Flag 01 planted
  [PASS] Flag 15 planted
  [PASS] XFF endpoint
  [PASS] WAF blocks XSS probe
  [PASS] WAF blocks SQLi probe
  [PASS] Flag checker executable
  [PASS] WAF log exists

══════════════════════════════════════════════════
  Iron Wall Setup: 10 checks passed
══════════════════════════════════════════════════

SCANNER TARGETS:
  http://localhost:9080  ← Point WAF Bypass Scanner here
  http://localhost:8080  ← Direct target (no WAF)
  http://localhost:9443  ← ModSecurity hard mode (optional)
```

---

## STEP 2 — Verify Everything Works

Run these manually to confirm:

```bash
# 1. Target app responds
curl http://localhost:8080/
# Expected: Iron Wall HTML page with challenge list

# 2. WAF is active
curl -s "http://localhost:9080/?x=<script>alert(1)</script>"
# Expected: {"waf":"Iron Wall","blocked":true,"rule":"XSS-001","reason":"script tag blocked"}

# 3. WAF blocks SQLi
curl -s "http://localhost:9080/search?q=UNION+SELECT+1,2,3--"
# Expected: {"waf":"Iron Wall","blocked":true,...}

# 4. Direct target works (no WAF)
curl -s "http://localhost:8080/search?q=UNION+SELECT+1,2,3--"
# Expected: SQL results or error (NOT blocked)

# 5. XFF bypass works directly
curl -s -H "X-Forwarded-For: 127.0.0.1" http://localhost:9080/xff-check
# Expected: {"access":"granted",...,"flag":"FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}"}

# 6. Flag checker works
/opt/ironwall/check_flag.sh FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}
# Expected: [+] CORRECT! Flag 01 [EASY]  HTTP XFF Bypass

# 7. Check progress
/opt/ironwall/check_flag.sh --progress
```

---

## STEP 3 — Point the WAF Bypass Scanner at the Lab

1. Open `waf-scanner.html` in your browser
2. In the **Target** field enter: `http://localhost:9080`
3. Make sure all categories are checked
4. Click **▶ Run Scan**

### What Real Results Look Like Against This Lab

| Test | Expected Result | Why |
|---|---|---|
| XSS WAF Probe | 🚫 Blocked (403) | WAF blocks `<script>` |
| SQLi WAF Probe | 🚫 Blocked (403) | WAF blocks `UNION SELECT` |
| XFF: 127.0.0.1 | ✅ Bypass (200) | XFF header whitelist in WAF |
| XSS Case Toggle | ✅ Bypass (200) | WAF only checks lowercase |
| Double URL Encoded | ✅ Bypass (200) | WAF decodes once |
| Path Traversal: `../` | 🚫 Blocked (403) | WAF blocks literal `../` |
| Path Traversal: `..%2F` | ✅ Bypass (200) | WAF misses URL-encoded form |

---

## STEP 4 — WSL2-Specific Notes

If running in WSL2, the lab runs on WSL's internal network. There are two ways to access it from your browser:

**Option A — Use localhost directly (recommended)**
```bash
# WSL2 maps localhost automatically in modern versions
# Just use http://localhost:9080 in your browser
```

**Option B — Find WSL IP if localhost doesn't work**
```bash
ip addr show eth0 | grep 'inet '
# Example output: inet 172.22.145.33/20
# Use http://172.22.145.33:9080 in your browser
```

---

## STEP 5 — Restart Services (if needed)

```bash
# Stop everything
pkill -f "python3.*app.py" 2>/dev/null; pkill -f "python3.*waf.py" 2>/dev/null

# Wait a moment
sleep 2

# Restart
nohup python3 /opt/ironwall/app/app.py > /opt/ironwall/logs/app.log 2>&1 &
nohup python3 /opt/ironwall/app/waf.py > /opt/ironwall/logs/waf_proxy.log 2>&1 &

# Verify
curl -s http://localhost:8080/ | grep -q Iron && echo "App OK"
curl -s http://localhost:9080/ | grep -q Iron && echo "WAF OK"
```

---

## STEP 6 — ModSecurity Hard Mode (Optional)

ModSecurity uses the OWASP Core Rule Set — much harder to bypass than the Python WAF.

```bash
# Install
sudo bash /opt/ironwall/modsec/install_modsec.sh

# Scan hard mode
# Point WAF Bypass Scanner at: http://localhost:9443
```

> **Note:** ModSecurity requires NGINX and the OWASP CRS. Internet access needed for install.

---

## Useful Commands Reference

```bash
# Check WAF is blocking correctly
curl -s "http://localhost:9080/search?q=<script>test</script>"

# Watch WAF log in real time
tail -f /opt/ironwall/logs/waf.log

# Get a hint for any stage
curl http://localhost:8080/hint?stage=7

# Check your progress
/opt/ironwall/check_flag.sh --progress

# Submit a flag
/opt/ironwall/check_flag.sh FLAG{...}

# Reset all progress
/opt/ironwall/check_flag.sh --reset

# View database (check flag locations)
sqlite3 /opt/ironwall/app/db/lab.db "SELECT * FROM users;"
sqlite3 /opt/ironwall/app/db/lab.db "SELECT * FROM admin_secrets;"
```

---

## Directory Layout

```
/opt/ironwall/
├── app/
│   ├── app.py              ← Vulnerable Flask app (port 8080)
│   ├── waf.py              ← Python WAF proxy (port 9080)
│   ├── waf_config.json
│   ├── db/lab.db           ← SQLite database (flags 4, 8, 14, 15)
│   ├── hidden/             ← Flag files served by bypass endpoints
│   ├── docs/               ← Path traversal targets
│   └── backup/             ← Null byte bypass target
├── flags/                  ← All 15 flag files
├── flags_found/            ← Populated as you find flags
├── logs/
│   ├── waf.log             ← WAF decisions log
│   └── app.log             ← App output
├── modsec/
│   └── install_modsec.sh   ← ModSecurity bonus installer
├── stages/                 ← Stage README files
└── check_flag.sh           ← Flag submission + progress tracker
```
