"""Uyum: açık ihbar formu, takip koduyla durum, soruşturma notları ve kapanış kilidi, veri ihlali kaydı."""
import datetime as dt
import hashlib

import psycopg
import pytest


def _ozet(kod):
    return hashlib.sha256(kod.encode()).hexdigest()


def test_acik_ihbar_formu_ve_takip_kodu(uygulama, veri, yonetici):
    u = uygulama.oturum(veri["k1"], veri["elif"])
    # Kurumsal olmayan hesapta form yoktur.
    with pytest.raises(psycopg.errors.NoDataFound):
        u.c.execute("SELECT hukuk.ihbar_formu(%s, 'diger', 'Yeterince uzun bir ihbar açıklaması', NULL, %s)",
                    (veri["k1"], _ozet("KOD1")))
    yonetici.execute("UPDATE hukuk.kiraci SET hesap_turu = 'kurumsal' WHERE id = %s", (veri["k1"],))
    # Oturumsuz (kiracı ayarlanmamış) bağlantıdan da çağrılabilir.
    u.c.execute("SELECT set_config('app.kiraci_id', '', false), set_config('app.kullanici_id', '', false)")
    u.c.execute("SELECT hukuk.ihbar_formu(%s, 'rusvetYolsuzluk', 'Depoda sayım farkları gizleniyor iddiası', NULL, %s)",
                (veri["k1"], _ozet("KOD1")))
    satir = u.c.execute("SELECT * FROM hukuk.ihbar_durumu(%s)", (_ozet("KOD1"),)).fetchone()
    assert satir[0] == "alindi" and satir[1] is False
    assert u.c.execute("SELECT * FROM hukuk.ihbar_durumu(%s)", (_ozet("YANLIS"),)).fetchone() is None
    with pytest.raises(psycopg.errors.UniqueViolation):
        u.c.execute("SELECT hukuk.ihbar_formu(%s, 'diger', 'Aynı kodla ikinci ihbar denemesi metni', NULL, %s)",
                    (veri["k1"], _ozet("KOD1")))


def test_sorusturma_notu_gizli_ve_kapanis_kilitli(uygulama, veri, yonetici):
    yonetici.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'hukukDirektoru')", (veri["k1"], veri["ayse"]))
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    u.c.execute("INSERT INTO hukuk.ihbar (kiraci_id, takip_kodu_ozet, kanal, kategori, aciklama) "
                "VALUES (%s, %s, 'web', 'diger', 'Bir ihbar metni yeterince uzun olmalı')", (veri["k1"], _ozet("K2")))
    ihbar = u.deger("SELECT id FROM hukuk.ihbar")
    s = u.deger("INSERT INTO hukuk.sorusturma (kiraci_id, ihbar_id, sorumlu) VALUES (%s, %s, %s) RETURNING id",
                veri["k1"], ihbar, veri["ayse"])
    u.c.execute("INSERT INTO hukuk.sorusturma_notu (kiraci_id, sorusturma_id, metin) VALUES (%s, %s, 'Tanık görüşmesi yapıldı')",
                (veri["k1"], s))
    # Ekipte olmayan not göremez ve yazamaz.
    m = uygulama.oturum(veri["k1"], veri["mert"])
    assert m.deger("SELECT count(*) FROM hukuk.sorusturma_notu") == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        m.c.execute("INSERT INTO hukuk.sorusturma_notu (kiraci_id, sorusturma_id, metin) VALUES (%s, %s, 'x')", (veri["k1"], s))
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    with pytest.raises(psycopg.errors.CheckViolation):  # sonuçsuz kapatma
        u.c.execute("UPDATE hukuk.sorusturma SET durum = 'kapandi' WHERE id = %s", (s,))
    u.c.execute("UPDATE hukuk.sorusturma SET durum = 'kapandi', sonuc = 'asilsiz', sonuc_ozeti = 'Belgeler iddiayı desteklemiyor' "
                "WHERE id = %s", (s,))
    with pytest.raises(psycopg.errors.CheckViolation, match="Sonuçlanmış"):
        u.c.execute("UPDATE hukuk.sorusturma SET durum = 'sorusturma', sonuc = NULL WHERE id = %s", (s,))
    st = u.c.execute("SELECT durum FROM hukuk.ihbar_durumu(%s)", (_ozet("K2"),)).fetchone()
    assert st[0] == "kapandi"


def test_veri_ihlali_72_saat_kaydi(uygulama, veri, yonetici):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    simdi = dt.datetime.now(dt.timezone.utc)
    u.c.execute("INSERT INTO hukuk.veri_ihlali (kiraci_id, ogrenilme, aciklama) VALUES (%s, %s, 'Yanlış alıcıya e-posta gitti')",
                (veri["k1"], simdi - dt.timedelta(hours=2)))
    # Yetkisiz rol göremez.
    assert u.deger("SELECT count(*) FROM hukuk.veri_ihlali") == 0
    yonetici.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'hukukDirektoru')", (veri["k1"], veri["ayse"]))
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    i = a.deger("SELECT id FROM hukuk.veri_ihlali")
    with pytest.raises(psycopg.errors.CheckViolation):  # öğrenilmeden önce bildirim
        a.c.execute("UPDATE hukuk.veri_ihlali SET kurula_bildirim = %s WHERE id = %s", (simdi - dt.timedelta(hours=3), i))
    a.c.execute("UPDATE hukuk.veri_ihlali SET kurula_bildirim = %s WHERE id = %s", (simdi, i))
    with pytest.raises(psycopg.errors.CheckViolation):  # bildirim zamanı sonradan değiştirilemez
        a.c.execute("UPDATE hukuk.veri_ihlali SET kurula_bildirim = %s WHERE id = %s", (simdi + dt.timedelta(hours=1), i))
    with pytest.raises(psycopg.errors.CheckViolation):  # gelecekte öğrenilme
        a.c.execute("INSERT INTO hukuk.veri_ihlali (kiraci_id, ogrenilme, aciklama) VALUES (%s, %s, 'Gelecek tarihli kayıt')",
                    (veri["k1"], simdi + dt.timedelta(days=1)))
