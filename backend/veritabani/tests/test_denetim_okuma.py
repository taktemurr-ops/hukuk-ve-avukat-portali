import psycopg
import pytest


def _yaz(o, k, n):
    o.c.execute("INSERT INTO hukuk.denetim_kaydi (kiraci_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet) "
                "VALUES (%s, 'disaAktarma', 'rapor', %s, '', '', '')", (k, n))


def test_denetimi_yalnizca_yonetici_okur(uygulama, veri):
    mert = uygulama.oturum(veri["k1"], veri["mert"])
    _yaz(mert, veri["k1"], "İş yükü")
    assert mert.deger("SELECT count(*) FROM hukuk.denetim_kaydi") == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        mert.deger("SELECT hukuk.denetim_dogrula(%s)", veri["k1"])

    ayse = uygulama.oturum(veri["k1"], veri["ayse"])
    assert ayse.liste("SELECT nesne_id FROM hukuk.denetim_kaydi") == ["İş yükü"]
    assert ayse.deger("SELECT kullanici_id FROM hukuk.denetim_kaydi") == veri["mert"]
    assert ayse.deger("SELECT hukuk.denetim_dogrula(%s)", veri["k1"]) is None
    # Başka kiracının zincirini doğrulayamaz.
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        ayse.deger("SELECT hukuk.denetim_dogrula(%s)", veri["k2"])


def test_baska_kiraciya_kayit_yazilamaz(uygulama, veri):
    mert = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        _yaz(mert, veri["k2"], "x")
