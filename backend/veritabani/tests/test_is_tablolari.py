import datetime as dt
import hashlib
import uuid

import psycopg
import pytest


def _kisi(yonetici, kiraci):
    return yonetici.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'tuzel', 'ABC Gıda A.Ş.') RETURNING id",
                            (kiraci,)).fetchone()[0]


def test_emanet_eksiye_dusmez_ve_mahsup_onay_ister(uygulama, veri, yonetici):
    m = _kisi(yonetici, veri["k1"])
    u = uygulama.oturum(veri["k1"], veri["mert"])
    ekle = ("INSERT INTO hukuk.emanet_hareket (kiraci_id, muvekkil_id, dosya_id, tur, tutar_kurus, tarih, aciklama, mahsup_onayi) "
            "VALUES (%s, %s, %s, %s, %s, current_date, 'x', %s)")
    u.c.execute(ekle, (veri["k1"], m, veri["d"]["acik"], "giris", 25_000_000, None))
    u.c.execute(ekle, (veri["k1"], m, veri["d"]["acik"], "muvekkileAktarim", 20_000_000, None))
    with pytest.raises(psycopg.errors.CheckViolation, match="bakiyesi yetersiz"):
        u.c.execute(ekle, (veri["k1"], m, veri["d"]["acik"], "muvekkileAktarim", 5_000_001, None))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute(ekle, (veri["k1"], m, veri["d"]["acik"], "ucretMahsubu", 1_000, None))
    u.c.execute(ekle, (veri["k1"], m, veri["d"]["acik"], "ucretMahsubu", 5_000_000, "Müvekkil e-posta onayı 25.11.2026"))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("UPDATE hukuk.emanet_hareket SET tutar_kurus = 1")


def test_zaman_kaydi_kurallari(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    ekle = ("INSERT INTO hukuk.zaman_kaydi (kiraci_id, kullanici_id, dosya_id, tarih, dakika, aciklama, saatlik_kurus) "
            "VALUES (%s, %s, %s, current_date, %s, 'Dilekçe hazırlığı', 300000) RETURNING id")
    z = u.deger(ekle, veri["k1"], veri["mert"], veri["d"]["acik"], 1400)
    with pytest.raises(psycopg.errors.CheckViolation, match="24 saat"):
        u.c.execute(ekle, (veri["k1"], veri["mert"], veri["d"]["acik"], 41))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.zaman_kaydi SET durum = 'onaylandi', onaylayan = kullanici_id WHERE id = %s", (z,))
    u.c.execute("UPDATE hukuk.zaman_kaydi SET durum = 'onaylandi', onaylayan = %s WHERE id = %s", (veri["ayse"], z))
    with pytest.raises(psycopg.errors.CheckViolation, match="silinemez"):
        u.c.execute("DELETE FROM hukuk.zaman_kaydi WHERE id = %s", (z,))
    u.c.execute("UPDATE hukuk.zaman_kaydi SET durum = 'faturalandi', fatura_no = 'ZF-2026-0001' WHERE id = %s", (z,))
    with pytest.raises(psycopg.errors.CheckViolation, match="Faturalanmış"):
        u.c.execute("UPDATE hukuk.zaman_kaydi SET dakika = 10 WHERE id = %s", (z,))


def test_sozlesme_onayi_ayni_kisi_iki_adim_onaylayamaz(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    s = u.deger("INSERT INTO hukuk.sozlesme (kiraci_id, no, baslik, tur, sorumlu, durum, onay_turu) "
                "VALUES (%s, 'SZ-1', 'Hizmet', 'hizmet', %s, 'onayda', 1) RETURNING id", veri["k1"], veri["ayse"])
    onay = ("INSERT INTO hukuk.sozlesme_onay (kiraci_id, sozlesme_id, tur_no, adim_sira, adim_kodu, kullanici_id, karar, notu) "
            "VALUES (%s, %s, 1, %s, %s, %s, %s, %s)")
    m = uygulama.oturum(veri["k1"], veri["mert"])
    m.c.execute(onay, (veri["k1"], s, 1, "hukuk", veri["mert"], "onay", ""))
    with pytest.raises(psycopg.errors.UniqueViolation):
        m.c.execute(onay, (veri["k1"], s, 2, "direktor", veri["mert"], "onay", ""))
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute(onay, (veri["k1"], s, 2, "direktor", veri["ayse"], "ret", ""))
    u.c.execute(onay, (veri["k1"], s, 2, "direktor", veri["ayse"], "onay", ""))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.sozlesme SET durum = 'yururlukte' WHERE id = %s", (s,))


def test_talep_ret_gerekcesi_ve_kapanis(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    t = u.deger("INSERT INTO hukuk.hukuk_talebi (kiraci_id, no, baslik, tur, oncelik, talep_eden, birim, sla_son_gun) "
                "VALUES (%s, 'HT-1', 'NDA', 'sozlesmeInceleme', 'normal', 'Satış', 'Satış', current_date + 3) RETURNING id",
                veri["k1"])
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.hukuk_talebi SET durum = 'reddedildi', kapanis = current_date WHERE id = %s", (t,))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.hukuk_talebi SET durum = 'tamamlandi' WHERE id = %s", (t,))
    u.c.execute("UPDATE hukuk.hukuk_talebi SET durum = 'reddedildi', kapanis = current_date, ret_gerekcesi = 'Kapsam dışı' "
                "WHERE id = %s", (t,))


def test_ihbar_ve_sorusturma_gizliligi(uygulama, veri, yonetici):
    # Ayşe'yi hukuk direktörü yap.
    yonetici.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'hukukDirektoru')", (veri["k1"], veri["ayse"]))
    u = uygulama.oturum(veri["k1"], veri["elif"])
    kod = hashlib.sha256(b"ABCDE23456").hexdigest()
    u.c.execute("INSERT INTO hukuk.ihbar (kiraci_id, takip_kodu_ozet, kanal, kategori, aciklama, ilgili_kisiler) "
                "VALUES (%s, %s, 'web', 'rusvetYolsuzluk', 'Satın almada tedarikçiden hediye alındığı iddiası', %s)",
                (veri["k1"], kod, [veri["mert"]]))
    # Kaydeden çalışan ihbarı sonradan göremez.
    assert u.deger("SELECT count(*) FROM hukuk.ihbar") == 0
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("INSERT INTO hukuk.ihbar (kiraci_id, takip_kodu_ozet, kanal, kategori, aciklama, anonim, iletisim) "
                    "VALUES (%s, %s, 'web', 'diger', 'Anonim olup iletişim bırakılan ihbar metni', true, 'x@y.com')",
                    (veri["k1"], kod))

    u.oturum(veri["k1"], veri["ayse"])
    ihbar = u.deger("SELECT id FROM hukuk.ihbar")
    assert ihbar is not None
    with pytest.raises(psycopg.errors.CheckViolation, match="İhbar edilen"):
        u.c.execute("INSERT INTO hukuk.sorusturma (kiraci_id, ihbar_id, sorumlu) VALUES (%s, %s, %s)",
                    (veri["k1"], ihbar, veri["mert"]))
    u.c.execute("INSERT INTO hukuk.sorusturma (kiraci_id, ihbar_id, sorumlu, ekip) VALUES (%s, %s, %s, %s)",
                (veri["k1"], ihbar, veri["ayse"], [veri["elif"]]))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.sorusturma SET ekip = ekip || %s::uuid", (veri["mert"],))

    # Ekipte olan Elif artık görür; ihbar edilen Mert hiçbir şey görmez ve soruşturma açamaz.
    u.oturum(veri["k1"], veri["elif"])
    assert u.deger("SELECT count(*) FROM hukuk.ihbar") == 1
    assert u.deger("SELECT count(*) FROM hukuk.sorusturma") == 1
    u.oturum(veri["k1"], veri["mert"])
    assert u.deger("SELECT count(*) FROM hukuk.ihbar") == 0
    assert u.deger("SELECT count(*) FROM hukuk.sorusturma") == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("INSERT INTO hukuk.sorusturma (kiraci_id, ihbar_id, sorumlu) VALUES (%s, %s, %s)",
                    (veri["k1"], ihbar, veri["elif"]))


def test_davet_ve_abonelik(uygulama, veri, yonetici):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("INSERT INTO hukuk.davet (kiraci_id, eposta, roller, kod_ozeti, davet_eden) VALUES (%s, 'a@b.com', '{}', %s, %s)",
                    (veri["k1"], "a" * 64, veri["ayse"]))
    u.c.execute("INSERT INTO hukuk.davet (kiraci_id, eposta, roller, kod_ozeti, davet_eden) VALUES (%s, 'a@b.com', '{avukat}', %s, %s)",
                (veri["k1"], "b" * 64, veri["ayse"]))
    assert u.deger("SELECT son_gecerlilik - olusturma FROM hukuk.davet") == dt.timedelta(hours=72)
    # Abonelik uygulama rolüyle hiç yazılamaz (yalnızca ödeme bildirimi); dönem tutarlılığı tabloda da zorlanır.
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("INSERT INTO hukuk.abonelik (kiraci_id, durum, donem, donem_basi, donem_sonu) "
                    "VALUES (%s, 'aktif', 'aylik', '2026-12-01', '2027-01-01')", (veri["k1"],))
    with pytest.raises(psycopg.errors.CheckViolation):
        yonetici.execute("INSERT INTO hukuk.abonelik (kiraci_id, durum, donem, donem_basi, donem_sonu) "
                         "VALUES (%s, 'aktif', 'aylik', '2026-12-01', '2026-12-01')", (veri["k1"],))


def test_icra_akdi_faiz_oran_ister_ve_masraf_eksi_olamaz(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    ekle = ("INSERT INTO hukuk.icra_dosyasi (kiraci_id, dosya_id, icra_dairesi, borclu, takip_turu, asil_kurus, temerrut, "
            "takip_tarihi, faiz_turu, akdi_oran, takip_oncesi_masraf_kurus) "
            "VALUES (%s, %s, 'İstanbul 5. İcra', 'Borçlu A.Ş.', 'ilamsiz', 100000, '2026-01-01', '2026-02-01', %s, %s, %s)")
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute(ekle, (veri["k1"], veri["d"]["acik"], "akdi", None, 0))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute(ekle, (veri["k1"], veri["d"]["acik"], "yasal", None, -1))
    u.c.execute(ekle, (veri["k1"], veri["d"]["acik"], "akdi", 24.5, 150_000))


def _sozlesme(u, kiraci, sorumlu):
    return u.deger("INSERT INTO hukuk.sozlesme (kiraci_id, no, baslik, tur, sorumlu) "
                   "VALUES (%s, 'SZ-2026-0099', 'Hizmet', 'hizmet', %s) RETURNING id", kiraci, sorumlu)


def test_sozlesme_onayi_yalnizca_guncel_turda_ve_kendi_adina(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    s = _sozlesme(u, veri["k1"], veri["mert"])
    ekle = "INSERT INTO hukuk.sozlesme_onay (kiraci_id, sozlesme_id, tur_no, adim_sira, adim_kodu, kullanici_id, karar, notu) " \
           "VALUES (%s, %s, %s, %s, 'hukuk', %s, %s, %s)"
    # Taslaktaki sözleşmeye onay yazılamaz.
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute(ekle, (veri["k1"], s, 0, 0, veri["ayse"], "onay", ""))
    u.c.execute("UPDATE hukuk.sozlesme SET durum = 'onayda', onay_turu = 1 WHERE id = %s", (s,))
    with pytest.raises(psycopg.errors.CheckViolation):  # başkası adına
        u.c.execute(ekle, (veri["k1"], s, 1, 0, veri["mert"], "onay", ""))
    with pytest.raises(psycopg.errors.CheckViolation):  # eski tur
        u.c.execute(ekle, (veri["k1"], s, 0, 0, veri["ayse"], "onay", ""))
    u.c.execute(ekle, (veri["k1"], s, 1, 0, veri["ayse"], "revizyon", "Ceza şartı eksik"))
    with pytest.raises(psycopg.errors.CheckViolation):  # tur sonuçlandı
        u.c.execute(ekle, (veri["k1"], s, 1, 1, veri["ayse"], "onay", ""))


def test_talep_bekleme_ve_gecmis(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    t = u.deger("INSERT INTO hukuk.hukuk_talebi (kiraci_id, no, baslik, tur, oncelik, talep_eden, birim, sla_son_gun) "
                "VALUES (%s, 'HT-2026-0001', 'NDA', 'sozlesmeInceleme', 'normal', 'Satış', 'Satış', current_date + 3) "
                "RETURNING id", veri["k1"])
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.hukuk_talebi SET durum = 'bilgiBekleniyor' WHERE id = %s", (t,))
    u.c.execute("UPDATE hukuk.hukuk_talebi SET durum = 'bilgiBekleniyor', bekleme_baslangici = current_date WHERE id = %s", (t,))
    u.c.execute("INSERT INTO hukuk.talep_olayi (kiraci_id, talep_id, kullanici, aciklama) VALUES (%s, %s, 'ayse', 'Bilgi istendi')",
                (veri["k1"], t))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("DELETE FROM hukuk.talep_olayi")
    b = uygulama.oturum(veri["k2"], veri["baska"])
    assert b.deger("SELECT count(*) FROM hukuk.talep_olayi") == 0
