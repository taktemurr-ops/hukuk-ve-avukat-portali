"""Şirket yetkisi: atanan şirket ve alt şirketleri görülür; atama yoksa ve yöneticide kısıt yok."""
import uuid

import psycopg
import pytest


def test_sirket_yetkisi(uygulama, veri, yonetici):
    k = veri["k1"]
    ana, alt, baska = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    yonetici.execute("INSERT INTO hukuk.sirket (id, kiraci_id, unvan, ana_sirket_id) VALUES (%s, %s, 'Holding', NULL), "
                     "(%s, %s, 'Gıda', %s), (%s, %s, 'Enerji', NULL)", (ana, k, alt, k, ana, baska, k))
    for i, (sid, ad) in enumerate([(alt, "Gıda tedarik"), (baska, "Enerji kira"), (None, "Şirketsiz")]):
        yonetici.execute("INSERT INTO hukuk.sozlesme (kiraci_id, no, baslik, tur, sorumlu, sirket_id) "
                         "VALUES (%s, %s, %s, 'hizmet', %s, %s)", (k, f"SZ-{i}", ad, veri["mert"], sid))
    mert = uygulama.oturum(k, veri["mert"])
    assert mert.deger("SELECT count(*) FROM hukuk.sozlesme") == 3  # kısıt yok
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        mert.c.execute("SELECT hukuk.kullanici_sirketleri_ayarla(%s, %s)", (veri["elif"], [ana]))
    ayse = uygulama.oturum(k, veri["ayse"])
    ayse.c.execute("SELECT hukuk.kullanici_sirketleri_ayarla(%s, %s)", (veri["mert"], [ana]))
    mert = uygulama.oturum(k, veri["mert"])
    assert mert.liste("SELECT baslik FROM hukuk.sozlesme ORDER BY baslik") == ["Gıda tedarik"]  # alt şirket dahil
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        mert.c.execute("INSERT INTO hukuk.sozlesme (kiraci_id, no, baslik, tur, sorumlu, sirket_id) "
                       "VALUES (%s, 'SZ-9', 'Yeni', 'hizmet', %s, %s)", (k, veri["mert"], baska))
    assert uygulama.oturum(k, veri["ayse"]).deger("SELECT count(*) FROM hukuk.sozlesme") == 3  # yönetici
    uygulama.oturum(k, veri["ayse"]).c.execute("SELECT hukuk.kullanici_sirketleri_ayarla(%s, '{}')", (veri["mert"],))
    assert uygulama.oturum(k, veri["mert"]).deger("SELECT count(*) FROM hukuk.sozlesme") == 3
