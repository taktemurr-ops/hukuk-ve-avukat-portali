"""Göç uygulayıcı: migrations/ altındaki SQL dosyalarını sırayla, her birini tek işlemde uygular.

Uygulanan göçler `public.hukuk_goc` tablosunda tutulur (ad + SHA-256). Daha önce uygulanmış bir dosyanın içeriği
değişmişse durur (göçler değiştirilmez; yeni göç yazılır). Dosyalardaki BEGIN/COMMIT satırları yok sayılır; her dosya
izleme kaydıyla birlikte tek işlemde uygulanır, hata olursa hiçbir kısmı kalmaz.

Kullanım:  PG_DSN="host=... user=... password=... dbname=hukuk" python goc.py [--kontrol]
"""
import hashlib
import os
import pathlib
import re
import sys

import psycopg
import psycopg.sql

KLASOR = pathlib.Path(__file__).resolve().parent / "migrations"
_ISLEM = re.compile(r"^\s*(BEGIN|COMMIT)\s*;\s*$", re.IGNORECASE | re.MULTILINE)


def main():
    dsn = os.environ.get("PG_DSN")
    if not dsn:
        sys.exit("PG_DSN tanımlı değil.")
    sadece_kontrol = "--kontrol" in sys.argv
    with psycopg.connect(dsn) as c:
        c.execute("CREATE TABLE IF NOT EXISTS public.hukuk_goc (ad text PRIMARY KEY, ozet char(64) NOT NULL, "
                  "zaman timestamptz NOT NULL DEFAULT now())")
        c.commit()
        uygulanmis = dict(c.execute("SELECT ad, ozet FROM public.hukuk_goc").fetchall())
        bekleyen = 0
        for dosya in sorted(KLASOR.glob("*.sql")):
            metin = dosya.read_text(encoding="utf-8")
            ozet = hashlib.sha256(metin.encode()).hexdigest()
            if dosya.name in uygulanmis:
                if uygulanmis[dosya.name].strip() != ozet:
                    sys.exit(f"{dosya.name} uygulandıktan sonra değişmiş; göçler değiştirilmez, yeni göç yazın.")
                continue
            bekleyen += 1
            if sadece_kontrol:
                print(f"bekliyor: {dosya.name}")
                continue
            print(f"uygulanıyor: {dosya.name}")
            with c.transaction():
                c.execute(_ISLEM.sub("", metin))
                c.execute("INSERT INTO public.hukuk_goc (ad, ozet) VALUES (%s, %s)", (dosya.name, ozet))
        print(f"{'bekleyen' if sadece_kontrol else 'uygulanan'} göç: {bekleyen}")
        # Uygulama sunucusunun bağlanacağı kullanıcı (tablo sahibi değil; RLS'e tabi hukuk_uygulama rolünün üyesi).
        sifre = os.environ.get("PG_UYGULAMA_SIFRE")
        if sifre and not sadece_kontrol:
            var = c.execute("SELECT 1 FROM pg_roles WHERE rolname = 'hukuk_api'").fetchone()
            komut = "ALTER ROLE hukuk_api" if var else "CREATE ROLE hukuk_api LOGIN IN ROLE hukuk_uygulama"
            c.execute(psycopg.sql.SQL(komut + " PASSWORD {}").format(psycopg.sql.Literal(sifre)))
            c.commit()
            print("hukuk_api kullanıcısı hazır.")
        if sadece_kontrol and bekleyen:
            sys.exit(1)


if __name__ == "__main__":
    main()
