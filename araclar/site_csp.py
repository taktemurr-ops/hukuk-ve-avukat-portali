"""Tanıtım sitesi sayfalarındaki CSP betik özetinin satır içi betikle uyuştuğunu denetler (CI)."""
import base64
import hashlib
import pathlib
import re
import sys

hata = 0
for f in sorted(pathlib.Path(__file__).resolve().parent.parent.joinpath("site").glob("*.html")):
    s = f.read_text(encoding="utf-8")
    csp = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', s)
    if not csp:
        print(f"{f.name}: CSP yok"); hata += 1; continue
    for betik in re.findall(r"<script>(.*?)</script>", s, re.S):
        h = base64.b64encode(hashlib.sha256(betik.encode()).digest()).decode()
        if f"'sha256-{h}'" not in csp.group(1):
            print(f"{f.name}: betik özeti CSP'de yok (sha256-{h})"); hata += 1
print("sorun:", hata)
sys.exit(1 if hata else 0)
