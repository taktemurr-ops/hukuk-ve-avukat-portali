import uuid

import psycopg
import pytest


def test_kiraci_ayrimi(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    assert sorted(u.liste("SELECT ad FROM hukuk.kiraci")) == ["Yılmaz Hukuk"]
    assert "Başkasının dosyası" not in u.liste("SELECT baslik FROM hukuk.dosya")
    assert u.deger("SELECT count(*) FROM hukuk.kullanici") == 3
    u.oturum(veri["k2"], veri["baska"])
    assert u.liste("SELECT baslik FROM hukuk.dosya") == ["Başkasının dosyası"]


def test_baska_kiraciya_yazilamaz(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'gercek', 'Sızma')", (veri["k2"],))


def test_oturum_ayarlanmazsa_hicbir_sey_gorunmez(uygulama, veri):
    assert uygulama.deger("SELECT count(*) FROM hukuk.dosya") == 0


def test_gizli_dosya_ve_etik_duvar(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    gorunen = u.liste("SELECT baslik FROM hukuk.dosya")
    assert "Açık dosya" in gorunen
    assert "Gizli soruşturma" not in gorunen
    assert "Duvarlı dosya" not in gorunen
    # Dosyası görünmeyen süre de görünmez.
    assert u.liste("SELECT aciklama FROM hukuk.sure_kaydi") == ["Cevap dilekçesi"]

    u.oturum(veri["k1"], veri["ayse"])
    gorunen = u.liste("SELECT baslik FROM hukuk.dosya")
    assert {"Açık dosya", "Gizli soruşturma", "Duvarlı dosya"} <= set(gorunen)

    u.oturum(veri["k1"], veri["elif"])
    assert "Gizli soruşturma" not in u.liste("SELECT baslik FROM hukuk.dosya")


def test_etik_duvar_yoneticiyi_de_engeller_ve_kaldirilabilir(uygulama, veri, yonetici):
    yonetici.execute("INSERT INTO hukuk.etik_duvar (kiraci_id, dosya_id, kullanici_id, gerekce, kuran) VALUES (%s, %s, %s, %s, %s)",
                     (veri["k1"], veri["d"]["gizli"], veri["ayse"], "Yöneticiyi de engelleyen duvar", veri["mert"]))
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    assert "Gizli soruşturma" not in u.liste("SELECT baslik FROM hukuk.dosya")
    u.oturum(veri["k1"], veri["mert"])
    u.c.execute("UPDATE hukuk.etik_duvar SET kaldiran = %s, kaldirma_gerekcesi = %s, kaldirma = now() WHERE dosya_id = %s",
                (veri["mert"], "Çatışma sona erdi ve onay alındı", veri["d"]["gizli"]))
    u.oturum(veri["k1"], veri["ayse"])
    assert "Gizli soruşturma" in u.liste("SELECT baslik FROM hukuk.dosya")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("DELETE FROM hukuk.etik_duvar")
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.etik_duvar SET kaldiran = %s, kaldirma = now() WHERE dosya_id = %s",
                    (veri["ayse"], veri["d"]["duvarli"]))


def test_kendine_duvar_ve_kisa_gerekce_reddedilir(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("INSERT INTO hukuk.etik_duvar (kiraci_id, dosya_id, kullanici_id, gerekce, kuran) VALUES (%s, %s, %s, %s, %s)",
                    (veri["k1"], veri["d"]["acik"], veri["ayse"], "Kendime duvar kuruyorum", veri["ayse"]))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("INSERT INTO hukuk.etik_duvar (kiraci_id, dosya_id, kullanici_id, gerekce, kuran) VALUES (%s, %s, %s, %s, %s)",
                    (veri["k1"], veri["d"]["acik"], veri["elif"], "kısa", veri["ayse"]))


def test_sure_dort_goz_ve_kanit(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.sure_kaydi SET durum = 'teyitli', teyit_eden = olusturan, teyit_zamani = now() "
                    "WHERE aciklama = 'Cevap dilekçesi'")
    u.c.execute("UPDATE hukuk.sure_kaydi SET durum = 'teyitli', teyit_eden = %s, teyit_zamani = now() "
                "WHERE aciklama = 'Cevap dilekçesi'", (veri["mert"],))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.sure_kaydi SET durum = 'tamamlandi' WHERE aciklama = 'Cevap dilekçesi'")
    u.c.execute("UPDATE hukuk.sure_kaydi SET durum = 'tamamlandi', kanit = 'UYAP 2026-123456' WHERE aciklama = 'Cevap dilekçesi'")
    # Görmediği dosyanın süresini güncelleyemez (satır görünmez, 0 satır etkilenir).
    sonuc = u.c.execute("UPDATE hukuk.sure_kaydi SET aciklama = 'x' WHERE aciklama = 'Gizli süre'")
    assert sonuc.rowcount == 0


def test_denetim_zinciri_ve_degistirilemezlik(uygulama, veri, yonetici):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    for i in range(3):
        u.c.execute("INSERT INTO hukuk.denetim_kaydi (kiraci_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet) "
                    "VALUES (%s, 'goruntuleme', 'dosya', %s, '', '', '')", (veri["k1"], f"d{i}"))
    satirlar = u.c.execute("SELECT sira, onceki_ozet, ozet, kullanici_id FROM hukuk.denetim_kaydi ORDER BY sira").fetchall()
    assert [s[0] for s in satirlar] == [1, 2, 3]
    assert satirlar[0][1] == "0" * 64
    assert satirlar[1][1] == satirlar[0][2]
    assert satirlar[2][3] == veri["ayse"]
    assert u.deger("SELECT hukuk.denetim_dogrula(%s)", veri["k1"]) is None

    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("UPDATE hukuk.denetim_kaydi SET aciklama = 'silindi'")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("DELETE FROM hukuk.denetim_kaydi")

    # Veritabanı yöneticisi bile değiştirse zincir bozulduğu yeri gösterir.
    yonetici.execute("UPDATE hukuk.denetim_kaydi SET aciklama = 'oynandı' WHERE kiraci_id = %s AND sira = 2", (veri["k1"],))
    assert u.deger("SELECT hukuk.denetim_dogrula(%s)", veri["k1"]) == 2


def test_belge_surumu_degistirilemez_ve_ozet_bicimi(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    b = u.deger("INSERT INTO hukuk.belge (kiraci_id, dosya_id, ad, tur) VALUES (%s, %s, 'Dilekçe', 'dilekce') RETURNING id",
                veri["k1"], veri["d"]["acik"])
    ozet = "a" * 64
    u.c.execute("INSERT INTO hukuk.belge_surum (belge_id, kiraci_id, no, sha256, boyut, dosya_adi, yukleyen, depo_anahtari) "
                "VALUES (%s, %s, 1, %s, 10, 'd.pdf', %s, 'tr-ist/1')", (b, veri["k1"], ozet, veri["mert"]))
    with pytest.raises(psycopg.errors.UniqueViolation):
        u.c.execute("INSERT INTO hukuk.belge_surum (belge_id, kiraci_id, no, sha256, boyut, dosya_adi, yukleyen, depo_anahtari) "
                    "VALUES (%s, %s, 2, %s, 10, 'd.pdf', %s, 'tr-ist/2')", (b, veri["k1"], ozet, veri["mert"]))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("INSERT INTO hukuk.belge_surum (belge_id, kiraci_id, no, sha256, boyut, dosya_adi, yukleyen, depo_anahtari) "
                    "VALUES (%s, %s, 3, 'ZZ', 10, 'd.pdf', %s, 'x')", (b, veri["k1"], veri["mert"]))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("UPDATE hukuk.belge_surum SET boyut = 0")


def test_veri_yalnizca_turkiyede_ve_sifre_ozeti(yonetici):
    with pytest.raises(psycopg.errors.CheckViolation):
        yonetici.execute("INSERT INTO hukuk.kiraci (ad, hesap_turu, veri_bolgesi) VALUES ('X', 'kurumsal', 'EU')")
    k = yonetici.execute("INSERT INTO hukuk.kiraci (ad, hesap_turu) VALUES ('Y', 'kurumsal') RETURNING id").fetchone()[0]
    with pytest.raises(psycopg.errors.CheckViolation):
        yonetici.execute("INSERT INTO hukuk.kullanici (kiraci_id, eposta, ad_soyad, sifre_ozeti) VALUES (%s, 'a@b.com', 'A', 'duzsifre')",
                         (k,))
    yonetici.execute("INSERT INTO hukuk.kullanici (kiraci_id, eposta, ad_soyad, sifre_ozeti) VALUES (%s, 'a@b.com', 'A', %s)",
                     (k, "$argon2id$v=19$x"))
    with pytest.raises(psycopg.errors.UniqueViolation):
        yonetici.execute("INSERT INTO hukuk.kullanici (kiraci_id, eposta, ad_soyad, sifre_ozeti) VALUES (%s, 'A@B.com', 'A', %s)",
                         (k, "$argon2id$v=19$x"))
