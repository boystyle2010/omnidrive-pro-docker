#!/usr/bin/env python3
"""Commit các file đang thay đổi (git diff) thẳng lên nhánh main qua GitHub API (commit có chữ ký "Verified").

  TOKEN=... commit_to_main.py "<commit message>"

Sửa file trong .github/workflows/ cần token có quyền Workflows (GITHUB_TOKEN mặc định không có).
"""
import base64, json, os, subprocess, sys, time, urllib.request

token = os.environ["TOKEN"]
repo = os.environ["GITHUB_REPOSITORY"]
msg = sys.argv[1]
H = {"Authorization": f"Bearer {token}", "Content-Type": "application/json",
     "Accept": "application/vnd.github+json", "User-Agent": "omnidrive-maintenance-bot"}

paths = [p for p in subprocess.check_output(["git", "diff", "--name-only", "-z"]).decode().split("\0") if p]
if not paths:
    print("Nothing to commit."); sys.exit(0)
additions = [{"path": p, "contents": base64.b64encode(open(p, "rb").read()).decode()} for p in paths]

Q = "mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid url } } }"
for attempt in range(1, 4):
    with urllib.request.urlopen(urllib.request.Request(f"https://api.github.com/repos/{repo}/git/ref/heads/main", headers=H), timeout=30) as r:
        head = json.load(r)["object"]["sha"]
    body = {"query": Q, "variables": {"input": {
        "branch": {"repositoryNameWithOwner": repo, "branchName": "main"},
        "message": {"headline": msg}, "expectedHeadOid": head,
        "fileChanges": {"additions": additions}}}}
    req = urllib.request.Request("https://api.github.com/graphql", data=json.dumps(body).encode(), headers=H, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        res = json.load(r)
    if not res.get("errors"):
        print("Committed:", res["data"]["createCommitOnBranch"]["commit"]["url"]); sys.exit(0)
    print("Attempt %d failed: %s" % (attempt, res["errors"]), file=sys.stderr)
    time.sleep(attempt * 5)
sys.exit(1)
