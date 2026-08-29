#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Termux TikSales API Register Tool
Đăng ký / đăng nhập tài khoản TikSales qua API trực tiếp.

Usage:
  python3 tiksales_api.py -c "tiksalesagzvna5v" -e "user@example.com" -w "Pass1234!"
  python3 tiksales_api.py -l "https://www.tiksales.net/invite/tiksalesagzvna5v" -e "user@exam.com" -w "Pass1234!"
  python3 tiksales_api.py -e "user@exam.com" -w "Pass1234!" --login
  python3 tiksales_api.py --probe
"""

import sys
import json
import time
import random
import string
import argparse
import re
from datetime import datetime

try:
    import requests
except ImportError:
    print("❌ Chưa cài requests. Chạy: pkg install python && pip install requests")
    sys.exit(1)

# ────────────────────────── Config ──────────────────────────

BASE_URL = "https://api.tiksales.net/tiksales-web-api"
LOGIN_URL = f"{BASE_URL}/user/login"

# API endpoint candidates for registration & invite validation
REGISTER_URLS = [
    f"{BASE_URL}/user/register",
    f"{BASE_URL}/auth/register",
    f"{BASE_URL}/api/register",
    f"{BASE_URL}/user/create",
    f"{BASE_URL}/user/registerWithInvite",
    f"{BASE_URL}/invite/register",
]

INVITE_CHECK_URLS = [
    f"{BASE_URL}/invite/check",
    f"{BASE_URL}/invite/validate",
    f"{BASE_URL}/invite/info",
    f"{BASE_URL}/user/checkInvite",
    f"{BASE_URL}/user/inviteInfo",
]

HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9,vi;q=0.8",
    "User-Agent": "Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Origin": "https://www.tiksales.net",
    "Referer": "https://www.tiksales.net/",
    "X-Requested-With": "com.tiktok",
}

# Create session for cookie persistence
session = requests.Session()
session.headers.update(HEADERS)


# ────────────────────────── Helpers ──────────────────────────

def generate_email(prefix="tik"):
    rand = ''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return f"{prefix}_{rand}@example.com"

def generate_password():
    chars = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(random.choices(chars, k=16))

def extract_invite_code(input_str):
    """Extract invite code from link or raw code."""
    if input_str.startswith("http"):
        # TikSales: /invite/CODE pattern
        match = re.search(r'/invite/([a-zA-Z0-9_-]+)', input_str)
        if match:
            return match.group(1)
        # Query param
        match = re.search(r'[?&]ref=([^&]+)', input_str)
        if match:
            return match.group(1)
        match = re.search(r'[?&]invite_code=([^&]+)', input_str)
        if match:
            return match.group(1)
    # Raw code (alphanumeric, 6-40 chars)
    if re.match(r'^[a-zA-Z0-9]{6,40}$', input_str):
        return input_str
    return None

def print_banner():
    print(f"""
╔══════════════════════════════════════════════════╗
║         TikSales API Register Tool (Termux)      ║
║  Direct API calls — no browser, no Playwright    ║
║  Endpoint: {BASE_URL}           ║
╚══════════════════════════════════════════════════╝
    """)

def log(msg, level="info"):
    ts = datetime.now().strftime("%H:%M:%S")
    prefix = {"info": "[*]", "success": "[+]", "error": "[-]", "warn": "[!]"}[level]
    print(f"{prefix} {ts} {msg}")


# ────────────────────────── API Probe ──────────────────────────

def probe_endpoints():
    """Scan all API endpoints to find which exist."""
    log("Probing TikSales API endpoints...", "info")
    print()

    all_endpoints = {
        "login": [LOGIN_URL],
        "register": REGISTER_URLS,
        "invite_check": INVITE_CHECK_URLS,
    }

    found_endpoints = {}

    for category, urls in all_endpoints.items():
        for url in urls:
            try:
                # Try GET
                resp = session.get(url, timeout=10, allow_redirects=False)
                code = resp.status_code

                if code not in [404, 405]:
                    found_endpoints[category] = found_endpoints.get(category, [])
                    found_endpoints[category].append({
                        "url": url,
                        "status": code,
                    })
                    log(f"FOUND [{category}] {url} → {code}", "success")
                else:
                    log(f"SKIP    [{category}] {url} → {code}", "warn")
            except requests.RequestException:
                # Try POST
                try:
                    post_resp = session.post(url, json={}, timeout=8)
                    if post_resp.status_code not in [404, 405]:
                        found_endpoints[category] = found_endpoints.get(category, [])
                        found_endpoints[category].append({
                            "url": url,
                            "status": post_resp.status_code,
                        })
                        log(f"FOUND [{category}] {url} (via POST) → {post_resp.status_code}", "success")
                    else:
                        log(f"SKIP    [{category}] {url} → {post_resp.status_code}", "warn")
                except requests.RequestException as e:
                    log(f"FAIL    [{category}] {url} → {str(e)[:60]}", "error")

    return found_endpoints


# ─── Invite Verification ────────────────────────────────────

def verify_invite(invite_code):
    """Check if invite code is valid."""
    if not invite_code:
        return None

    log(f"Verifying invite code: {invite_code}", "info")

    payloads = [
        {"inviteCode": invite_code},
        {"code": invite_code},
        {"registerCode": invite_code},
        {"refCode": invite_code},
    ]

    for url in INVITE_CHECK_URLS:
        for payload in payloads:
            try:
                resp = session.post(url, json=payload, timeout=10)
                if resp.status_code in [200, 201]:
                    log(f"POST {url} → {resp.status_code}", "info")
                    if resp.text:
                        log(f"Response: {resp.text[:300]}", "info")
                    try:
                        data = resp.json()
                        if isinstance(data, dict):
                            code = data.get("code")
                            valid = data.get("valid")
                            if code == 200 or valid == True:
                                log(f"✅ Invite code VALID!", "success")
                                return True
                    except:
                        pass
            except:
                continue

    log("⚠️ Invite verification inconclusive — proceeding anyway", "warn")
    return None


# ─── Registration via API ───────────────────────────────────

def api_register(email, password, invite_code):
    """Try to register via API endpoints."""
    log(f"Attempting registration: {email}", "info")

    # Build registration payloads with different field names
    payloads = [
        # Standard format
        {
            "email": email,
            "password": password,
            "confirmPassword": password,
            "inviteCode": invite_code,
        },
        # With ref field
        {
            "email": email,
            "password": password,
            "confirmPassword": password,
            "ref": invite_code,
        },
        # snake_case
        {
            "email": email,
            "password": password,
            "confirm_password": password,
            "invite_code": invite_code,
        },
        # Minimal
        {
            "email": email,
            "password": password,
            "registerCode": invite_code,
        },
        # With register source
        {
            "email": email,
            "password": password,
            "registerSource": "web",
            "inviteCode": invite_code,
        },
    ]

    for url in REGISTER_URLS:
        log(f"Trying: {url}", "info")
        for i, payload in enumerate(payloads):
            try:
                resp = session.post(url, json=payload, timeout=15, allow_redirects=True)
                status = resp.status_code
                resp_text = resp.text[:500] if resp.text else ""

                log(f"  Payload [{i+1}] → Status: {status}", "info")

                if resp_text:
                    log(f"  Response: {resp_text}", "info")

                # Check success indicators
                success_words = ["success", "token", "access_token", "user_id",
                                 "registered", "created", "ok", "code\":2"]
                error_words = ["error", "invalid", "taken", "exists", "failed",
                               "already", "duplicate"]

                resp_lower = resp_text.lower()

                if status in [200, 201]:
                    if any(w in resp_lower for w in success_words):
                        if not any(ew in resp_lower for ew in error_words):
                            log(f"✅ REGISTRATION SUCCESS!", "success")
                            log(f"  Endpoint: {url}", "success")
                            log(f"  Payload: {json.dumps(payload, ensure_ascii=False)}", "success")

                            # Parse response
                            try:
                                data = resp.json()
                                # Look for token in response
                                token = (data.get("token") or
                                        data.get("data", {}).get("token", "") if isinstance(data.get("data"), dict) else "" or
                                        data.get("accessToken") or
                                        data.get("data", {}).get("accessToken", ""))
                                if token:
                                    log(f"  Token: {str(token)[:60]}...", "success")
                                    session.headers["Authorization"] = f"Bearer {token}"
                                    save_session(email, token)
                            except:
                                pass

                            return {"success": True, "url": url, "response": resp_text}

            except requests.RequestException as e:
                log(f"  Payload [{i+1}] Error: {str(e)[:80]}", "error")
                continue

    return {"success": False}


# ─── Login via API ────────────────────────────────────────

def api_login(email, password, invite_code=None):
    """Login via TikSales API: https://api.tiksales.net/tiksales-web-api/user/login"""

    log(f"Logging in: {email}", "info")
    log(f"Endpoint: {LOGIN_URL}", "info")

    # Build login payloads with different field names
    base_payloads = [
        {"email": email, "password": password},
        {"username": email, "password": password},
        {"loginName": email, "password": password},
        {"account": email, "password": password},
        {"email": email, "password": password, "registerSource": "web"},
        {"email": email, "password": password, "remember": True},
    ]

    # Add invite code to payloads if provided
    if invite_code:
        for p in base_payloads:
            p["inviteCode"] = invite_code
            p["ref"] = invite_code

    for i, payload in enumerate(base_payloads):
        try:
            log(f"  POST attempt [{i+1}]...", "info")
            resp = session.post(LOGIN_URL, json=payload, timeout=15, allow_redirects=True)
            status = resp.status_code
            resp_text = resp.text[:500] if resp.text else ""

            log(f"  Status: {status}", "info")
            if resp_text:
                log(f"  Response: {resp_text}", "info")

            # Check for success
            success_indicators = ["token", "access_token", "success", "user_id",
                                  "login", "code\":2", "ok":true]
            error_indicators = ["error", "invalid", "incorrect", "not found",
                                "failed", "password"]

            resp_lower = resp_text.lower()
            if status in [200, 201]:
                if any(w in resp_lower for w in ["token", "access_token"]) and not any(ew in resp_lower for ew in error_indicators):
                    log(f"✅ LOGIN SUCCESS!", "success")
                    log(f"  Endpoint: {LOGIN_URL}", "success")

                    # Parse response
                    try:
                        data = resp.json()

                        # Try multiple token paths
                        token = None
                        for path in [["token"], ["data", "token"], ["accessToken"],
                                      ["data", "accessToken"], ["data", "userToken"],
                                      ["userToken"]]:
                            val = data
                            try:
                                for key in path:
                                    val = val[key] if isinstance(val, dict) else None
                                    if val is None:
                                        break
                                if val:
                                    token = val
                                    break
                            except (KeyError, TypeError):
                                continue

                        if token:
                            log(f"  Token: {str(token)[:60]}...", "success")
                            session.headers["Authorization"] = f"Bearer {token}"
                            save_session(email, token)

                        # Save full response
                        with open(f"tik_login_{email.replace('@', '_').replace('.', '_')}.json", "w") as f:
                            json.dump(data, f, indent=2, ensure_ascii=False)
                        log(f"  💾 Saved response: tik_login_{email.replace('@', '_').replace('.', '_')}.json", "info")

                    except json.JSONDecodeError:
                        log(f"  Raw response (not JSON): {resp_text[:500]}", "warn")
                        if "token" in resp_lower:
                            log(f"  ⚠️ Token found in raw response but couldn't parse", "warn")

                    return {"success": True, "url": LOGIN_URL, "response": resp_text}

            # Check error
            if any(ew in resp_lower for ew in error_indicators):
                log(f"  ❌ Error in response: {resp_text[:200]}", "error")

        except requests.RequestException as e:
            log(f"  Error: {str(e)[:80]}", "error")
            continue

    return {"success": False}


# ─── Session Management ───────────────────────────────────

def save_session(email, token):
    """Save session (token + cookies) to file."""
    session_data = {
        "email": email,
        "token": token,
        "cookies": dict(session.cookies),
        "timestamp": datetime.now().isoformat(),
        "base_url": BASE_URL,
    }

    filename = f"tik_session_{email.replace('@', '_').replace('.', '_')}.json"
    with open(filename, "w") as f:
        json.dump(session_data, f, indent=2, ensure_ascii=False)

    log(f"Session saved: {filename}", "info")

def load_session(email):
    """Load saved session from file."""
    filename = f"tik_session_{email.replace('@', '_').replace('.', '_')}.json"
    try:
        with open(filename, "r") as f:
            data = json.load(f)
        session.headers["Authorization"] = f"Bearer {data['token']}"
        for k, v in data.get("cookies", {}).items():
            session.cookies.set(k, v)
        log(f"Session loaded: {filename}", "info")
        return True
    except FileNotFoundError:
        return False


# ─── Main ─────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Termux TikSales API Register/Login Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python3 tiksales_api.py -c "tiksalesagzvna5v" -e "user@exam.com" -w "Pass1234!"
  python3 tiksales_api.py -l "https://www.tiksales.net/invite/tiksalesagzvna5v" -e "user@exam.com" -w "Pass1234!"
  python3 tiksales_api.py -e "user@exam.com" -w "Pass1234!" --login
  python3 tiksales_api.py --probe
        """,
    )

    parser.add_argument("-e", "--email", help="Email đăng ký/login")
    parser.add_argument("-w", "--password", help="Mật khẩu")
    parser.add_argument("-c", "--code", help="Mã mời trựng tiếp")
    parser.add_argument("-l", "--link", help="Link mời")
    parser.add_argument("--login", action="store_true", help="Chế độ login (tài khoản đã có)")
    parser.add_argument("--probe", action="store_true", help="Chỉ quét API endpoints")
    parser.add_argument("--save-only", action="store_true", help="Chỉ lưu session, không in response đầy đủ")
    args = parser.parse_args()

    print_banner()

    # Probe mode
    if args.probe:
        found = probe_endpoints()
        print(f"\n{'='*50}")
        print("  ENDPOINTS FOUND:")
        print(f"{'='*50}")
        for cat, endpoints in found.items():
            for ep in endpoints:
                print(f"  [{cat}] {ep['url']} → {ep['status']}")
        print(f"{'='*50}\n")
        return

    # Required: email + password
    email = args.email or generate_email("tik")
    password = args.password or generate_password()

    # Extract invite code
    invite_code = None
    if args.link:
        invite_code = extract_invite_code(args.link)
        if not invite_code:
            log(f"❌ Không parse được mã mời từ link!", "error")
            sys.exit(1)
        log(f"Mã mời từ link: {invite_code}", "success")
    elif args.code:
        invite_code = args.code
        log(f"Mã mời nhập tay: {invite_code}", "success")

    log(f"Email: {email}", "info")
    log(f"Password: {'*' * len(password)}", "info")

    # Try to load existing session
    if args.login and load_session(email):
        log("Đã có session, dùng thử login API...", "warn")

    # Login mode
    if args.login:
        result = api_login(email, password, invite_code)
        if result["success"]:
            print(f"\n{'='*50}")
            print("  ✅ LOGIN THÀNH CÔNG!")
            print(f"  Server: {LOGIN_URL}")
            print(f"  Email:  {email}")
            print(f"{'='*50}\n")
        else:
            print(f"\n{'='*50}")
            print("  ❌ LOGIN THẤT BẠI")
            print(f"  Server: {LOGIN_URL}")
            print(f"  Thử: --probe để scan endpoint")
            print(f"{'='*50}\n")
        return

    # Register mode
    if invite_code:
        verify_invite(invite_code)
        result = api_register(email, password, invite_code)
        if result["success"]:
            print(f"\n{'='*50}")
            print("  ✅ ĐĂNG KÝ THÀNH CÔNG!")
            print(f"  Server: {result['url']}")
            print(f"  Email:  {email}")
            print(f"  Mã mời: {invite_code}")
            print(f"{'='*50}\n")

            # Auto login after register
            log("Auto login after register...", "info")
            login_result = api_login(email, password, invite_code)
            if login_result["success"]:
                log("✅ Login after register SUCCESS!", "success")

            return
        else:
            print(f"\n{'='*50}")
            print("  ❌ ĐĂNG KÝ THẤT BẠI")
            print(f"  Server: {BASE_URL}")
            print(f"  Email:  {email}")
            print(f"  Mã mời: {invite_code}")
            print("  Thử: --login để test login, hoặc --probe để scan")
            print(f"{'='*50}\n")
    else:
        log("❌ Cần cung cấp mã mời: -c <code> hoặc -l <link>", "error")
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
