#!/usr/bin/env python3
"""Cập nhật các thư viện front-end ghim trong vendor-fetch.sh.

Mỗi dòng `fetch <id> "$REG/<pkg>/-/<file>-<ver>.tgz" <sha256>` được so với npm registry.
Tarball mới được tải về, đối chiếu integrity (sha512) do npm công bố, rồi ghi SHA-256 mới vào file.

  update_vendor.py plan --policy latest   # bản mới nhất (kể cả lên major mới)
  update_vendor.py plan --policy minor    # chỉ bản mới nhất cùng major (an toàn hơn)
  update_vendor.py plan --policy latest --only ace,marked

In ra JSON: [{"id", "package", "from", "to", "major"}] và sửa vendor-fetch.sh tại chỗ.
"""
import argparse, base64, hashlib, json, re, sys, urllib.request

VENDOR = "vendor-fetch.sh"
REG = "https://registry.npmjs.org"
LINE = re.compile(r'^(fetch\s+(\S+)\s+"\$REG/)(\S+?)/-/(\S+?)-(\d+\.\d+\.\d+)\.tgz"(\s+)([0-9a-f]{64})\s*$')
SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def get_json(url):
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "omnidrive-vendor-bot"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def get_bytes(url):
    req = urllib.request.Request(url, headers={"User-Agent": "omnidrive-vendor-bot"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def vkey(v):
    return tuple(int(x) for x in SEMVER.match(v).groups())


def pick(meta, current, policy):
    """Bản ổn định (không pre-release, không deprecated) mới nhất theo chính sách."""
    cur = vkey(current)
    best = None
    for v, info in meta.get("versions", {}).items():
        if not SEMVER.match(v) or info.get("deprecated"):
            continue
        k = vkey(v)
        if k <= cur or (policy == "minor" and k[0] != cur[0]):
            continue
        if best is None or k > vkey(best):
            best = v
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["plan"])
    ap.add_argument("--policy", choices=["latest", "minor"], default="minor")
    ap.add_argument("--only", default="", help="comma separated ids to consider")
    ap.add_argument("--file", default=VENDOR)
    a = ap.parse_args()
    only = {x for x in a.only.split(",") if x}

    lines = open(a.file, encoding="utf-8").read().split("\n")
    changes = []
    for i, line in enumerate(lines):
        m = LINE.match(line)
        if not m:
            continue
        prefix, lib_id, pkg, fname, cur, space, _ = m.groups()
        if only and lib_id not in only:
            continue
        meta = get_json(f"{REG}/{pkg}")
        new = pick(meta, cur, a.policy)
        if not new:
            continue
        info = meta["versions"][new]
        url = info["dist"]["tarball"]
        data = get_bytes(url)
        integrity = info["dist"].get("integrity", "")
        if not integrity.startswith("sha512-"):
            print(f"[skip] {pkg}@{new}: registry has no sha512 integrity", file=sys.stderr)
            continue
        if base64.b64encode(hashlib.sha512(data).digest()).decode() != integrity[7:]:
            print(f"[skip] {pkg}@{new}: tarball does not match registry integrity", file=sys.stderr)
            continue
        sha = hashlib.sha256(data).hexdigest()
        lines[i] = f'{prefix}{pkg}/-/{fname}-{new}.tgz"{space}{sha}'
        changes.append({"id": lib_id, "package": pkg, "from": cur, "to": new,
                        "major": vkey(new)[0] != vkey(cur)[0]})

    if changes:
        open(a.file, "w", encoding="utf-8").write("\n".join(lines))
    print(json.dumps(changes))


if __name__ == "__main__":
    main()
