"""Yetki sertleştirme ve iki adımlı doğrulama saklama kuralları."""
import psycopg
import pytest


def test_kullanici_ve_rol_dogrudan_degistirilemez(uygulama, veri):
    m = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        m.c.execute("SELECT sifre_ozeti FROM hukuk.kullanici")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        m.c.execute("UPDATE hukuk.kullanici SET ad_soyad = 'x' WHERE id = %s", (veri["mert"],))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):  # kendine yönetici rolü veremez
        m.c.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'yoneticiOrtak')", (veri["k1"], veri["mert"]))
    assert m.deger("SELECT count(*) FROM hukuk.kullanici") == 3
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    a.c.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'muhasebe')", (veri["k1"], veri["elif"]))
    # Yönetici kendi rolünü de değiştiremez: silme satır bulmaz, ekleme reddedilir.
    assert a.c.execute("DELETE FROM hukuk.kullanici_rol WHERE kullanici_id = %s", (veri["ayse"],)).rowcount == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        a.c.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'denetci')", (veri["k1"], veri["ayse"]))


def test_dosya_ekibini_yalnizca_sorumlu_veya_yonetici_degistirir(uygulama, veri):
    e = uygulama.oturum(veri["k1"], veri["elif"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        e.c.execute("INSERT INTO hukuk.dosya_ekip VALUES (%s, %s, %s)", (veri["k1"], veri["d"]["acik"], veri["elif"]))
    m = uygulama.oturum(veri["k1"], veri["mert"])  # açık dosyanın sorumlusu
    m.c.execute("INSERT INTO hukuk.dosya_ekip VALUES (%s, %s, %s)", (veri["k1"], veri["d"]["acik"], veri["elif"]))


def test_iki_adimli_kurulum_ve_tekrar_kullanim(uygulama, veri, yonetici):
    m = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.CheckViolation):
        m.c.execute("SELECT hukuk.iki_adimli_etkinlestir(100)")
    m.c.execute("SELECT hukuk.iki_adimli_bekleyen_yaz(%s)", (b"sifreli-sir",))
    assert bytes(m.deger("SELECT hukuk.iki_adimli_bekleyen()")) == b"sifreli-sir"
    m.c.execute("SELECT hukuk.iki_adimli_etkinlestir(100)")
    sir, adim = m.c.execute("SELECT * FROM hukuk.iki_adimli_sir(%s)", (veri["mert"],)).fetchone()
    assert bytes(sir) == b"sifreli-sir" and adim == 100
    assert m.deger("SELECT hukuk.iki_adimli_adim_kullan(%s, 100)", veri["mert"]) is False  # aynı kod
    assert m.deger("SELECT hukuk.iki_adimli_adim_kullan(%s, 101)", veri["mert"]) is True
    assert m.deger("SELECT hukuk.iki_adimli_adim_kullan(%s, 101)", veri["mert"]) is False
    # Başkasının kurulumunu değiştiremez: fonksiyonlar oturumdaki kullanıcıya bağlıdır.
    e = uygulama.oturum(veri["k1"], veri["elif"])
    e.c.execute("SELECT hukuk.iki_adimli_kapat()")
    assert yonetici.execute("SELECT iki_adimli FROM hukuk.kullanici WHERE id = %s", (veri["mert"],)).fetchone()[0] is True
