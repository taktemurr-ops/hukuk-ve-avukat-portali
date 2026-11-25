"""Abonelik ödemesi: yalnızca yönetici başlatır, sonuç yalnızca bildirimle; tek seferlik, tutar kontrolü; yazma kilidi."""
import datetime as dt
import secrets

import psycopg
import pytest


def _abonelik(yonetici, kiraci, durum="deneme", sonu_gun=10, ilk_basarisiz=None):
    yonetici.execute("INSERT INTO hukuk.abonelik (kiraci_id, durum, donem, donem_basi, donem_sonu, ilk_basarisiz) "
                     "VALUES (%s, %s, 'aylik', current_date - 20, current_date + %s, %s)",
                     (kiraci, durum, sonu_gun, ilk_basarisiz))


def _odeme(u, kiraci, toplam=180000, koltuk=1, donem="aylik"):
    ref = secrets.token_hex(16)
    u.c.execute("INSERT INTO hukuk.odeme (kiraci_id, saglayici, referans, donem, koltuk, matrah_kurus, kdv_kurus, toplam_kurus) "
                "VALUES (%s, 'sahte', %s, %s, %s, %s, %s, %s)", (kiraci, ref, donem, koltuk, toplam * 5 // 6, toplam // 6, toplam))
    return ref


def test_abonelik_dogrudan_yazilamaz_odemeyi_yonetici_baslatir(uygulama, veri, yonetici):
    _abonelik(yonetici, veri["k1"])
    m = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        m.c.execute("UPDATE hukuk.abonelik SET durum = 'aktif'")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        _odeme(m, veri["k1"])
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    _odeme(a, veri["k1"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        a.c.execute("UPDATE hukuk.odeme SET durum = 'basarili'")


def test_basarili_bildirim_donem_acar_ve_tek_seferliktir(uygulama, veri, yonetici):
    _abonelik(yonetici, veri["k1"])
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    ref = _odeme(a, veri["k1"], koltuk=3, donem="yillik")
    sonuc = a.deger("SELECT hukuk.odeme_sonuclandi(%s, true, 180000, 'SAG-1', NULL)", ref)
    assert sonuc == "basarili"
    durum, basi, sonu, koltuk = yonetici.execute(
        "SELECT durum, donem_basi, donem_sonu, ucretli_koltuk FROM hukuk.abonelik WHERE kiraci_id = %s", (veri["k1"],)).fetchone()
    bugun = dt.date.today()
    assert (durum, basi, koltuk) == ("aktif", bugun, 3)
    assert sonu == bugun.replace(year=bugun.year + 1)
    # Aynı bildirim ikinci kez gelirse dönem uzamaz.
    assert a.deger("SELECT hukuk.odeme_sonuclandi(%s, true, 180000, 'SAG-1', NULL)", ref) == "basarili"
    assert yonetici.execute("SELECT donem_sonu FROM hukuk.abonelik WHERE kiraci_id = %s", (veri["k1"],)).fetchone()[0] == sonu


def test_tutar_uyusmazsa_basarisiz_ve_aktif_abonelik_odeme_bekler(uygulama, veri, yonetici):
    _abonelik(yonetici, veri["k1"], durum="aktif", sonu_gun=3)
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    ref = _odeme(a, veri["k1"])
    assert a.deger("SELECT hukuk.odeme_sonuclandi(%s, true, 100, 'SAG-2', NULL)", ref) == "basarisiz"
    durum, hata = yonetici.execute("SELECT durum, hata FROM hukuk.odeme WHERE referans = %s", (ref,)).fetchone()
    assert durum == "basarisiz" and "uyuşmazlığı" in hata
    assert yonetici.execute("SELECT durum FROM hukuk.abonelik WHERE kiraci_id = %s", (veri["k1"],)).fetchone()[0] == "odemeBekliyor"


@pytest.mark.parametrize("durum,sonu,ilk,beklenen", [
    ("deneme", 5, None, True),
    ("deneme", 0, None, False),           # deneme bitti → askıda
    ("aktif", -3, None, True),            # 7 gün tolerans: ödeme bekliyor
    ("aktif", -10, None, False),          # yenilenmedi → askıda
    ("odemeBekliyor", 5, dt.date.today() - dt.timedelta(days=8), False),
    ("iptal", 5, None, False),
])
def test_yazma_kilidi(uygulama, veri, yonetici, durum, sonu, ilk, beklenen):
    _abonelik(yonetici, veri["k1"], durum=durum, sonu_gun=sonu, ilk_basarisiz=ilk)
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    assert a.deger("SELECT hukuk.abonelik_yazilabilir(%s)", veri["k1"]) is beklenen
