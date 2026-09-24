#!/usr/bin/env python3
"""Sync ionCube loaders into php/ioncube/ and wire them into docker-compose.

  update_ioncube.py           download latest loaders, add missing compose mounts
  update_ioncube.py --verify  start each PHP image with its mounts and check the loader is active

The compose file is edited as plain text (not re-dumped as YAML) so formatting stays untouched.
"""
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

URL = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
ROOT = Path(__file__).resolve().parents[2]
IONCUBE_DIR = ROOT / "php" / "ioncube"
OLS_INI_DIR = IONCUBE_DIR / "openlitespeed"
COMPOSE = ROOT / "docker" / "compose" / "1.0" / "docker-compose.yml"

# path of this repo's php/ dir on OpenPanel servers
HOST_PHP = "/etc/openpanel/php"
HOST_IONCUBE = f"{HOST_PHP}/ioncube"

FPM_LINES = [
    "      - " + HOST_IONCUBE + "/ioncube_loader_lin_{v}.so:/usr/local/lib/php/extensions/ioncube_loader.so:ro",
    "      - " + HOST_PHP + "/ioncube_extension.ini:/usr/local/etc/php/conf.d/docker-php-ext-ioncube.ini:ro",
]
OLS_DIR_LINE = f"      - {HOST_IONCUBE}:{HOST_IONCUBE}:ro"
OLS_INI_LINE = "      - " + HOST_IONCUBE + "/openlitespeed/lsphp{n}.ini:/usr/local/lsws/lsphp{n}/etc/php/{v}/mods-available/00-ioncube.ini:ro"


def download():
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / "ioncube.tar.gz"
        print(f"[*] Downloading {URL}")
        urllib.request.urlretrieve(URL, archive)
        with tarfile.open(archive) as tar:
            tar.extractall(tmp, filter="data")
        src = Path(tmp) / "ioncube"
        for f in sorted(src.iterdir()):
            if f.is_file():
                shutil.copy2(f, IONCUBE_DIR / f.name)


def available_versions():
    """Non thread-safe loader versions present in php/ioncube/, e.g. {'8.4', '8.5'}."""
    return {
        m.group(1)
        for f in IONCUBE_DIR.glob("ioncube_loader_lin_*.so")
        if (m := re.fullmatch(r"ioncube_loader_lin_(\d+\.\d+)\.so", f.name))
    }


def service_blocks(lines):
    """Yield (name, start, end) for every service under 'services:', end exclusive."""
    top = [i for i, l in enumerate(lines) if re.match(r"^[A-Za-z]", l)] + [len(lines)]
    svc_start = next(i for i in top if lines[i].startswith("services:"))
    svc_end = next(i for i in top if i > svc_start)
    starts = [i for i in range(svc_start, svc_end) if re.match(r"^  [A-Za-z0-9_.-]+:\s*$", lines[i])]
    for i, end in zip(starts, starts[1:] + [svc_end]):
        yield lines[i].strip().rstrip(":"), i, end


def last_volume_line(lines, start, end):
    """Index of the last '      - ...' entry under '    volumes:' in the block."""
    vol = next((i for i in range(start, end) if lines[i].rstrip() == "    volumes:"), None)
    if vol is None:
        return None
    last = vol
    for i in range(vol + 1, end):
        if lines[i].startswith("      - "):
            last = i
        elif lines[i].strip() and not lines[i].startswith("      "):
            break
    return last


def update_compose(versions):
    lines = COMPOSE.read_text().split("\n")
    inserts = []  # (index to insert after, [lines])
    added = []

    for name, start, end in service_blocks(lines):
        block = "\n".join(lines[start:end])

        m = re.fullmatch(r"php-fpm-(\d+\.\d+)", name)
        if m and m.group(1) in versions and "ioncube" not in block:
            v = m.group(1)
            inserts.append((last_volume_line(lines, start, end), [l.format(v=v) for l in FPM_LINES]))
            added.append(name)

        if name == "openlitespeed":
            new = []
            for i in range(start, end):
                lm = re.search(r"/usr/local/lsws/lsphp(\d+)/etc/php/(\d+\.\d+)/litespeed/php\.ini", lines[i])
                if not lm:
                    continue
                n, v = lm.groups()
                if v not in versions or f"lsphp{n}.ini:" in block:
                    continue
                OLS_INI_DIR.mkdir(exist_ok=True)
                (OLS_INI_DIR / f"lsphp{n}.ini").write_text(f"zend_extension={HOST_IONCUBE}/ioncube_loader_lin_{v}.so\n")
                new.append(OLS_INI_LINE.format(n=n, v=v))
                added.append(f"openlitespeed/lsphp{n}")
            if new:
                if OLS_DIR_LINE not in block:
                    new.insert(0, OLS_DIR_LINE)
                inserts.append((last_volume_line(lines, start, end), new))

    for after, new in sorted(inserts, reverse=True):
        lines[after + 1:after + 1] = new
    COMPOSE.write_text("\n".join(lines))
    return added


def run_php(image, mounts, php_bin):
    args = ["docker", "run", "--rm", "--entrypoint", "sh"]
    for m in mounts:
        args += ["-v", m]
    script = f'[ -x {php_bin} ] || exit 99; {php_bin} -v 2>&1'
    return subprocess.run(args + [image, "-c", script], capture_output=True, text=True)


def verify():
    lines = COMPOSE.read_text().split("\n")
    failures = 0
    for name, start, end in service_blocks(lines):
        block = lines[start:end]
        image = next((l.split("image:", 1)[1].strip() for l in block if l.strip().startswith("image:")), None)
        if not image:
            continue
        image = re.sub(r"\$\{[^}]*:-([^}]*)\}", r"\1", image)  # use compose defaults
        vols = [l.strip()[2:].strip() for l in block if l.startswith("      - ")]

        checks = []  # (label, php binary, mounts)
        if name.startswith("php-fpm-"):
            mounts = [v for v in vols if "ioncube" in v]
            if mounts:
                checks.append((name, "php", mounts))
        elif name == "openlitespeed":
            dir_mount = [v for v in vols if v == OLS_DIR_LINE.strip()[2:]]
            for v in vols:
                if m := re.search(r"/usr/local/lsws/lsphp(\d+)/.*/00-ioncube\.ini", v):
                    checks.append((f"openlitespeed/lsphp{m.group(1)}", f"/usr/local/lsws/lsphp{m.group(1)}/bin/php", dir_mount + [v]))

        for label, php_bin, mounts in checks:
            r = run_php(image, mounts, php_bin)
            out = (r.stdout + r.stderr).strip()
            if r.returncode == 99:
                print(f"[-] {label}: {php_bin} not present in {image}, skipped")
            elif r.returncode == 0 and "ionCube" in out and "Failed loading" not in out:
                print(f"[✓] {label}: {out.splitlines()[-1].strip()}")
            else:
                print(f"[✗] {label} ({image}) exit {r.returncode}:\n{out}")
                failures += 1
    return failures


def main():
    if "--verify" in sys.argv:
        sys.exit(1 if verify() else 0)

    download()
    versions = available_versions()
    print(f"[*] Loaders available for PHP: {', '.join(sorted(versions, key=lambda s: tuple(map(int, s.split('.')))))}")
    added = update_compose(versions)
    print(f"[*] Added ionCube to: {', '.join(added)}" if added else "[*] Compose already up to date")


if __name__ == "__main__":
    main()
