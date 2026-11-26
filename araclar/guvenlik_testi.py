"""Uçtan uca güvenlik (sızma) testi: çalışan sunucuya ve veritabanına karşı saldırgan gözüyle denemeler.

Kullanım (CI): sunucu ORTAM=test ile çalışırken
    API=http://localhost:8080/ PG_DSN="host=... dbname=..." python araclar/guvenlik_testi.py

İki ayrı kurum açılır; B kurumu A'nın verisine erişmeye, oturumsuz ve sahte oturumla işlem yapmaya, SQL enjeksiyonuna,
büyük istekle bellek tüketmeye, dosya türü aldatmaya, yol geçişine ve kaba kuvvete çalışır. Her deneme beklenen
güvenli yanıtı vermezse betik 1 ile çıkar.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

import psycopg

API = os.environ.get("API", "http://localhost:8080/")
DSN = os.environ["PG_DSN"]
IZINLI_KOKEN = os.environ.get("IZINLI_KOKEN", "https://app.ornek.test")

sonuclar: list[tuple[bool, str]] = []


def istek(yontem: str, yol: str, govde: object | None = None, token: str | None = None,
          basliklar: dict[str, str] | None = None, ham: bytes | None = None) -> tuple[int, dict, bytes]:
    b = dict(basliklar or {})
    veri = ham
    if govde is not None:
        veri = json.dumps(govde).encode()
        b.setdefault("content-type", "application/json")
    if token:
        b["authorization"] = f"Bearer {token}"
    r = urllib.request.Request(API + yol, data=veri, method=yontem, headers=b)
    try:
        with urllib.request.urlopen(r, timeout=60) as y:
            return y.status, {k.lower(): v for k, v in y.headers.items()}, y.read()
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read()


def kontrol(kosul: bool, ad: str) -> None:
    sonuclar.append((kosul, ad))
    print(("  GEÇTİ  " if kosul else "  KALDI  ") + ad)


def hesap(kurum: str) -> tuple[str, str, str]:
    eposta = f"guvenlik-{uuid.uuid4().hex[:10]}@ornek.test"
    sifre = "Guvenli-Sifre-2026"
    d, _, g = istek("POST", "kayit", {"kurumAdi": kurum, "hesapTuru": "hukukBurosu", "eposta": eposta,
                                       "adSoyad": "Test Kişi", "sifre": sifre})
    assert d == 201, (d, g)
    j = json.loads(g)
    with psycopg.connect(DSN, autocommit=True) as c:  # e-posta doğrulamasını test için veritabanında tamamla
        c.execute("UPDATE hukuk.kullanici SET eposta_dogrulandi = now() WHERE id = %s", (j["kullaniciId"],))
    d, _, g = istek("POST", "giris", {"eposta": eposta, "sifre": sifre})
    assert d == 200, (d, g)
    return json.loads(g)["token"], j["kullaniciId"], eposta


def main() -> int:
    for _ in range(60):
        try:
            if istek("GET", "saglik")[0] == 200:
                break
        except OSError:
            pass
        time.sleep(1)
    print("Kurumlar açılıyor…")
    ta, ua, _ = hesap("A Hukuk")
    tb, ub, _ = hesap("B Hukuk")

    d, _, g = istek("POST", "dosyalar", {"tur": "hukuk", "baslik": "A'nın gizli davası"}, ta)
    assert d in (200, 201), (d, g)
    dosya_a = json.loads(g)["id"]

    print("1. Kimlik doğrulama")
    kontrol(istek("GET", "dosyalar")[0] == 401, "oturumsuz istek 401")
    kontrol(istek("GET", "dosyalar", token="sahte-token")[0] == 401, "sahte token 401")
    kontrol(istek("GET", "dosyalar", basliklar={"authorization": "Basic YTpi"})[0] == 401, "Bearer olmayan başlık 401")

    print("2. Kurumlar arası erişim (IDOR)")
    d, _, _ = istek("GET", f"dosyalar/{dosya_a}", token=tb)
    kontrol(d in (403, 404), f"B, A'nın dosyasını açamıyor ({d})")
    d, _, g = istek("GET", "dosyalar", token=tb)
    kontrol(d == 200 and dosya_a not in g.decode(), "B'nin dosya listesinde A'nın dosyası yok")
    d, _, _ = istek("POST", f"dosyalar/{dosya_a}/belgeler", token=tb, ham=b"%PDF-1.7\n%%EOF",
                    basliklar={"x-dosya-adi": "x.pdf", "content-type": "application/octet-stream"})
    kontrol(d >= 400 and d != 500, f"B, A'nın dosyasına belge yükleyemiyor ({d})")
    d, _, _ = istek("PUT", f"kullanicilar/{ua}/roller", {"roller": ["avukat"]}, tb)
    kontrol(d >= 400 and d != 500, f"B, A'nın kullanıcısının rolünü değiştiremiyor ({d})")
    d, _, g = istek("GET", "denetim", token=tb)
    kontrol(d != 200 or dosya_a not in g.decode(), "B'nin denetim kaydında A'nın işlemleri yok")

    print("3. SQL enjeksiyonu")
    for yuk in ["' OR '1'='1", "1; DROP TABLE hukuk.dosya; --", "\\' UNION SELECT sifre_ozeti FROM hukuk.kullanici --"]:
        d, _, g = istek("GET", "belgeler/ara?q=" + urllib.request.quote(yuk), token=tb)
        kontrol(d != 500 and b"argon2" not in g, f"arama alanı: {yuk[:20]}… ({d})")
        d, _, _ = istek("GET", "dosyalar/" + urllib.request.quote(yuk, safe=""), token=tb)
        kontrol(d in (400, 404, 409), f"yol parametresi: {yuk[:20]}… ({d})")
    d, _, g = istek("POST", "giris", {"eposta": "x' OR 1=1 --@ornek.test", "sifre": "x' OR '1'='1"})
    kontrol(d == 401, f"girişte enjeksiyon ({d})")
    with psycopg.connect(DSN) as c:
        kontrol(c.execute("SELECT to_regclass('hukuk.dosya')").fetchone()[0] is not None, "tablolar yerinde")

    print("4. Girdi ve kaynak tüketimi")
    d, _, _ = istek("POST", "dosyalar", token=ta, ham=b'{"baslik":"' + b"a" * (2 * 1024 * 1024) + b'"}',
                    basliklar={"content-type": "application/json"})
    kontrol(d == 413, f"2 MB JSON reddedilir ({d})")
    t0 = time.time()
    d, _, _ = istek("POST", "giris", {"eposta": "yok@ornek.test", "sifre": "a" * 100_000})
    kontrol(d == 401 and time.time() - t0 < 5, f"aşırı uzun şifre hızlıca reddedilir ({d})")
    d, _, _ = istek("POST", "dosyalar", token=ta, ham=b"{bozuk", basliklar={"content-type": "application/json"})
    kontrol(d == 400, f"bozuk JSON 400 ({d})")

    print("5. Dosya yükleme")
    exe = b"MZ\x90\x00" + b"\x00" * 100
    d, _, _ = istek("POST", f"dosyalar/{dosya_a}/belgeler", token=ta, ham=exe,
                    basliklar={"x-dosya-adi": "dilekce.pdf", "content-type": "application/octet-stream"})
    kontrol(d == 400, f"PDF diye yüklenen çalıştırılabilir dosya reddedilir ({d})")
    d, _, _ = istek("POST", f"dosyalar/{dosya_a}/belgeler", token=ta, ham=b"<script>alert(1)</script>",
                    basliklar={"x-dosya-adi": "a.html", "content-type": "application/octet-stream"})
    kontrol(d == 400, f"HTML dosyası reddedilir ({d})")
    d, _, _ = istek("POST", f"dosyalar/{dosya_a}/belgeler", token=ta, ham=b"%PDF-1.7\n%%EOF",
                    basliklar={"x-dosya-adi": "a%0D%0ASet-Cookie:x.pdf", "content-type": "application/octet-stream"})
    kontrol(d == 400, f"dosya adında satır sonu reddedilir ({d})")
    d, _, _ = istek("GET", "belgeler/..%2F..%2Fetc%2Fpasswd/surumler/1/icerik", token=ta)
    kontrol(d in (400, 404), f"yol geçişi ({d})")

    print("6. Tarayıcı güvenliği")
    _, b, _ = istek("GET", "dosyalar", token=ta)
    for ad in ["x-content-type-options", "x-frame-options", "content-security-policy", "strict-transport-security",
               "referrer-policy", "cache-control"]:
        kontrol(ad in b, f"başlık: {ad}")
    _, b, _ = istek("GET", "dosyalar", token=ta, basliklar={"origin": "https://saldirgan.example"})
    kontrol("access-control-allow-origin" not in b, "izinsiz kökene CORS izni yok")
    _, b, _ = istek("GET", "dosyalar", token=ta, basliklar={"origin": IZINLI_KOKEN})
    kontrol(b.get("access-control-allow-origin") == IZINLI_KOKEN, "izinli kökene CORS izni var")
    d, _, g = istek("GET", "yok/olmayan/yol", token=ta)
    kontrol(d == 404 and b"Exception" not in g and b"package:" not in g, "bilinmeyen yolda iç ayrıntı sızmaz")

    print("7. Oturum")
    d, _, _ = istek("POST", "cikis", {}, tb)
    kontrol(d in (200, 204), f"çıkış ({d})")
    kontrol(istek("GET", "ben", token=tb)[0] == 401, "çıkıştan sonra token geçersiz")

    print("8. Kaba kuvvet")
    durumlar = [istek("POST", "giris", {"eposta": f"deneme{i}@ornek.test", "sifre": "Yanlis-Sifre-1"})[0]
                for i in range(40)]
    kontrol(429 in durumlar, "çok sayıda hatalı giriş 429 ile durdurulur")

    basarisiz = [ad for ok, ad in sonuclar if not ok]
    print(f"\n{len(sonuclar) - len(basarisiz)}/{len(sonuclar)} deneme güvenli sonuçlandı.")
    for ad in basarisiz:
        print("  AÇIK:", ad)
    return 1 if basarisiz else 0


if __name__ == "__main__":
    sys.exit(main())
