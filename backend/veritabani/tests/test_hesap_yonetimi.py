"""Ekip yönetimi: rol değiştirme kuralları, pasifleştirmede devir, en az bir yönetici; şifre ve oturum yönetimi."""
import psycopg
import pytest


def test_rol_degistirme(uygulama, veri, yonetici):
    ayse = uygulama.oturum(veri["k1"], veri["ayse"])
    ayse.c.execute("SELECT hukuk.kullanici_rolleri_degistir(%s, ARRAY['avukat', 'muhasebe'])", (veri["elif"],))
    assert sorted(ayse.liste("SELECT rol FROM hukuk.kullanici_rol WHERE kullanici_id = %s", veri["elif"])) == ["avukat", "muhasebe"]
    assert ayse.deger("SELECT count(*) FROM hukuk.denetim_kaydi WHERE islem = 'rolVerme'") == 1
    with pytest.raises(psycopg.errors.CheckViolation):  # kurumsal rol hukuk bürosunda olmaz
        ayse.c.execute("SELECT hukuk.kullanici_rolleri_degistir(%s, ARRAY['hukukDirektoru'])", (veri["elif"],))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):  # kendi rolü
        ayse.c.execute("SELECT hukuk.kullanici_rolleri_degistir(%s, ARRAY['avukat'])", (veri["ayse"],))
    mert = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):  # yönetici değil
        mert.c.execute("SELECT hukuk.kullanici_rolleri_degistir(%s, ARRAY['stajyer'])", (veri["elif"],))


def test_son_yonetici_korunur(uygulama, veri):
    ayse = uygulama.oturum(veri["k1"], veri["ayse"])
    ayse.c.execute("SELECT hukuk.kullanici_rolleri_degistir(%s, ARRAY['yoneticiOrtak'])", (veri["mert"],))
    mert = uygulama.oturum(veri["k1"], veri["mert"])
    mert.c.execute("SELECT hukuk.kullanici_rolleri_degistir(%s, ARRAY['avukat'])", (veri["ayse"],))  # mert hâlâ yönetici
    with pytest.raises(psycopg.errors.InsufficientPrivilege):  # ayse artık yönetici değil
        uygulama.oturum(veri["k1"], veri["ayse"]).c.execute(
            "SELECT hukuk.kullanici_rolleri_degistir(%s, ARRAY['avukat'])", (veri["mert"],))


def test_pasiflestirmede_devir(uygulama, veri, yonetici):
    ayse = uygulama.oturum(veri["k1"], veri["ayse"])
    yonetici.execute("SELECT hukuk.oturum_ac(%s, %s, interval '1 day', 'test')", ("b" * 64, veri["mert"]))
    with pytest.raises(psycopg.errors.CheckViolation):  # açık süresi ve dosyası var, devralan yok
        ayse.c.execute("SELECT hukuk.kullanici_pasiflestir(%s, NULL, 'İstifa')", (veri["mert"],))
    n = ayse.deger("SELECT hukuk.kullanici_pasiflestir(%s, %s, 'İstifa etti')", veri["mert"], veri["ayse"])
    assert n >= 2  # süre + dosya
    assert yonetici.execute("SELECT asil_sorumlu FROM hukuk.sure_kaydi WHERE aciklama = 'Cevap dilekçesi' AND kiraci_id = %s",
                            (veri["k1"],)).fetchone()[0] == veri["ayse"]
    assert yonetici.execute("SELECT sorumlu FROM hukuk.dosya WHERE id = %s", (veri["d"]["acik"],)).fetchone()[0] == veri["ayse"]
    assert uygulama.c.execute("SELECT * FROM hukuk.oturum_coz(%s)", ("b" * 64,)).fetchall() == []
    with pytest.raises(psycopg.errors.CheckViolation):  # koltuk dolu
        ayse.c.execute("SELECT hukuk.kullanici_aktiflestir(%s)", (veri["mert"],))
    yonetici.execute("INSERT INTO hukuk.abonelik (kiraci_id, durum, donem, donem_basi, donem_sonu, ucretli_koltuk) "
                     "VALUES (%s, 'aktif', 'aylik', current_date, current_date + 30, 5) "
                     "ON CONFLICT (kiraci_id) DO UPDATE SET ucretli_koltuk = 5", (veri["k1"],))
    ayse.c.execute("SELECT hukuk.kullanici_aktiflestir(%s)", (veri["mert"],))
    assert yonetici.execute("SELECT aktif FROM hukuk.kullanici WHERE id = %s", (veri["mert"],)).fetchone()[0] is True


def test_sifre_ve_oturumlar(uygulama, veri, yonetici):
    for t in ("c", "d", "e"):
        yonetici.execute("SELECT hukuk.oturum_ac(%s, %s, interval '1 day', %s)", (t * 64, veri["elif"], f"cihaz {t}"))
    elif_ = uygulama.oturum(veri["k1"], veri["elif"])
    ot = elif_.c.execute("SELECT kimlik, bu_oturum FROM hukuk.kendi_oturumlarim(%s)", ("c" * 64,)).fetchall()
    assert len(ot) == 3 and sum(1 for _, b in ot if b) == 1
    assert elif_.deger("SELECT hukuk.kendi_oturumlarimi_kapat(%s, %s)", "d" * 12, "c" * 64) == 1
    assert elif_.deger("SELECT hukuk.kendi_oturumlarimi_kapat(%s, %s)", "c" * 12, "c" * 64) == 0  # bu oturum kapanmaz
    assert elif_.deger("SELECT hukuk.kendi_sifre_ozetim()").startswith("$argon2id$")
    elif_.c.execute("SELECT hukuk.sifre_degistir(%s, %s)", ("$argon2id$v=19$m=65536,t=3,p=4$eQ$eQ", "c" * 64))
    kalan = [r[0] for r in elif_.c.execute("SELECT kimlik FROM hukuk.kendi_oturumlarim(%s)", ("c" * 64,)).fetchall()]
    assert kalan == ["c" * 12]
    # Başkasının oturumunu kapatamaz.
    yonetici.execute("SELECT hukuk.oturum_ac(%s, %s, interval '1 day', 'x')", ("f" * 64, veri["ayse"]))
    assert elif_.deger("SELECT hukuk.kendi_oturumlarimi_kapat(%s, %s)", "f" * 12, "c" * 64) == 0
