"""Süre hatırlatmaları: aynı uyarı aynı gün bir kez gider, adresler uygulamaya çıkmaz, pasif hesaplara gitmez."""
import psycopg
import pytest

GONDER = "SELECT hukuk.sure_bildirimi_gonder(%s, %s, '2026-12-08', %s, %s, %s, 'Süre hatırlatması', 'metin')"


def _sure(yonetici, veri, aciklama):
    return yonetici.execute("SELECT id FROM hukuk.sure_kaydi WHERE aciklama = %s AND kiraci_id = %s",
                             (aciklama, veri["k1"])).fetchone()[0]


def test_adaylar_ve_tekil_gonderim(uygulama, veri, yonetici):
    u = uygulama  # görev kiracı bağlamı olmadan çalışır
    adaylar = u.c.execute("SELECT ic_no, son_gun::text, durum FROM hukuk.sure_bildirim_adaylari()").fetchall()
    assert ("2026/1", "2026-12-09", "teyitBekliyor") in adaylar  # tüm kiracılar
    s = _sure(yonetici, veri, "Cevap dilekçesi")
    assert u.deger(GONDER, veri["k1"], s, "hatirlatma", [veri["mert"]], False) == 1
    assert u.deger(GONDER, veri["k1"], s, "hatirlatma", [veri["mert"]], False) == 0  # aynı gün ikinci kez yok
    # Yönetici seviyesi: sorumlu + yöneticiler (ayse); tekrar edenler tek adres.
    assert u.deger(GONDER, veri["k1"], s, "yonetici", [veri["mert"], veri["ayse"]], True) == 2
    alicilar = sorted(r[0] for r in yonetici.execute(
        "SELECT alici FROM hukuk.eposta_kuyrugu WHERE tur = 'sure' AND kiraci_id = %s", (veri["k1"],)).fetchall())
    assert alicilar == ["ayse@ornek.com.tr", "mert@ornek.com.tr", "mert@ornek.com.tr"]
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("SELECT * FROM hukuk.eposta_kuyrugu")


def test_pasif_hesap_ve_baska_kiraci(uygulama, veri, yonetici):
    s = _sure(yonetici, veri, "Cevap dilekçesi")
    yonetici.execute("UPDATE hukuk.kullanici SET aktif = false WHERE id = %s", (veri["mert"],))
    assert uygulama.deger(GONDER, veri["k1"], s, "kritik", [veri["mert"]], False) == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        uygulama.deger(GONDER, veri["k2"], s, "kritik", [veri["baska"]], False)


def test_kayitlari_yalnizca_yonetici_gorur(uygulama, veri, yonetici):
    s = _sure(yonetici, veri, "Cevap dilekçesi")
    uygulama.deger(GONDER, veri["k1"], s, "hatirlatma", [veri["mert"]], False)
    assert uygulama.oturum(veri["k1"], veri["mert"]).deger("SELECT count(*) FROM hukuk.sure_bildirimi") == 0
    assert uygulama.oturum(veri["k1"], veri["ayse"]).deger("SELECT count(*) FROM hukuk.sure_bildirimi") == 1
