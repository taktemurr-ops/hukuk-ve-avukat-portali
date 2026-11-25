"""Testler gerçek bir PostgreSQL 16'ya karşı çalışır. PG_DSN ile bağlantı verilir (süper kullanıcı)."""

import os
import uuid
from pathlib import Path

import psycopg
import pytest

GOC = Path(__file__).resolve().parents[1] / "migrations"
DSN = os.environ.get("PG_DSN", "host=/tmp/pgdeneme port=54329 user=postgres")


@pytest.fixture(scope="session")
def vt_adi():
    ad = f"hukuk_test_{uuid.uuid4().hex[:8]}"
    with psycopg.connect(DSN + " dbname=postgres", autocommit=True) as c:
        c.execute(f'CREATE DATABASE "{ad}"')
    with psycopg.connect(DSN + f" dbname={ad}", autocommit=True) as c:
        for dosya in sorted(GOC.glob("*.sql")):
            c.execute(dosya.read_text(encoding="utf-8"))
    yield ad
    with psycopg.connect(DSN + " dbname=postgres", autocommit=True) as c:
        c.execute(f'DROP DATABASE "{ad}" WITH (FORCE)')


@pytest.fixture
def yonetici(vt_adi):
    """Süper kullanıcı bağlantısı (RLS'ye takılmaz); test verisini kurmak için."""
    with psycopg.connect(DSN + f" dbname={vt_adi}", autocommit=True) as c:
        yield c


class Uygulama:
    """Uygulama sunucusunun bağlantısı: hukuk_uygulama rolüyle, her işlemde kiracı ve kullanıcı ayarlanır."""

    def __init__(self, baglanti):
        self.c = baglanti

    def oturum(self, kiraci, kullanici):
        self.c.execute("SELECT set_config('app.kiraci_id', %s, false), set_config('app.kullanici_id', %s, false)",
                       (str(kiraci), str(kullanici)))
        return self

    def deger(self, sql, *p):
        satir = self.c.execute(sql, p).fetchone()
        return None if satir is None else satir[0]

    def liste(self, sql, *p):
        return [r[0] for r in self.c.execute(sql, p).fetchall()]


@pytest.fixture
def uygulama(vt_adi):
    with psycopg.connect(DSN + f" dbname={vt_adi}", autocommit=True) as c:
        c.execute("SET ROLE hukuk_uygulama")
        yield Uygulama(c)


OZET = "$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA"


@pytest.fixture
def veri(yonetici):
    """İki kiracı: Yılmaz Hukuk (ayse yönetici ortak, mert avukat, elif stajyer) ve başka bir büro."""
    k1, k2 = uuid.uuid4(), uuid.uuid4()
    k = {n: uuid.uuid4() for n in ["ayse", "mert", "elif", "baska"]}
    c = yonetici
    c.execute("INSERT INTO hukuk.kiraci (id, ad, hesap_turu) VALUES (%s, 'Yılmaz Hukuk', 'hukukBurosu'), (%s, 'Başka Büro', 'avukatlikBurosu')",
              (k1, k2))
    for ad, kir in [("ayse", k1), ("mert", k1), ("elif", k1), ("baska", k2)]:
        c.execute("INSERT INTO hukuk.kullanici (id, kiraci_id, eposta, ad_soyad, sifre_ozeti) VALUES (%s, %s, %s, %s, %s)",
                  (k[ad], kir, f"{ad}@ornek.com.tr", ad, OZET))
    c.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'yoneticiOrtak'), (%s, %s, 'avukat'), (%s, %s, 'stajyer'), (%s, %s, 'buroSahibi')",
              (k1, k["ayse"], k1, k["mert"], k1, k["elif"], k2, k["baska"]))
    d = {n: uuid.uuid4() for n in ["acik", "gizli", "duvarli", "baska"]}
    c.execute("""INSERT INTO hukuk.dosya (id, kiraci_id, ic_no, tur, baslik, sorumlu, gizli) VALUES
                 (%s, %s, '2026/1', 'hukuk', 'Açık dosya', %s, false),
                 (%s, %s, '2026/2', 'danismanlik', 'Gizli soruşturma', %s, true),
                 (%s, %s, '2026/3', 'hukuk', 'Duvarlı dosya', %s, false),
                 (%s, %s, '2026/1', 'hukuk', 'Başkasının dosyası', %s, false)""",
              (d["acik"], k1, k["mert"], d["gizli"], k1, k["ayse"], d["duvarli"], k1, k["ayse"], d["baska"], k2, k["baska"]))
    c.execute("INSERT INTO hukuk.etik_duvar (kiraci_id, dosya_id, kullanici_id, gerekce, kuran) VALUES (%s, %s, %s, %s, %s)",
              (k1, d["duvarli"], k["mert"], "Karşı tarafı önceki büroda temsil etti", k["ayse"]))
    c.execute("""INSERT INTO hukuk.sure_kaydi (kiraci_id, dosya_id, aciklama, kural_kodu, son_gun, olusturan, asil_sorumlu)
                 VALUES (%s, %s, 'Cevap dilekçesi', 'HMK_CEVAP_DILEKCESI', '2026-12-09', %s, %s),
                        (%s, %s, 'Gizli süre', 'HMK_ISTINAF', '2026-12-10', %s, %s)""",
              (k1, d["acik"], k["elif"], k["mert"], k1, d["gizli"], k["ayse"], k["ayse"]))
    return {"k1": k1, "k2": k2, **k, "d": d}
