import hashlib

import psycopg
import pytest


def _ozet(t: str) -> str:
    return hashlib.sha256(t.encode()).hexdigest()


def test_giris_adaylari_ve_kilit(uygulama, veri, yonetici):
    eposta = f"mert.{veri['mert'].hex[:8]}@ornek.com.tr"
    yonetici.execute("UPDATE hukuk.kullanici SET eposta = %s WHERE id = %s", (eposta, veri["mert"]))
    u = uygulama  # kiracı bağlamı yok: giriş öncesi
    adaylar = u.c.execute("SELECT kullanici_id, kiraci_adi, sifre_ozeti FROM hukuk.giris_adaylari(%s)",
                          (eposta.upper(),)).fetchall()
    assert [(a[0], a[1]) for a in adaylar] == [(veri["mert"], "Yılmaz Hukuk")]
    assert adaylar[0][2].startswith("$argon2id$")
    for i in range(5):
        assert u.deger("SELECT hukuk.giris_kilitli(%s)", eposta) is False
        u.c.execute("SELECT hukuk.giris_denemesi_kaydet(%s, false)", (eposta,))
    assert u.deger("SELECT hukuk.giris_kilitli(%s)", eposta) is True
    assert u.c.execute("SELECT * FROM hukuk.giris_adaylari(%s)", (eposta,)).fetchall() == []
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("SELECT * FROM hukuk.giris_denemesi")


def test_oturum_yasam_dongusu(uygulama, veri, yonetici):
    u = uygulama
    u.c.execute("SELECT hukuk.oturum_ac(%s, %s, interval '8 hours', 'web')", (_ozet("t1"), veri["ayse"]))
    assert u.c.execute("SELECT * FROM hukuk.oturum_coz(%s)", (_ozet("t1"),)).fetchone() == (veri["ayse"], veri["k1"])
    assert u.c.execute("SELECT * FROM hukuk.oturum_coz(%s)", (_ozet("yanlis"),)).fetchone() is None

    u.c.execute("SELECT hukuk.oturum_ac(%s, %s, interval '-1 second', 'web')", (_ozet("eski"), veri["ayse"]))
    assert u.c.execute("SELECT * FROM hukuk.oturum_coz(%s)", (_ozet("eski"),)).fetchone() is None

    u.c.execute("SELECT hukuk.oturum_kapat(%s)", (_ozet("t1"),))
    assert u.c.execute("SELECT * FROM hukuk.oturum_coz(%s)", (_ozet("t1"),)).fetchone() is None

    # Kullanıcı pasifleşince oturumları kapanır.
    u.c.execute("SELECT hukuk.oturum_ac(%s, %s, interval '8 hours', 'mobil')", (_ozet("t2"), veri["elif"]))
    yonetici.execute("UPDATE hukuk.kullanici SET aktif = false WHERE id = %s", (veri["elif"],))
    assert u.c.execute("SELECT * FROM hukuk.oturum_coz(%s)", (_ozet("t2"),)).fetchone() is None
    assert yonetici.execute("SELECT iptal IS NOT NULL FROM hukuk.oturum WHERE token_ozeti = %s", (_ozet("t2"),)).fetchone()[0]

    # Uygulama yalnızca kendi oturumlarını listeler.
    u.oturum(veri["k1"], veri["mert"])
    assert u.deger("SELECT count(*) FROM hukuk.oturum") == 0
