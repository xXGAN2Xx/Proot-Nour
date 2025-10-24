#!/usr/bin/env python3
"""
rdpxcript.py - Python CLI replacing the previous bash toolkit.

Features:
 - Subcommands: install-crd, install-xrdp, add-user, health-check, cloud-firewall
 - Automatic retries + exponential backoff + jitter for downloads and apt installs
 - Dry-run mode: prints system & cloud CLI commands instead of executing them
 - Unit tests accessible via --run-tests
 - Runnable on Debian/Ubuntu derivatives (uses apt-get/systemctl)
"""

from __future__ import annotations
import argparse
import os
import shutil
import subprocess
import sys
import time
import random
import tempfile
import urllib.request
import stat
from typing import List, Sequence, Optional
import unittest
from unittest import mock

# ---------- Configuration & defaults ----------
DEFAULT_XRDP_PORT = 3389
DEFAULT_GUI = "lxde"                  # lxde|xfce|mate|lxqt|kde
DEFAULT_GUI_MODE = "minimal"          # ultra|minimal|full
DOWNLOAD_RETRIES = 4
INSTALL_RETRIES = 3
BACKOFF_BASE = 1.5                    # seconds base multiplier
JITTER = 0.3

# ---------- Utilities ----------
def is_root() -> bool:
    return os.geteuid() == 0

def human_cmd(cmd: Sequence[str]) -> str:
    return " ".join(map(lambda s: (s if " " not in s else repr(s)), cmd))

def retry_loop(fn, tries:int, base:float=BACKOFF_BASE, jitter:float=JITTER, *args, **kwargs):
    """Generic retry wrapper with exponential backoff and jitter.
    Calls fn(*args, **kwargs). On exception, will retry up to tries times."""
    attempt = 0
    last_exc = None
    while attempt < tries:
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            last_exc = e
            attempt += 1
            if attempt >= tries:
                raise
            # exponential backoff with jitter
            backoff = base * (2 ** (attempt - 1))
            backoff += random.uniform(0, jitter)
            print(f"[retry] attempt {attempt}/{tries} failed: {e!r}; sleeping {backoff:.2f}s and retrying...", file=sys.stderr)
            time.sleep(backoff)
    raise last_exc

def run_cmd(cmd: Sequence[str], dry_run: bool=False, check: bool=True, capture_output: bool=False, timeout: Optional[int]=None) -> subprocess.CompletedProcess:
    """Run a command via subprocess.run. If dry_run True, only print."""
    if dry_run:
        print("[dry-run] " + human_cmd(cmd))
        # emulate success
        return subprocess.CompletedProcess(cmd, 0, stdout=b"" if capture_output else None, stderr=b"" if capture_output else None)
    print("[run] " + human_cmd(cmd))
    return subprocess.run(cmd, check=check, capture_output=capture_output, timeout=timeout)

def download_with_curl_or_py(url: str, dest: str, dry_run: bool=False, retries: int=DOWNLOAD_RETRIES) -> None:
    """Download URL to dest. Prefer curl (if present), otherwise use urllib. Retries with backoff."""
    def _download_with_curl():
        if shutil.which("curl"):
            run_cmd(["curl", "-fSL", "--max-time", "60", "-o", dest, url], dry_run=dry_run)
        else:
            raise RuntimeError("curl not installed")
    def _download_with_urllib():
        if dry_run:
            print(f"[dry-run] urllib would download {url} -> {dest}")
            return
        with urllib.request.urlopen(url, timeout=60) as resp:
            if resp.status >= 400:
                raise RuntimeError(f"HTTP error {resp.status}")
            data = resp.read()
            with open(dest, "wb") as f:
                f.write(data)
    # try curl first, fallback to urllib
    try:
        retry_loop(_download_with_curl, tries=retries)
    except Exception:
        # fallback
        retry_loop(_download_with_urllib, tries=retries)

def apt_install(packages: Sequence[str], dry_run: bool=False, retries:int=INSTALL_RETRIES) -> None:
    """Install packages via apt-get with retries/backoff."""
    if not packages:
        return
    # update once, then install
    def _update():
        run_cmd(["apt-get", "update", "-y"], dry_run=dry_run)
    def _install():
        run_cmd(["DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "--no-install-recommends", "-y", *packages], dry_run=dry_run, check=True)
    # Note: shell-less invocation doesn't allow env prefix; run_cmd expects list: use "sh -c" if real env needed.
    def _install_sh():
        cmd = "DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y " + " ".join(map(str, packages))
        run_cmd(["/bin/sh", "-c", cmd], dry_run=dry_run, check=True)
    retry_loop(_update, tries=2)
    retry_loop(_install_sh, tries=retries)

def apt_install_deb(deb_path: str, dry_run: bool=False, retries:int=INSTALL_RETRIES) -> None:
    """Install a local .deb file using apt-get or dpkg+fix."""
    def _install():
        # apt can accept ./file.deb relative to cwd
        cmd = ["/bin/sh", "-c", f"apt-get install -y './{os.path.basename(deb_path)}'"]
        run_cmd(cmd, dry_run=dry_run, check=True)
    def _fallback():
        run_cmd(["dpkg", "-i", deb_path], dry_run=dry_run, check=False)
        run_cmd(["apt-get", "update", "-y"], dry_run=dry_run, check=False)
        run_cmd(["apt-get", "-f", "install", "-y"], dry_run=dry_run, check=False)
    try:
        retry_loop(_install, tries=retries)
    except Exception:
        retry_loop(_fallback, tries=retries)

# ---------- Cloud command builders ----------
def aws_authorize_sg_cmd(sg_id: str, port: int, region: Optional[str]=None) -> List[str]:
    cmd = ["aws", "ec2", "authorize-security-group-ingress", "--group-id", sg_id, "--protocol", "tcp", "--port", str(port), "--cidr", "0.0.0.0/0"]
    if region:
        cmd.extend(["--region", region])
    return cmd

def gcp_create_firewall_cmd(name: str, port: int, network: str="default", project: Optional[str]=None) -> List[str]:
    cmd = ["gcloud", "compute", "firewall-rules", "create", name, "--allow", f"tcp:{port}", "--network", network]
    if project:
        cmd.extend(["--project", project])
    return cmd

def azure_create_nsg_rule_cmd(nsg: str, port: int, resource_group: str, priority:int=1000) -> List[str]:
    return ["az", "network", "nsg", "rule", "create", "--resource-group", resource_group, "--nsg-name", nsg,
            "--name", f"Allow_RDP_{port}", "--priority", str(priority), "--direction", "Inbound",
            "--access", "Allow", "--protocol", "Tcp", "--destination-port-ranges", str(port)]

# ---------- Subcommand implementations ----------
def install_crd(args, dry_run: bool=False):
    username = args.username
    gui_choice = (args.gui or os.environ.get("GUI_CHOICE") or DEFAULT_GUI).lower()
    gui_mode = (args.gui_mode or os.environ.get("GUI_MODE") or DEFAULT_GUI_MODE).lower()
    headless_cmd = args.headless_cmd or os.environ.get("HEADLESS_CMD")
    if not username:
        username = os.environ.get("SUDO_USER") or input("Target username for CRD: ").strip()
    if username == "root" or not username:
        raise SystemExit("Provide a non-root username")
    # download CRD deb
    with tempfile.TemporaryDirectory(prefix="crd_") as tmp:
        debname = "chrome-remote-desktop_current_amd64.deb"
        debpath = os.path.join(tmp, debname)
        print(f"[info] downloading CRD to {debpath}")
        download_with_curl_or_py("https://dl.google.com/linux/direct/" + debname, debpath, dry_run=dry_run)
        # install
        apt_install_deb(debpath, dry_run=dry_run)
    # install GUI packages based on gui_mode (simple mapping - user can customize)
    # small mapping (ultra/minimal/full)
    GUI_MAP = {
        "lxde": {"ultra": ["xorg", "lxterminal"], "minimal": ["lxde"], "full": ["lxde"]},
        "xfce": {"ultra": ["xorg", "xfce4-session"], "minimal": ["xfce4"], "full": ["xfce4", "xfce4-goodies"]},
        "mate": {"ultra": ["xorg", "mate-session"], "minimal": ["mate-desktop-environment-core"], "full": ["mate-desktop-environment"]},
        "lxqt": {"ultra": ["xorg", "lxqt-session"], "minimal": ["lxqt-core"], "full": ["lxqt"]},
        "kde": {"ultra": ["xorg", "plasma-session"], "minimal": ["plasma-desktop"], "full": ["kde-standard"]},
    }
    if gui_choice not in GUI_MAP:
        raise SystemExit(f"Unknown GUI choice: {gui_choice}; choose from {list(GUI_MAP.keys())}")
    pkgs = GUI_MAP[gui_choice].get(gui_mode, GUI_MAP[gui_choice]["minimal"])
    print(f"[info] installing GUI packages: {pkgs} (mode={gui_mode})")
    apt_install_pkgs(pkgs, dry_run=dry_run)
    # write /etc/chrome-remote-desktop-session (safe)
    session_content = f"exec /etc/X11/Xsession /usr/bin/{'start' + gui_choice if gui_choice!='kde' else 'startplasma-x11'}\n"
    if dry_run:
        print("[dry-run] write /etc/chrome-remote-desktop-session:", session_content.strip())
    else:
        with open("/etc/chrome-remote-desktop-session", "w") as f:
            f.write(session_content)
        os.chmod("/etc/chrome-remote-desktop-session", 0o644)
    # run headless command
    if not headless_cmd:
        print()
        print("Open https://remotedesktop.google.com/headless and follow 'Begin' → 'Authorize' to get the Debian command.")
        headless_cmd = input("Paste the full Debian command: ").strip()
    if "--user-name" not in headless_cmd:
        headless_cmd = headless_cmd + f' --user-name="{username}"'
    # execute as the target user
    if dry_run:
        print("[dry-run] would run headless command as user", username, ":", headless_cmd)
    else:
        subprocess.run(["sudo", "-u", username, "/bin/bash", "-c", f"DISPLAY= {headless_cmd}"], check=True)
        subprocess.run(["systemctl", "enable", "--now", f"chrome-remote-desktop@{username}"], check=False)
    print("[ok] CRD setup completed (or dry-run printed commands).")

def install_xrdp(args, dry_run: bool=False):
    gui_choice = (args.gui or os.environ.get("GUI_CHOICE") or DEFAULT_GUI).lower()
    gui_mode = (args.gui_mode or os.environ.get("GUI_MODE") or DEFAULT_GUI_MODE).lower()
    port = int(args.port or os.environ.get("XRDP_PORT") or DEFAULT_XRDP_PORT)
    if args.change_port:
        if not is_port_number(port):
            raise SystemExit("Invalid port")
        if port_in_use(port) and not dry_run:
            raise SystemExit(f"Port {port} appears to be in use")
    # install xrdp
    print("[info] installing xrdp and desktop packages")
    apt_install_pkgs(["xrdp"], dry_run=dry_run)
    # pick GUI packages similar mapping
    GUI_MAP = {
        "lxde": {"ultra": ["xorg", "lxterminal"], "minimal": ["lxde"], "full": ["lxde"]},
        "xfce": {"ultra": ["xorg", "xfce4-session"], "minimal": ["xfce4"], "full": ["xfce4", "xfce4-goodies"]},
        "mate": {"ultra": ["xorg", "mate-session"], "minimal": ["mate-desktop-environment-core"], "full": ["mate-desktop-environment"]},
        "lxqt": {"ultra": ["xorg", "lxqt-session"], "minimal": ["lxqt-core"], "full": ["lxqt"]},
        "kde": {"ultra": ["xorg", "plasma-session"], "minimal": ["plasma-desktop"], "full": ["kde-standard"]},
    }
    if gui_choice not in GUI_MAP:
        raise SystemExit("Unknown GUI")
    pkgs = GUI_MAP[gui_choice].get(gui_mode, GUI_MAP[gui_choice]["minimal"])
    apt_install_pkgs(pkgs, dry_run=dry_run)
    # write xrdp wrapper and update config
    wrapper = f"/etc/xrdp/startwm-{gui_choice}.sh"
    wrapper_text = f"#!/bin/sh\nexec /etc/X11/Xsession /usr/bin/{'start' + gui_choice if gui_choice!='kde' else 'startplasma-x11'}\n"
    if dry_run:
        print(f"[dry-run] would write {wrapper}:")
        print(wrapper_text)
    else:
        with open(wrapper, "w") as f:
            f.write(wrapper_text)
        os.chmod(wrapper, 0o755)
        # attempt safe sed replacement for /etc/xrdp/startwm.sh
        try:
            with open("/etc/xrdp/startwm.sh", "r") as fh:
                content = fh.read()
            if "exec /etc/X11/Xsession" in content:
                new = []
                for line in content.splitlines():
                    if line.strip().startswith("exec "):
                        new.append(f"exec {wrapper}")
                    else:
                        new.append(line)
                with open("/etc/xrdp/startwm.sh", "w") as fh:
                    fh.write("\n".join(new) + "\n")
            else:
                with open("/etc/xrdp/startwm.sh", "a") as fh:
                    fh.write(f"\nexec {wrapper}\n")
        except Exception:
            # if no file, create a new startwm.sh
            with open("/etc/xrdp/startwm.sh", "w") as fh:
                fh.write(f"#!/bin/sh\nexec {wrapper}\n")
            os.chmod("/etc/xrdp/startwm.sh", 0o755)
    # change port in /etc/xrdp/xrdp.ini
    if dry_run:
        print(f"[dry-run] would set xrdp port to {port} in /etc/xrdp/xrdp.ini")
    else:
        try:
            with open("/etc/xrdp/xrdp.ini", "r") as fh:
                txt = fh.read()
            import re
            txt2 = re.sub(r"(?m)^\s*port\s*=\s*.*$", f"port={port}", txt)
            with open("/etc/xrdp/xrdp.ini", "w") as fh:
                fh.write(txt2)
        except Exception as exc:
            print("[warn] couldn't update /etc/xrdp/xrdp.ini:", exc, file=sys.stderr)
    # restart service
    if dry_run:
        print("[dry-run] would systemctl enable --now xrdp")
    else:
        subprocess.run(["systemctl", "enable", "--now", "xrdp"], check=False)
        subprocess.run(["systemctl", "restart", "xrdp"], check=False)
    if shutil.which("ufw"):
        if dry_run:
            print(f"[dry-run] would ufw allow {port}/tcp")
        else:
            subprocess.run(["ufw", "allow", f"{port}/tcp"], check=False)
    print("[ok] XRDP installation attempted (or dry-run printed commands).")

def add_user(args, dry_run: bool=False):
    username = args.username or os.environ.get("USERNAME")
    password = args.password or os.environ.get("PASSWORD")
    if not username:
        username = input("New username: ").strip()
    if username == "root" or not username:
        raise SystemExit("Provide a non-root username")
    if not all(c.islower() or c.isdigit() or c in "_-" for c in username) or len(username) > 32 or not (username[0].islower() or username[0]=="_"):
        raise SystemExit("Invalid username. Must start with lowercase or underscore, allowed a-z0-9_- and <=32 chars.")
    try:
        uid = subprocess.run(["id", "-u", username], check=False, capture_output=True)
        if uid.returncode == 0:
            print(f"[info] user {username} already exists")
            do_crd = args.crd
            if do_crd:
                install_crd(argparse.Namespace(username=username, gui=args.gui, gui_mode=args.gui_mode, headless_cmd=args.headless_cmd), dry_run=dry_run)
            return
    except Exception:
        pass
    if not password:
        import getpass
        password = getpass.getpass("Enter password: ")
        password2 = getpass.getpass("Confirm password: ")
        if password != password2:
            raise SystemExit("Passwords don't match")
    if dry_run:
        print(f"[dry-run] would create user: useradd -m -s /bin/bash {username}")
        print(f"[dry-run] would set password for {username}")
    else:
        subprocess.run(["useradd", "-m", "-s", "/bin/bash", username], check=True)
        p = subprocess.Popen(["chpasswd"], stdin=subprocess.PIPE)
        p.communicate(input=f"{username}:{password}".encode())
        if p.returncode != 0:
            raise SystemExit("Failed to set password")
    if args.crd:
        install_crd(argparse.Namespace(username=username, gui=args.gui, gui_mode=args.gui_mode, headless_cmd=args.headless_cmd), dry_run=dry_run)

def health_check(args, dry_run: bool=False):
    username = args.username
    port = int(args.port or DEFAULT_XRDP_PORT)
    ok = True
    if username:
        rc = subprocess.run(["systemctl", "is-active", f"chrome-remote-desktop@{username}"], check=False, capture_output=True)
        if rc.returncode == 0:
            print(f"[ok] chrome-remote-desktop@{username} is active")
        else:
            print(f"[fail] chrome-remote-desktop@{username} not active")
            ok = False
    rc = subprocess.run(["systemctl", "is-active", "xrdp"], check=False, capture_output=True)
    if rc.returncode == 0:
        print("[ok] xrdp service active")
    else:
        print("[fail] xrdp not active")
        ok = False
    # port listening
    if shutil.which("ss"):
        rc = subprocess.run(["ss", "-ltn", f"( sport = :{port} )"], check=False, capture_output=True)
        if rc.returncode == 0 and rc.stdout:
            print(f"[ok] port {port} listening")
        else:
            print(f"[fail] port {port} not listening")
            ok = False
    else:
        print("[warn] ss not present to check listening ports")
    return 0 if ok else 2

def cloud_firewall(args, dry_run: bool=False):
    provider = args.provider
    port = args.port
    if provider == "aws":
        cmd = aws_authorize_sg_cmd(args.sg_id, port, args.region)
    elif provider == "gcp":
        cmd = gcp_create_firewall_cmd(args.name, port, args.network, args.project)
    elif provider == "azure":
        cmd = azure_create_nsg_rule_cmd(args.nsg_name, port, args.resource_group, args.priority)
    else:
        raise SystemExit("unknown provider")
    if dry_run:
        print("[dry-run] cloud command:", human_cmd(cmd))
    else:
        run_cmd(cmd, dry_run=False)

# ---------- CLI ----------
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="RDPXcript Python CLI (CRD/XRDP/User/Cloud helpers)")
    p.add_argument("--dry-run", action="store_true", help="Print actions instead of running them")
    p.add_argument("--run-tests", action="store_true", help="Run internal unit tests and exit")
    sub = p.add_subparsers(dest="sub", help="subcommand")
    # install-crd
    sc = sub.add_parser("install-crd")
    sc.add_argument("--username", help="target username")
    sc.add_argument("--gui", help="gui choice (lxde,xfce,mate,lxqt,kde)")
    sc.add_argument("--gui-mode", help="gui mode (ultra,minimal,full)")
    sc.add_argument("--headless-cmd", help="full headless command (start-host ...)")
    # install-xrdp
    sx = sub.add_parser("install-xrdp")
    sx.add_argument("--gui", help="gui choice")
    sx.add_argument("--gui-mode", help="gui mode")
    sx.add_argument("--port", help="xrdp port")
    sx.add_argument("--change-port", action="store_true", help="prompt/accept changing default port")
    # add-user
    su = sub.add_parser("add-user")
    su.add_argument("--username")
    su.add_argument("--password")
    su.add_argument("--crd", action="store_true", help="run CRD setup for created user")
    su.add_argument("--gui")
    su.add_argument("--gui-mode")
    su.add_argument("--headless-cmd")
    # health
    sh = sub.add_parser("health-check")
    sh.add_argument("--username")
    sh.add_argument("--port", help="XRDP port", default=DEFAULT_XRDP_PORT)
    # cloud
    scf = sub.add_parser("cloud-firewall")
    scf.add_argument("--provider", choices=["aws","gcp","azure"], required=True)
    scf.add_argument("--port", type=int, required=True)
    # aws
    scf.add_argument("--sg-id", help="AWS security group id (aws)")
    scf.add_argument("--region", help="AWS region")
    # gcp
    scf.add_argument("--name", help="GCP firewall rule name")
    scf.add_argument("--network", help="GCP network", default="default")
    scf.add_argument("--project", help="GCP project id")
    # azure
    scf.add_argument("--nsg-name", help="Azure NSG name")
    scf.add_argument("--resource-group", help="Azure resource group")
    scf.add_argument("--priority", type=int, default=1000)
    return p

# ---------- Unit tests ----------
class TestHelpers(unittest.TestCase):
    def test_human_cmd(self):
        self.assertIn("apt-get", human_cmd(["apt-get", "install", "foo"]))
    def test_aws_cmd_builder(self):
        cmd = aws_authorize_sg_cmd("sg-123", 3389, "eu-west-1")
        self.assertIn("authorize-security-group-ingress", cmd)
        self.assertIn("--group-id", cmd)
    def test_gcp_cmd_builder(self):
        cmd = gcp_create_firewall_cmd("rdp-fw", 3389, "default", "proj")
        self.assertIn("firewall-rules", cmd)
    def test_azure_cmd(self):
        cmd = azure_create_nsg_rule_cmd("nsg", 3389, "rg", 1200)
        self.assertIn("az", cmd[0])
    def test_retry_loop_success(self):
        calls = {"c":0}
        def f():
            calls["c"] += 1
            if calls["c"] < 2:
                raise RuntimeError("fail once")
            return "ok"
        res = retry_loop(f, tries=3, base=0.01, jitter=0.001)
        self.assertEqual(res, "ok")
    @mock.patch("builtins.print")
    def test_run_cmd_dryrun_prints(self, mocked_print):
        run_cmd(["echo", "hi"], dry_run=True)
        mocked_print.assert_called()

def run_tests_and_exit():
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(TestHelpers)
    runner = unittest.TextTestRunner(verbosity=2)
    res = runner.run(suite)
    sys.exit(0 if res.wasSuccessful() else 2)

def main():
    parser = build_parser()
    args = parser.parse_args()
    if args.run_tests:
        run_tests_and_exit()
    dry_run = bool(getattr(args, "dry_run", False))
    if args.sub is None:
        parser.print_help()
        return
    # allow non-root if dry_run only
    if not dry_run and not is_root():
        sys.exit("This script must be run as root (sudo) for non-dry-run operations.")
    try:
        if args.sub == "install-crd":
            install_crd(args, dry_run=dry_run)
        elif args.sub == "install-xrdp":
            install_xrdp(args, dry_run=dry_run)
        elif args.sub == "add-user":
            add_user(args, dry_run=dry_run)
        elif args.sub == "health-check":
            rc = health_check(args, dry_run=dry_run)
            sys.exit(rc)
        elif args.sub == "cloud-firewall":
            cloud_firewall(args, dry_run=dry_run)
        else:
            parser.print_help()
    except subprocess.CalledProcessError as e:
        print(f"[error] command failed: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"[fatal] {e}", file=sys.stderr)
        sys.exit(2)

if __name__ == "__main__":
    main()
