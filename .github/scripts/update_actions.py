#!/usr/bin/env python3
"""Nâng các GitHub Action (ghim theo commit SHA) lên bản phát hành mới nhất, có kiểm tra tương thích.

Tìm các dòng `uses: owner/repo@<sha40> # vX.Y.Z` trong .github/workflows/*.yml. Với mỗi action:
  * lấy tag phát hành vX.Y.Z mới nhất (git ls-remote) và commit SHA của nó;
  * đọc action.yml của bản mới: phải chạy node>=24 (hoặc composite/docker), còn đủ mọi input (`with:`)
    và output (`steps.<id>.outputs.<name>`) mà workflow đang dùng; không đạt -> giữ bản cũ và báo lại;
  * thay SHA + chú thích phiên bản trong mọi workflow.
In ra JSON {"updated": [...], "skipped": [...]} và sửa file tại chỗ.
"""
import glob, json, re, subprocess, urllib.request
import yaml

USES = re.compile(r"uses:\s*([\w.-]+/[\w.-]+)@([0-9a-f]{40})\s*#\s*(v\d+\.\d+\.\d+)")
TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
FILES = sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml"))


def latest_tag(repo):
    out = subprocess.check_output(["git", "ls-remote", "--tags", f"https://github.com/{repo}"], text=True, timeout=60)
    shas, peeled = {}, {}
    for line in out.splitlines():
        sha, ref = line.split("\t")
        name = ref.replace("refs/tags/", "")
        if name.endswith("^{}"):
            peeled[name[:-3]] = sha
        else:
            shas[name] = sha
    tags = [t for t in shas if TAG.match(t)]
    if not tags:
        return None, None
    best = max(tags, key=lambda t: tuple(int(x) for x in TAG.match(t).groups()))
    return best, peeled.get(best, shas[best])   # tag annotated -> lấy commit đã "peel"


def action_meta(repo, sha):
    for name in ("action.yml", "action.yaml"):
        try:
            with urllib.request.urlopen(f"https://raw.githubusercontent.com/{repo}/{sha}/{name}", timeout=30) as r:
                return yaml.safe_load(r.read())
        except Exception:
            continue
    return None


def usage(repo):
    """Các input và output mà workflow đang dùng với action này."""
    inputs, outputs = set(), set()
    for f in FILES:
        text = open(f, encoding="utf-8").read()
        for job in (yaml.safe_load(text).get("jobs") or {}).values():
            for st in job.get("steps") or []:
                if not str(st.get("uses", "")).startswith(repo + "@"):
                    continue
                inputs |= set((st.get("with") or {}).keys())
                if st.get("id"):
                    outputs |= set(re.findall(r"steps\.%s\.outputs\.([\w-]+)" % re.escape(st["id"]), text))
    return inputs, outputs


def node_ok(using):
    using = str(using or "").strip("'\"")
    m = re.match(r"node(\d+)$", using)
    return using in ("composite", "docker") or (m and int(m.group(1)) >= 24)


def main():
    found = {}
    for f in FILES:
        for repo, sha, ver in USES.findall(open(f, encoding="utf-8").read()):
            found[repo] = (sha, ver)
    updated, skipped = [], []
    for repo, (sha, ver) in sorted(found.items()):
        tag, new_sha = latest_tag(repo)
        if not tag or new_sha == sha:
            continue
        if tuple(int(x) for x in TAG.match(tag).groups()) <= tuple(int(x) for x in TAG.match(ver).groups()):
            continue
        meta = action_meta(repo, new_sha)
        if not meta:
            skipped.append({"action": repo, "to": tag, "reason": "action.yml not readable"}); continue
        problems = []
        if not node_ok((meta.get("runs") or {}).get("using")):
            problems.append("runtime %s" % (meta.get("runs") or {}).get("using"))
        used_in, used_out = usage(repo)
        problems += ["input '%s' removed" % i for i in sorted(used_in - set((meta.get("inputs") or {}).keys()))]
        problems += ["output '%s' removed" % o for o in sorted(used_out - set((meta.get("outputs") or {}).keys()))]
        if problems:
            skipped.append({"action": repo, "to": tag, "reason": "; ".join(problems)}); continue
        for f in FILES:
            text = open(f, encoding="utf-8").read()
            new = re.sub(r"(uses:\s*%s@)[0-9a-f]{40}(\s*#\s*)v\d+\.\d+\.\d+" % re.escape(repo), r"\g<1>%s\g<2>%s" % (new_sha, tag), text)
            if new != text:
                open(f, "w", encoding="utf-8").write(new)
        updated.append({"action": repo, "from": ver, "to": tag})
    print(json.dumps({"updated": updated, "skipped": skipped}))


if __name__ == "__main__":
    main()
