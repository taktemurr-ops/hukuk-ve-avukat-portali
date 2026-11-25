"""Davet: yalnızca yönetici oluşturur, koltuk sayımı, kabulde e-posta/süre/tek kullanım, müvekkil davetinin kişiye bağlanması."""
import hashlib

import psycopg
import pytest

OZET = "$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA"


def _oz(kod):
    return hashlib.sha256(kod.encode()).hexdigest()


def _davet(u, kiraci, eden, kod, roller, eposta="yeni@ornek.com.tr", kisi=None):
    return u.deger("INSERT INTO hukuk.davet (kiraci_id, eposta, roller, kod_ozeti, davet_eden, kisi_id) "
                   "VALUES (%s, %s, %s, %s, %s, %s) RETURNING id", kiraci, eposta, roller, _oz(kod), eden, kisi)


def test_yalnizca_yonetici_davet_eder_ve_koltuk_sayilir(uygulama, veri, yonetici):
    yonetici.execute("INSERT INTO hukuk.abonelik (kiraci_id, durum, donem, donem_basi, donem_sonu, ucretli_koltuk) "
                     "VALUES (%s, 'aktif', 'aylik', current_date, current_date + 30, 5)", (veri["k1"],))
    m = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        _davet(m, veri["k1"], veri["mert"], "kod-m", ["avukat"])
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    # Ayşe (yönetici ortak), Mert (avukat), Elif (stajyer) = 3 koltuk.
    assert a.c.execute("SELECT * FROM hukuk.koltuk_durumu()").fetchone() == (5, 3)
    _davet(a, veri["k1"], veri["ayse"], "kod-1", ["avukat"])
    _davet(a, veri["k1"], veri["ayse"], "kod-2", ["talepEden"], eposta="talep@ornek.com.tr")
    assert a.c.execute("SELECT * FROM hukuk.koltuk_durumu()").fetchone() == (5, 4)
    # Davet listesini yönetici olmayan göremez.
    assert m.oturum(veri["k1"], veri["mert"]).deger("SELECT count(*) FROM hukuk.davet") == 0


def test_davet_kabul_kurallari(uygulama, veri, yonetici):
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    _davet(a, veri["k1"], veri["ayse"], "kod-k", ["avukat"])
    kabul = "SELECT kiraci_id, kullanici_id FROM hukuk.davet_kabul(%s, %s, 'Av. Yeni Kişi', %s)"
    with pytest.raises(psycopg.errors.CheckViolation):  # başka e-posta
        a.c.execute(kabul, (_oz("kod-k"), "baska@ornek.com.tr", OZET))
    with pytest.raises(psycopg.errors.CheckViolation):  # yanlış kod
        a.c.execute(kabul, (_oz("yanlis"), "yeni@ornek.com.tr", OZET))
    k, u = a.c.execute(kabul, (_oz("kod-k"), "YENI@ornek.com.tr", OZET)).fetchone()
    assert k == veri["k1"]
    assert yonetici.execute("SELECT rol FROM hukuk.kullanici_rol WHERE kullanici_id = %s", (u,)).fetchone()[0] == "avukat"
    with pytest.raises(psycopg.errors.CheckViolation):  # ikinci kullanım
        a.c.execute(kabul, (_oz("kod-k"), "yeni@ornek.com.tr", OZET))
    # Süresi dolmuş davet
    a.oturum(veri["k1"], veri["ayse"])
    d = _davet(a, veri["k1"], veri["ayse"], "kod-eski", ["avukat"], eposta="eski@ornek.com.tr")
    yonetici.execute("UPDATE hukuk.davet SET son_gecerlilik = now() - interval '1 minute' WHERE id = %s", (d,))
    with pytest.raises(psycopg.errors.CheckViolation):
        a.c.execute(kabul, (_oz("kod-eski"), "eski@ornek.com.tr", OZET))


def test_muvekkil_daveti_kisiye_baglanir(uygulama, veri, yonetici):
    kisi = yonetici.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'tuzel', 'ABC Gıda A.Ş.') RETURNING id",
                            (veri["k1"],)).fetchone()[0]
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    with pytest.raises(psycopg.errors.CheckViolation):  # kişisiz müvekkil daveti
        _davet(a, veri["k1"], veri["ayse"], "kod-x", ["muvekkil"], eposta="m@abc.com.tr")
    with pytest.raises(psycopg.errors.CheckViolation):  # müvekkil başka rolle birleşemez
        _davet(a, veri["k1"], veri["ayse"], "kod-y", ["muvekkil", "avukat"], eposta="m@abc.com.tr", kisi=kisi)
    _davet(a, veri["k1"], veri["ayse"], "kod-z", ["muvekkil"], eposta="m@abc.com.tr", kisi=kisi)
    _, u = a.c.execute("SELECT * FROM hukuk.davet_kabul(%s, 'm@abc.com.tr', 'Ali Veli', %s)", (_oz("kod-z"), OZET)).fetchone()
    assert yonetici.execute("SELECT kisi_id FROM hukuk.kullanici WHERE id = %s", (u,)).fetchone()[0] == kisi
