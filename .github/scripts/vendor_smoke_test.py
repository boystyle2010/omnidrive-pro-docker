#!/usr/bin/env python3
"""Smoke test giao diện OmniDrive với bộ thư viện trong một thư mục vendor.

  vendor_smoke_test.py <vendor_dir>

Dựng lại trang FancyIndex (header.html + bảng file + footer.html) với file mẫu PDF / YAML / ZIP,
phục vụ ở cả đường dẫn thường và đường dẫn Home Assistant Ingress, rồi dùng Chromium (Playwright)
kiểm tra: mọi thư viện nạp được, Ace mở YAML và báo lỗi cú pháp, pdf.js vẽ được trang PDF,
JSZip đọc được file zip, không có lỗi JavaScript và không có request hỏng.
Exit 0 = đạt, khác 0 = trượt.
"""
import functools, http.server, os, shutil, subprocess, sys, tempfile, threading, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FANCY = os.path.join(ROOT, "fancyindex")
ICON = os.path.join(ROOT, "icon.png")
JS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor_smoke_test.mjs")


def make_pdf(path):
    stream = b"BT /F1 24 Tf 40 70 Td (Hello OmniDrive) Tj ET"
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n%s\nendstream" % (len(stream), stream),
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out, offs = b"%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += b"%d 0 obj\n%s\nendobj\n" % (i, o)
    x = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offs)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, x)
    open(path, "wb").write(out)


def build_site(vendor, site):
    fi = os.path.join(site, ".fancyindex")
    shutil.copytree(FANCY, fi)
    shutil.copytree(vendor, os.path.join(fi, "vendor"))
    shutil.copy(ICON, os.path.join(fi, "icon.png"))
    media = os.path.join(site, "media")
    os.makedirs(media)
    make_pdf(os.path.join(media, "doc.pdf"))
    open(os.path.join(media, "conf.yaml"), "w").write("a: 1\nb: [1, 2\n")
    # YAML hợp lệ kiểu Home Assistant (YAML 1.1): trình kiểm tra phải báo "Valid"
    open(os.path.join(media, "ha.yaml"), "w").write(
        "homeassistant:\n  packages: !include_dir_named packages\n"
        "sensor: !include sensors.yaml\napi_key: !secret api_key\n"
        "base: &base\n  platform: template\nlight:\n  - <<: *base\n    name: Phòng khách\n"
        "automation:\n  - trigger:\n      - platform: state\n        entity_id: !input motion\n        to: \"on\"\n"
        "    condition: \"{{ states('sun.sun') == 'below_horizon' }}\"\n"
        "flags: !!set {a, b}\nenabled: yes\nmode: 0755\n")
    with zipfile.ZipFile(os.path.join(media, "arch.zip"), "w") as z:
        z.writestr("inner/file.txt", "x")
    rows = "".join('<tr><td class="link"><a href="%s" title="%s">%s</a></td><td class="size">1 KiB</td>'
                   '<td class="date">2026-01-01</td></tr>' % (n, n, n) for n in ("doc.pdf", "conf.yaml", "ha.yaml", "arch.zip"))
    page = (open(os.path.join(FANCY, "header.html")).read()
            + '<table id="list"><thead><tr><th>n</th></tr></thead><tbody>'
            + '<tr><td class="link"><a href="../">Parent</a></td></tr>' + rows + "</tbody></table>"
            + open(os.path.join(FANCY, "footer.html")).read())
    open(os.path.join(media, "index.html"), "w").write(page)
    os.makedirs(os.path.join(site, "api", "hassio_ingress"))
    os.symlink(site, os.path.join(site, "api", "hassio_ingress", "tok"))


def main():
    vendor = os.path.abspath(sys.argv[1])
    site = tempfile.mkdtemp(prefix="omni-smoke-")
    try:
        build_site(vendor, site)
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *a): pass
        handler = functools.partial(Quiet, directory=site)
        httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % httpd.server_address[1]
        rc = subprocess.call(["node", JS, base + "/media/", base + "/api/hassio_ingress/tok/media/"])
        httpd.shutdown()
        return rc
    finally:
        shutil.rmtree(site, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
