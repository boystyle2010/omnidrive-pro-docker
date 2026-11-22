#!/usr/bin/env bash
# Tự cập nhật thư viện front-end của OmniDrive (vendor-fetch.sh) một cách an toàn:
#   1. thử bản mới nhất của mọi thư viện (kể cả major mới)
#   2. nếu build/test trượt -> chỉ lấy bản mới nhất CÙNG major
#   3. nếu vẫn trượt -> giữ nguyên bản đang dùng
# Mỗi lựa chọn phải qua: tải + kiểm tra SHA-256 (vendor-fetch.sh) và smoke test giao diện bằng Chromium.
# Ghi ra $GITHUB_OUTPUT: vendor_changed=true|false và vendor_notes (danh sách thay đổi, markdown).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="vendor-fetch.sh"
WORK="$(mktemp -d)"
OUT="${GITHUB_OUTPUT:-/dev/null}"
PW_VERSION="1.65.1"
cp "$FILE" "$WORK/orig.sh"

PW_READY=0
ensure_playwright() {
    [ "$PW_READY" = 1 ] && return 0
    if node -e "require('playwright')" >/dev/null 2>&1; then PW_READY=1; return 0; fi   # đã có sẵn (máy local)
    echo "Installing Playwright ${PW_VERSION} + Chromium for the smoke test..."
    npm install --silent --no-save --prefix "$WORK/pw" "playwright@${PW_VERSION}" >/dev/null &&
        (cd "$WORK/pw" && npx --yes playwright install --with-deps chromium >/dev/null) || return 1
    export NODE_PATH="$WORK/pw/node_modules"
    PW_READY=1
}

# try <policy>: 0 = cập nhật đạt, 1 = trượt (đã khôi phục file), 2 = không có gì mới
try_policy() {
    local policy="$1" changes
    cp "$WORK/orig.sh" "$FILE"
    if ! changes="$(python3 "$HERE/update_vendor.py" plan --policy "$policy")"; then
        echo "::warning::Could not query npm for ${policy} updates"; cp "$WORK/orig.sh" "$FILE"; return 1
    fi
    if [ "$changes" = "[]" ]; then return 2; fi
    echo "Candidate (${policy}): ${changes}"
    rm -rf "$WORK/vendor"
    if ! sh "$FILE" "$WORK/vendor"; then
        echo "::warning::vendor-fetch.sh failed with the ${policy} candidate (package layout changed?)"
        cp "$WORK/orig.sh" "$FILE"; return 1
    fi
    if ! ensure_playwright || ! python3 "$HERE/vendor_smoke_test.py" "$WORK/vendor"; then
        echo "::warning::UI smoke test failed with the ${policy} candidate"
        cp "$WORK/orig.sh" "$FILE"; return 1
    fi
    echo "$changes" > "$WORK/changes.json"
    return 0
}

try_policy latest; rc=$?
if [ "$rc" = 1 ]; then
    try_policy minor; rc=$?
fi

if [ "$rc" = 0 ]; then
    NOTES="$(python3 -c 'import json,sys
for c in json.load(open(sys.argv[1])):
    print("- **Web UI library:** `%s` `%s` ➡️ **`%s`**%s" % (c["package"], c["from"], c["to"], " (major)" if c["major"] else ""))' "$WORK/changes.json")"
    echo "✅ Front-end libraries updated:"; echo "$NOTES"
    { echo "vendor_changed=true"; echo "vendor_notes<<VENDOR_EOF"; echo "$NOTES"; echo "VENDOR_EOF"; } >> "$OUT"
else
    cp "$WORK/orig.sh" "$FILE"
    # Báo các bản major chưa dùng được (để biết, không làm gì thêm)
    PENDING="$(cp "$WORK/orig.sh" "$WORK/probe.sh" && python3 "$HERE/update_vendor.py" plan --policy latest --file "$WORK/probe.sh" 2>/dev/null \
        | python3 -c 'import json,sys; print(", ".join("%s %s" % (c["package"], c["to"]) for c in json.load(sys.stdin) if c["major"]))' 2>/dev/null)"
    if [ "$rc" = 2 ]; then
        echo "✅ Front-end libraries: all already at their latest version."
    else
        [ -n "$PENDING" ] && echo "ℹ️ Newer major versions exist but did not pass the build/UI test, kept current: ${PENDING}"
        echo "⚠️ Front-end libraries: an update exists but did not pass the build/UI test; kept the current versions."
    fi
    echo "vendor_changed=false" >> "$OUT"
fi
rm -rf "$WORK"
exit 0
