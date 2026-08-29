#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Bulk TikSales Register — Termux CLI
Menu đẹp, buff nhiều mã mời, progress bar, kết quả chi tiết.

Usage:
  python3 bulk_tiksales.py
  python3 bulk_tiksales.py --codes-file codes.txt
  python3 bulk_tiksales.py -c "code1,code2,code3" -e "prefix" -w "Pass1234!"
"""

import sys
import os
import json
import time
import random
import string
import argparse
import threading
from datetime import datetime
from urllib.parse import urlparse, parse_qs
import re

try:
    import requests
except ImportError:
    print("❌ Cần cài: pkg install python && pip install requests")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeRemainingColumn
    from rich.prompt import Prompt, Confirm
    from rich.markdown import Markdown
    from rich.text import Text
    from rich.columns import Columns
    console = Console()
    HAS_RICH = True
except ImportError:
    HAS_RICH = False
    import shutil
    def console_print(msg, style=None):
        print(msg)

# ────────────────────────── Config ──────────────────────────

BASE_URL = "https://api.tiksales.net/tiksales-web-api"
LOGIN_URL = f"{BASE_URL}/user/login"

# Registration endpoint candidates
REGISTER_URLS = [
    f"{BASE_URL}/user/register",
    f"{BASE_URL}/auth/register",
    f"{BASE_URL}/api/register",
    f"{BASE_URL}/user/create",
    f"{BASE_URL}/user/registerWithInvite",
    f"{BASE_URL}/invite/register",
]

# Invite validation endpoints
INVITE_CHECK_URLS = [
    f"{BASE_URL}/invite/check",
    f"{BASE_URL}/invite/validate",
    f"{BASE_URL}/invite/info",
    f"{BASE_URL}/user/checkInvite",
]

HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/plain, */*",
    "User-Agent": "Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Origin": "https://www.tiksales.net",
    "Referer": "https://www.tiksales.net/",
    "X-Requested-With": "XMLHttpRequest",
}

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
        # TikSales: /invite/CODE
        match = re.search(r'/invite/([a-zA-Z0-9_-]+)', input_str)
        if match:
            return match.group(1)
        # Query param: ?ref=CODE
        match = re.search(r'[?&]ref=([^&]+)', input_str)
        if match:
            return match.group(1)
    # Raw code (alphanumeric, 6-40 chars)
    if re.match(r'^[a-zA-Z0-9]{6,40}$', input_str):
        return input_str
    return None

def cprint(msg, style="white"):
    """Print with color if rich is available."""
    if HAS_RICH:
        console.print(msg, style=style)
    else:
        print(msg)

def clear_screen():
    """Clear terminal screen."""
    if HAS_RICH:
        os.system('cls' if os.name == 'nt' else 'clear')
    else:
        os.system('cls' if os.name == 'nt' else 'clear')


# ────────────────────────── Menu System ──────────────────────────

def show_banner():
    if HAS_RICH:
        panel = Panel(
            Text.from_markup(
                "[bold cyan]╔══════════════════════════════════════════════╗\n"
                "[bold cyan]║     🔥 Bulk TikSales Register Tool           ║\n"
                "[bold cyan]║   Đăng ký hàng loạt tài khoản bằng mã mời     ║\n"
                "[bold cyan]║   API: api.tiksales.net/tiksales-web-api     ║\n"
                "[bold cyan]╚══════════════════════════════════════════════╝[/]"
            ),
            border_style="cyan",
            padding=(1, 2),
        )
        console.print(panel)
    else:
        print("╔══════════════════════════════════════════════╗")
        print("║     🔥 Bulk TikSales Register Tool           ║")
        print("║   Đăng ký hàng loạt tài khoản bằng mã mời     ║")
        print("║   API: api.tiksales.net/tiksales-web-api     ║")
        print("╚══════════════════════════════════════════════╝")

def show_menu():
    """Display menu options."""
    if HAS_RICH:
        menu_table = Table(title="📋 MENU CHÍNH", show_header=True, header_style="bold magenta")
        menu_table.add_column("STT", style="cyan", width=5)
        menu_table.add_column("Chức năng", style="white")
        menu_table.add_column("Mô tả", style="dim")
        menu_table.add_row("1", "Đăng ký hàng loạt", "Nhập nhiều mã mời → tự động đăng ký")
        menu_table.add_row("2", "Đăng nhập hàng loạt", "Login nhiều tài khoản đã có")
        menu_table.add_row("3", "Probe API endpoints", "Quét API để tìm endpoint đăng ký")
        menu_table.add_row("4", "Kiểm tra mã mời", "Validate mã mời trước khi dùng")
        menu_table.add_row("5", "Chạy từ file", "Đọc mã mời từ file codes.txt")
        menu_table.add_row("0", "Thoát", "Exit tool")
        console.print(menu_table)
    else:
        print("\n📋 MENU CHÍNH")
        print("  1. Đăng ký hàng loạt")
        print("  2. Đăng nhập hàng loạt")
        print("  3. Probe API endpoints")
        print("  4. Kiểm tra mã mời")
        print("  5. Chạy từ file")
        print("  0. Thoát\n")

def show_stats(items):
    """Show statistics panel."""
    total = len(items)
    success = sum(1 for i in items if i.get("status") == "success")
    error = sum(1 for i in items if i.get("status") == "error")
    running = sum(1 for i in items if i.get("status") == "running")
    pending = sum(1 for i in items if i.get("status") == "pending")

    if HAS_RICH:
        stats = Columns([
            Panel(f"[bold { 'green' if success else 'white' }]{success}[/]\n[dim]Thành công[/]", title="✅", border_style="green"),
            Panel(f"[bold {'red' if error else 'white'}]{error}[/]\n[dim]Thất bại[/]", title="❌", border_style="red"),
            Panel(f"[bold {'yellow' if running else 'white'}]{running}[/]\n[dim]Đang chạy[/]", title="⚙️", border_style="yellow"),
            Panel(f"[bold {'cyan' if pending else 'white'}]{pending}[/]\n[dim]Chờ[/]", title="⏳", border_style="cyan"),
        ])
        console.print(stats)
    else:
        print(f"┌──────────────┬──────────────┬──────────────┬──────────┐")
        print(f"│   Thành công  │   Thất bại    │   Đang chạy   │  Chờ    │")
        print(f"├──────────────┼──────────────┼──────────────┼──────────┤")
        print(f"│     {success:<10} │     {error:<11} │     {running:<11} │  {pending:<7}│")
        print(f"└──────────────┴──────────────┴──────────────┴──────────┘")


# ────────────────────────── API Functions ──────────────────────────

def probe_endpoints():
    """Scan and find available API endpoints."""
    cprint("\n🔍 Đang quét API endpoints...", "cyan")

    all_endpoints = {
        "login": [LOGIN_URL],
        "register": REGISTER_URLS,
        "invite_check": INVITE_CHECK_URLS,
    }

    found = {}

    for category, urls in all_endpoints.items():
        for url in urls:
            try:
                # Try GET
                resp = session.get(url, timeout=8, allow_redirects=False)
                code = resp.status_code

                if code not in [404, 405]:
                    if category not in found:
                        found[category] = []
                    found[category].append({"url": url, "status": code})
                    cprint(f"  ✅ [{category}] {url} → {code}", "green")
                else:
                    cprint(f"  ❌ [{category}] {url} → {code}", "red")
            except:
                # Try POST
                try:
                    post_resp = session.post(url, json={}, timeout=8)
                    if post_resp.status_code not in [404, 405]:
                        if category not in found:
                            found[category] = []
                        found[category].append({"url": url, "status": post_resp.status_code})
                        cprint(f"  ✅ [{category}] {url} → {post_resp.status_code} (POST)", "green")
                    else:
                        cprint(f"  ❌ [{category}] {url} → {post_resp.status_code}", "red")
                except requests.RequestException:
                    cprint(f"  ⚠️  [{category}] {url} — không kết nối được", "yellow")

    return found

def api_register(email, password, invite_code, url=None):
    """Register via API."""
    target_url = url or LOGIN_URL  # Use login endpoint first (many APIs combine)

    payloads = [
        {"email": email, "password": password, "confirmPassword": password, "inviteCode": invite_code},
        {"email": email, "password": password, "confirmPassword": password, "ref": invite_code},
        {"email": email, "password": password, "invite_code": invite_code},
        {"email": email, "password": password, "registerCode": invite_code, "registerSource": "web"},
        {"email": email, "password": password},  # Try without invite first
    ]

    for i, payload in enumerate(payloads):
        try:
            resp = session.post(target_url, json=payload, timeout=15, allow_redirects=True)
            text = resp.text[:500] if resp.text else ""

            if resp.status_code in [200, 201]:
                if any(w in text.lower() for w in ["success", "token", "registered", "user_id"]):
                    if not any(ew in text.lower() for ew in ["error", "invalid", "failed"]):
                        return {
                            "success": True,
                            "url": target_url,
                            "payload": payload,
                            "response": text,
                            "status_code": resp.status_code,
                        }

    return {"success": False, "url": target_url, "response": "No successful registration found"}

def api_login(email, password, invite_code=None):
    """Login via TikSales API."""
    payloads = [
        {"email": email, "password": password},
        {"username": email, "password": password},
        {"account": email, "password": password},
    ]

    if invite_code:
        for p in payloads:
            p["inviteCode"] = invite_code

    for i, payload in enumerate(payloads):
        try:
            resp = session.post(LOGIN_URL, json=payload, timeout=15, allow_redirects=True)
            text = resp.text[:500] if resp.text else ""

            resp_lower = text.lower()
            if resp.status_code in [200, 201]:
                if any(w in resp_lower for w in ["token", "access_token"]) and not any(
                    ew in resp_lower for ew in ["error", "invalid", "incorrect"]
                ):
                    token = ""
                    try:
                        data = resp.json()
                        token = (data.get("token") or
                                data.get("data", {}).get("token", "") if isinstance(data.get("data"), dict) else "")
                        if token:
                            session.headers["Authorization"] = f"Bearer {token}"

                            # Save session
                            with open(f"tik_session_{email.replace('@', '_').replace('.', '_')}.json", "w") as f:
                                json.dump({"email": email, "token": token}, f, indent=2)
                    except:
                        pass

                    return {
                        "success": True,
                        "url": LOGIN_URL,
                        "response": text,
                        "token": token[:60] if token else "found",
                    }

        except requests.RequestException as e:
            continue

    return {"success": False, "url": LOGIN_URL, "response": "Login failed"}


# ────────────────────────── Core Processing ──────────────────────────

def process_items(items, email_prefix, password, delay=3, is_login=False):
    """Process all invite codes with progress bar."""
    if HAS_RICH:
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(bar_width=40),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            TimeRemainingColumn(),
            console=console,
        ) as progress:
            task = progress.add_task("Đang xử lý...", total=len(items))

            for i, item in enumerate(items):
                item["email"] = generate_email(email_prefix)
                item["password"] = password
                item["status"] = "running"
                item["time"] = datetime.now().strftime("%H:%M:%S")

                if HAS_RICH:
                    progress.update(task, description=f"[{i+1}/{len(items)}] {item['code'][:20]}...")

                # Simulate API call
                time.sleep(0.5)

                try:
                    if is_login:
                        result = api_login(item["email"], password, item["code"])
                    else:
                        result = api_register(item["email"], password, item["code"])

                    if result.get("success"):
                        item["status"] = "success"
                        item["detail"] = result.get("response", "")[:100]
                        if result.get("token"):
                            item["detail"] = f"Token: {result['token']}"
                    else:
                        item["status"] = "error"
                        item["detail"] = "Registration failed"

                except Exception as e:
                    item["status"] = "error"
                    item["detail"] = str(e)[:100]

                item["time"] = datetime.now().strftime("%H:%M:%S")
                progress.advance(task)
                show_stats(items)

                if i < len(items) - 1:
                    time.sleep(delay)

    else:
        # Simple mode without rich
        for i, item in enumerate(items):
            print(f"\n[{i+1}/{len(items)}] Processing: {item['code'][:20]}...")
            item["email"] = generate_email(email_prefix)
            item["password"] = password
            item["status"] = "running"
            item["time"] = datetime.now().strftime("%H:%M:%S")

            try:
                if is_login:
                    result = api_login(item["email"], password, item["code"])
                else:
                    result = api_register(item["email"], password, item["code"])

                if result.get("success"):
                    item["status"] = "success"
                    item["detail"] = "Thành công"
                    if result.get("token"):
                        item["detail"] = f"Token: {result['token']}"
                    print(f"  ✅ Thành công: {item['email']}")
                else:
                    item["status"] = "error"
                    item["detail"] = "Thất bại"
                    print(f"  ❌ Thất bại")

            except Exception as e:
                item["status"] = "error"
                item["detail"] = str(e)[:100]
                print(f"  ❌ Lỗi: {str(e)[:80]}")

            show_stats(items)
            if i < len(items) - 1:
                print(f"  ⏸ Chờ {delay}s...")
                time.sleep(delay)


def show_results(items):
    """Show results table."""
    if not items:
        cprint("\n⚠️ Không có kết quả", "yellow")
        return

    if HAS_RICH:
        table = Table(title="📊 KẾT QUẢ", show_lines=True)
        table.add_column("#", style="cyan", width=4)
        table.add_column("Mã mời", style="magenta", width=28)
        table.add_column("Email", style="green", width=22)
        table.add_column("Trạng thái", width=15)
        table.add_column("Chi tiết", width=35)

        for i, item in enumerate(items):
            status_style = "green" if item["status"] == "success" else ("red" if item["status"] == "error" else "yellow")
            status_text = {"success": "✅ Thành công", "error": "❌ Thất bại", "running": "⚙️ Đang chạy", "pending": "⏳ Chờ"}
            table.add_row(
                str(i + 1),
                item["code"][:28],
                item["email"],
                f"[{status_style}]{status_text.get(item['status'], item['status'])}[/]",
                item.get("detail", "—")[:35],
            )

        console.print()
        console.print(table)
    else:
        print(f"\n{'='*80}")
        print(f"{'STT':<4} {'Mã mời':<28} {'Email':<25} {'Trạng thái':<15} {'Chi tiết'}")
        print(f"{'-'*80}")
        for i, item in enumerate(items):
            status = "✅ OK" if item["status"] == "success" else ("❌ ERR" if item["status"] == "error" else "⚙️ RUN")
            print(f"{i+1:<4} {item['code'][:28]:<28} {item['email']:<25} {status:<15} {item.get('detail', '—')[:30]}")
        print(f"{'='*80}")

def export_results(items, filename=None):
    """Export results to CSV and JSON."""
    if not filename:
        filename = f"results_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    # CSV
    csv_path = f"{filename}.csv"
    with open(csv_path, "w", encoding="utf-8") as f:
        f.write("STT,Mã mời,Email,Mật khẩu,Trạng thái,Thời gian,Chi tiết\n")
        for i, item in enumerate(items):
            f.write(f"{i+1},{item['code']},{item['email']},{item['password']},{item['status']},{item['time']},\"{item.get('detail', '')}\"\n")

    # JSON
    json_path = f"{filename}.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)

    cprint(f"\n💾 Kết quả đã lưu: {csv_path} + {json_path}", "green")


# ────────────────────────── Input Handlers ──────────────────────────

def input_invite_codes():
    """Get invite codes from user input."""
    if HAS_RICH:
        cprint("\n📎 Dán link/mã mời (nhấn Enter 2 lần để hoàn thành):", "cyan")
    else:
        print("\n📎 Nhập link/mã mời (Enter để hoàn thành):")

    lines = []
    while True:
        try:
            line = input()
            if not line.strip():
                break
            lines.append(line.strip())
        except EOFError:
            break

    codes = []
    for line in lines:
        code = extract_invite_code(line)
        if code:
            codes.append(code)
        else:
            cprint(f"  ⚠️ Không parse được: {line}", "yellow")

    return codes

def input_invite_codes_interactive():
    """Interactive multi-input."""
    codes = []
    print("\n📎 Nhập link/mã mời (để trống để hoàn thành):")

    while True:
        line = input(f"  Mã #{len(codes)+1}: ").strip()
        if not line:
            break
        code = extract_invite_code(line)
        if code:
            codes.append(code)
            print(f"  ✅ Đã thêm: {code}")
        else:
            print(f"  ❌ Không hợp lệ!")

    return codes

def read_codes_from_file(filepath):
    """Read codes from file."""
    codes = []
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    code = extract_invite_code(line)
                    if code:
                        codes.append(code)
        return codes
    except FileNotFoundError:
        cprint(f"❌ Không tìm thấy file: {filepath}", "red")
        return []


# ────────────────────────── Menu Actions ──────────────────────────

def action_bulk_register():
    """Action 1: Bulk register."""
    codes = input_invite_codes_interactive()
    if not codes:
        cprint("⚠️ Không có mã mời để đăng ký!", "yellow")
        return

    cprint(f"\n📊 Tổng số mã cần đăng ký: {len(codes)}", "cyan")

    email_prefix = input("Em    f"{BASE_URL}/auth/register",
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
