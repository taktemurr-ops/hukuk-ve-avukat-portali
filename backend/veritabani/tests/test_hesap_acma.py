import uuid

import psycopg
import pytest

OZET = "$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA"


def test_hesap_ac_deneme_ve_kurucu_rolu(uygulama):
    eposta = f"kurucu.{uuid.uuid4().hex[:6]}@buro.com.tr"
    k, u = uygulama.c.execute("SELECT * FROM hukuk.hesap_ac('Deniz Hukuk', 'hukukBurosu', %s, 'Av. Deniz Ak', %s)",
                              (eposta.upper(), OZET)).fetchone()
    uygulama.oturum(k, u)
    assert uygulama.deger("SELECT eposta FROM hukuk.kullanici") == eposta
    assert uygulama.liste("SELECT rol FROM hukuk.kullanici_rol") == ["yoneticiOrtak"]
    assert uygulama.deger("SELECT durum FROM hukuk.abonelik") == "deneme"
    assert uygulama.deger("SELECT donem_sonu - donem_basi FROM hukuk.abonelik") == 14
    assert uygulama.deger("SELECT hukuk.denetim_dogrula(%s)", k) is None
    assert uygulama.deger("SELECT count(*) FROM hukuk.denetim_kaydi") == 1


def test_gecersiz_tur_ve_duz_sifre(uygulama):
    with pytest.raises(psycopg.errors.CheckViolation):
        uygulama.c.execute("SELECT * FROM hukuk.hesap_ac('X', 'baska', 'a@b.com', 'A', %s)", (OZET,))
    with pytest.raises(psycopg.errors.CheckViolation):
        uygulama.c.execute("SELECT * FROM hukuk.hesap_ac('X', 'kurumsal', 'a@b.com', 'A', 'duzsifre')")


def test_sure_baslangic_ve_adimlar(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["elif"])
    u.c.execute("UPDATE hukuk.sure_kaydi SET baslangic = '2026-11-25', hesap_adimlari = %s::jsonb "
                "WHERE aciklama = 'Cevap dilekçesi'", ('[{"tarih": "2026-11-25", "aciklama": "Başlangıç"}]',))
    assert u.deger("SELECT hesap_adimlari->0->>'aciklama' FROM hukuk.sure_kaydi WHERE aciklama = 'Cevap dilekçesi'") == "Başlangıç"
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.sure_kaydi SET baslangic = '2027-01-01' WHERE aciklama = 'Cevap dilekçesi'")
