"""Dış avukat faturası: bütçe aşımı onaylanamaz, geçişler ileri, numara tekil, kapalı işe fatura yok."""
import psycopg
import pytest


def _is(u, kiraci, butce=1_000_000):
    a = u.deger("INSERT INTO hukuk.dis_avukat (kiraci_id, buro, sorumlu_avukat, eposta) "
                "VALUES (%s, 'Kaya Hukuk', 'Av. Deniz Kaya', 'deniz@kaya.av.tr') RETURNING id", kiraci)
    return u.deger("INSERT INTO hukuk.dis_avukat_isi (kiraci_id, dis_avukat_id, konu, ilk_butce_kurus) "
                   "VALUES (%s, %s, 'Rekabet soruşturması', %s) RETURNING id", kiraci, a, butce)


def _fatura(u, kiraci, isi, no, tutar):
    return u.deger("INSERT INTO hukuk.dis_avukat_faturasi (kiraci_id, isi_id, no, tarih, tutar_kurus) "
                   "VALUES (%s, %s, %s, current_date, %s) RETURNING id", kiraci, isi, no, tutar)


def test_butce_asimi_ve_gecisler(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    isi = _is(u, veri["k1"])
    f1 = _fatura(u, veri["k1"], isi, "KH-1", 700_000)
    f2 = _fatura(u, veri["k1"], isi, "KH-2", 400_000)
    with pytest.raises(psycopg.errors.UniqueViolation):
        _fatura(u, veri["k1"], isi, " kh-1 ", 1)
    onay = "UPDATE hukuk.dis_avukat_faturasi SET durum = 'onaylandi', onaylayan = %s WHERE id = %s"
    u.c.execute(onay, (veri["ayse"], f1))
    with pytest.raises(psycopg.errors.CheckViolation, match="bütçeyi aşıyor"):
        u.c.execute(onay, (veri["ayse"], f2))
    with pytest.raises(psycopg.errors.CheckViolation):  # kısa gerekçeyle artış
        u.c.execute("INSERT INTO hukuk.dis_avukat_butce_artisi (kiraci_id, isi_id, tutar_kurus, gerekce) VALUES (%s, %s, 200000, 'kısa')",
                    (veri["k1"], isi))
    u.c.execute("INSERT INTO hukuk.dis_avukat_butce_artisi (kiraci_id, isi_id, tutar_kurus, gerekce) "
                "VALUES (%s, %s, 200000, 'Ek bilirkişi incelemesi gerekti')", (veri["k1"], isi))
    u.c.execute(onay, (veri["ayse"], f2))
    with pytest.raises(psycopg.errors.CheckViolation):  # geri gidilemez
        u.c.execute("UPDATE hukuk.dis_avukat_faturasi SET durum = 'bekliyor', onaylayan = NULL WHERE id = %s", (f1,))
    with pytest.raises(psycopg.errors.CheckViolation):  # tutar değiştirilemez
        u.c.execute("UPDATE hukuk.dis_avukat_faturasi SET tutar_kurus = 1 WHERE id = %s", (f1,))
    u.c.execute("UPDATE hukuk.dis_avukat_faturasi SET durum = 'finansaGonderildi' WHERE id = %s", (f1,))


def test_kapali_ise_fatura_eklenemez_ve_kiraci_ayrimi(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    isi = _is(u, veri["k1"])
    u.c.execute("UPDATE hukuk.dis_avukat_isi SET kapali = true WHERE id = %s", (isi,))
    with pytest.raises(psycopg.errors.CheckViolation, match="Kapalı"):
        _fatura(u, veri["k1"], isi, "X-1", 100)
    b = uygulama.oturum(veri["k2"], veri["baska"])
    assert b.deger("SELECT count(*) FROM hukuk.dis_avukat_isi") == 0
