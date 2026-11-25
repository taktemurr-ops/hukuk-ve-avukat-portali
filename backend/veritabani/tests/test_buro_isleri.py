"""Görev, duruşma, tebligat, dosya tarafı ve vekâletname kuralları."""
import psycopg
import pytest


def _kisi(yonetici, kiraci, ad="ABC Gıda A.Ş."):
    return yonetici.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'tuzel', %s) RETURNING id",
                            (kiraci, ad)).fetchone()[0]


def test_gizli_dosyanin_gorev_ve_durusmasi_gorunmez(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    u.c.execute("INSERT INTO hukuk.gorev (kiraci_id, dosya_id, baslik, atanan) VALUES (%s, %s, 'Bilirkişi raporu incele', %s)",
                (veri["k1"], veri["d"]["gizli"], veri["ayse"]))
    u.c.execute("INSERT INTO hukuk.durusma (kiraci_id, dosya_id, baslangic, yer, katilan) "
                "VALUES (%s, %s, now() + interval '3 days', 'İstanbul 3. Asliye Ticaret', %s)",
                (veri["k1"], veri["d"]["gizli"], veri["ayse"]))
    u.c.execute("INSERT INTO hukuk.gorev (kiraci_id, baslik, atanan) VALUES (%s, 'Büro toplantısı', %s)", (veri["k1"], veri["elif"]))
    e = uygulama.oturum(veri["k1"], veri["elif"])
    assert e.deger("SELECT count(*) FROM hukuk.gorev") == 1
    assert e.deger("SELECT count(*) FROM hukuk.durusma") == 0
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        e.c.execute("INSERT INTO hukuk.durusma (kiraci_id, dosya_id, baslangic, yer, katilan) "
                    "VALUES (%s, %s, now(), 'x', %s)", (veri["k1"], veri["d"]["gizli"], veri["elif"]))


def test_sureden_dogan_gorev_kanitsiz_kapanamaz(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    g = u.deger("INSERT INTO hukuk.gorev (kiraci_id, dosya_id, baslik, atanan, kanit_gerekir) "
                "VALUES (%s, %s, 'İstinaf dilekçesi gönder', %s, true) RETURNING id", veri["k1"], veri["d"]["acik"], veri["mert"])
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.gorev SET durum = 'tamamlandi', kapanis = now() WHERE id = %s", (g,))
    u.c.execute("UPDATE hukuk.gorev SET durum = 'tamamlandi', kapanis = now(), kapanis_kaniti = 'UYAP 2026/99887' WHERE id = %s", (g,))


def test_tebligat_mukerrer_kaydedilmez(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    ekle = ("INSERT INTO hukuk.tebligat (kiraci_id, kanal, ulasma_tarihi, teblig_tarihi, gonderen, konu, tekillik) "
            "VALUES (%s, 'uets', '2026-11-20', '2026-11-25', 'İstanbul 3. Asliye Ticaret', 'Gerekçeli karar', 'k1')")
    u.c.execute(ekle, (veri["k1"],))
    with pytest.raises(psycopg.errors.UniqueViolation):
        u.c.execute(ekle, (veri["k1"],))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("INSERT INTO hukuk.tebligat (kiraci_id, kanal, ulasma_tarihi, teblig_tarihi, gonderen, konu, tekillik) "
                    "VALUES (%s, 'uets', '2026-11-20', '2026-11-19', 'x', 'y', 'k2')", (veri["k1"],))


def test_taraf_ve_vekaletname(uygulama, veri, yonetici):
    m = _kisi(yonetici, veri["k1"])
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    u.c.execute("INSERT INTO hukuk.dosya_taraf VALUES (%s, %s, %s, 'muvekkil')", (veri["k1"], veri["d"]["acik"], m))
    with pytest.raises(psycopg.errors.UniqueViolation):
        u.c.execute("INSERT INTO hukuk.dosya_taraf VALUES (%s, %s, %s, 'karsiTaraf')", (veri["k1"], veri["d"]["acik"], m))
    with pytest.raises(psycopg.errors.CheckViolation):  # özel vekâletname dosya ister
        u.c.execute("INSERT INTO hukuk.vekaletname (kiraci_id, muvekkil_id, avukatlar, duzenleme, genel) "
                    "VALUES (%s, %s, %s, '2026-01-05', false)", (veri["k1"], m, [veri["ayse"]]))
    v = u.deger("INSERT INTO hukuk.vekaletname (kiraci_id, muvekkil_id, avukatlar, duzenleme, ozel_yetkiler) "
                "VALUES (%s, %s, %s, '2026-01-05', '{sulh,ibra}') RETURNING id", veri["k1"], m, [veri["ayse"]])
    u.c.execute("UPDATE hukuk.vekaletname SET durum = 'azil', durum_tarihi = current_date WHERE id = %s", (v,))
    with pytest.raises(psycopg.errors.CheckViolation, match="Sona ermiş"):
        u.c.execute("UPDATE hukuk.vekaletname SET durum = 'gecerli', durum_tarihi = NULL WHERE id = %s", (v,))
    b = uygulama.oturum(veri["k2"], veri["baska"])
    assert b.deger("SELECT count(*) FROM hukuk.vekaletname") == 0


def test_dosya_numarasi_gizli_dosyalari_da_sayar(uygulama, veri):
    # Elif gizli dosyayı göremez ama numara çakışmaz.
    e = uygulama.oturum(veri["k1"], veri["elif"])
    assert e.deger("SELECT count(*) FROM hukuk.dosya") < 3
    # conftest: k1'de 2026/1-3 var (biri gizli); başka kiracının 2026/1'i sayılmaz.
    assert e.deger("SELECT hukuk.sonraki_dosya_no(2026)") == "2026/0004"
