"""Şifre sıfırlama: tek kullanımlık, süreli, hesap varlığını sızdırmaz, oturumları kapatır, sınırlı."""
import hashlib

import psycopg
import pytest

YENI = "$argon2id$v=19$m=65536,t=3,p=4$eWVuaQ$eWVuaQ"


def ozet(kod):
    return hashlib.sha256(kod.encode()).hexdigest()


def iste(u, eposta, kod):
    u.c.execute("SELECT hukuk.sifre_sifirlama_iste(%s, %s, 'Şifre sıfırlama', %s)", (eposta, ozet(kod), f"bağlantı {kod}"))


def test_akis(uygulama, veri, yonetici):
    u = uygulama
    adres = f"mert.{veri['k1'].hex[:8]}@ornek.com.tr"  # test veritabanı paylaşımlı: tekil adres
    yonetici.execute("UPDATE hukuk.kullanici SET eposta = %s WHERE id = %s", (adres, veri["mert"]))
    yonetici.execute("SELECT hukuk.oturum_ac(%s, %s, interval '1 day', 'test')", ("a" * 64, veri["mert"]))
    iste(u, adres.upper(), "kod1")
    assert yonetici.execute("SELECT count(*) FROM hukuk.eposta_kuyrugu WHERE alici = %s AND tur = 'sifreSifirlama'",
                            (adres,)).fetchone()[0] == 1
    assert u.deger("SELECT hukuk.sifre_sifirla(%s, %s)", ozet("kod1"), YENI) == 1
    assert yonetici.execute("SELECT sifre_ozeti FROM hukuk.kullanici WHERE id = %s", (veri["mert"],)).fetchone()[0] == YENI
    assert u.c.execute("SELECT * FROM hukuk.oturum_coz(%s)", ("a" * 64,)).fetchall() == []
    with pytest.raises(psycopg.errors.InvalidParameterValue):  # ikinci kullanım
        u.deger("SELECT hukuk.sifre_sifirla(%s, %s)", ozet("kod1"), YENI)


def test_bilinmeyen_adres_ve_sinir(uygulama, veri, yonetici):
    iste(uygulama, "yok@ornek.com.tr", "x")  # hata yok, iz yok
    assert yonetici.execute("SELECT count(*) FROM hukuk.sifre_sifirlama WHERE eposta = 'yok@ornek.com.tr'").fetchone()[0] == 0
    for i in range(5):
        iste(uygulama, "elif@ornek.com.tr", f"e{i}{veri['k1']}")
    assert yonetici.execute("SELECT count(*) FROM hukuk.sifre_sifirlama WHERE eposta = 'elif@ornek.com.tr' "
                            "AND olusturma > now() - interval '1 hour'").fetchone()[0] <= 3


def test_eski_kod_ve_sure(uygulama, veri, yonetici):
    k = str(veri["k1"])
    yonetici.execute("DELETE FROM hukuk.sifre_sifirlama WHERE eposta = 'ayse@ornek.com.tr'")
    iste(uygulama, "ayse@ornek.com.tr", "eski" + k)
    iste(uygulama, "ayse@ornek.com.tr", "yeni" + k)
    with pytest.raises(psycopg.errors.InvalidParameterValue):  # yeni istek eskisini geçersiz kıldı
        uygulama.deger("SELECT hukuk.sifre_sifirla(%s, %s)", ozet("eski" + k), YENI)
    yonetici.execute("UPDATE hukuk.sifre_sifirlama SET son_gecerlilik = now() - interval '1 minute' WHERE kod_ozeti = %s",
                     (ozet("yeni" + k),))
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        uygulama.deger("SELECT hukuk.sifre_sifirla(%s, %s)", ozet("yeni" + k), YENI)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        uygulama.c.execute("SELECT * FROM hukuk.sifre_sifirlama")
