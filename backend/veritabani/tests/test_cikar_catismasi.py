"""Çıkar çatışması: görünmeyen dosyanın tarafı da bulunur ama dosya adı maskelenir; karar değiştirilemez;
çatışmada kabul farklı bir yöneticinin onayına kadar geçerli değildir."""
import json
import uuid

import psycopg
import pytest


def test_tarama_gizli_dosyayi_maskeler(uygulama, veri, yonetici):
    kisi = uuid.uuid4()
    yonetici.execute("INSERT INTO hukuk.kisi (id, kiraci_id, tur, ad) VALUES (%s, %s, 'tuzel', 'Orman Enerji A.Ş.')",
                     (kisi, veri["k1"]))
    yonetici.execute("INSERT INTO hukuk.dosya_taraf (kiraci_id, dosya_id, kisi_id, sifat) VALUES (%s, %s, %s, 'karsiTaraf')",
                     (veri["k1"], veri["d"]["gizli"], kisi))
    elif_ = uygulama.oturum(veri["k1"], veri["elif"])
    assert elif_.deger("SELECT count(*) FROM hukuk.dosya_taraf WHERE kisi_id = %s", kisi) == 0  # doğrudan göremez
    r = elif_.c.execute("SELECT dosya_adi, korumali FROM hukuk.cikar_tarama_taraflari() WHERE kisi_id = %s", (kisi,)).fetchall()
    assert r == [("", True)]


def _karar(o, k, seviye, tur, gerekce="Müvekkil yazılı muvafakat verdi."):
    return o.deger("INSERT INTO hukuk.is_kabul_karari (kiraci_id, adaylar, en_yuksek, tur, gerekce, kosullar, durum) "
                   "VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id",
                   k, json.dumps([{"ad": "Orman Enerji", "sifat": "karsiTaraf"}]), seviye, tur, gerekce,
                   "Etik duvar kurulacak" if tur == "kosulluKabul" else None,
                   "onayBekliyor" if seviye == "catisma" and tur != "ret" else "gecerli")


def test_karar_ve_onay(uygulama, veri):
    mert = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.CheckViolation):  # çatışmada onaysız "geçerli" kabul olmaz
        mert.deger("INSERT INTO hukuk.is_kabul_karari (kiraci_id, adaylar, en_yuksek, tur, gerekce, durum) "
                   "VALUES (%s, '[{\"ad\":\"x\"}]', 'catisma', 'kabul', 'Yeterince uzun gerekçe', 'gecerli') RETURNING id", veri["k1"])
    kid = _karar(mert, veri["k1"], "catisma", "kosulluKabul")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        mert.c.execute("SELECT hukuk.is_kabul_onayla(%s)", (kid,))  # yönetici değil
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        mert.c.execute("UPDATE hukuk.is_kabul_karari SET gerekce = 'değişti başka gerekçe' WHERE id = %s", (kid,))
    ayse = uygulama.oturum(veri["k1"], veri["ayse"])
    ayse.c.execute("SELECT hukuk.is_kabul_onayla(%s)", (kid,))
    assert ayse.c.execute("SELECT durum, onaylayan FROM hukuk.is_kabul_karari WHERE id = %s", (kid,)).fetchone() == \
        ("gecerli", veri["ayse"])
    kendi = _karar(ayse, veri["k1"], "catisma", "kabul")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        ayse.c.execute("SELECT hukuk.is_kabul_onayla(%s)", (kendi,))  # kendi kararı
    assert _karar(mert, veri["k1"], "catisma", "ret")  # ret onay beklemez
