"""Takvim bağlantısı: kişiye özel, yenilenince eskisi geçersiz, pasif hesapta çalışmaz."""


def test_takvim_baglantisi(uygulama, veri, yonetici):
    mert = uygulama.oturum(veri["k1"], veri["mert"])
    mert.c.execute("SELECT hukuk.takvim_baglantisi_olustur(%s)", ("a" * 64,))
    assert uygulama.c.execute("SELECT * FROM hukuk.takvim_sahibi(%s)", ("a" * 64,)).fetchall() == [(veri["mert"], veri["k1"])]
    mert.c.execute("SELECT hukuk.takvim_baglantisi_olustur(%s)", ("b" * 64,))  # yenileme
    assert uygulama.c.execute("SELECT * FROM hukuk.takvim_sahibi(%s)", ("a" * 64,)).fetchall() == []
    assert mert.c.execute("SELECT son_okuma FROM hukuk.takvim_baglantisi_var()").fetchone()[0] is None
    uygulama.c.execute("SELECT * FROM hukuk.takvim_sahibi(%s)", ("b" * 64,))
    assert mert.c.execute("SELECT son_okuma FROM hukuk.takvim_baglantisi_var()").fetchone()[0] is not None
    yonetici.execute("UPDATE hukuk.kullanici SET aktif = false WHERE id = %s", (veri["mert"],))
    assert uygulama.c.execute("SELECT * FROM hukuk.takvim_sahibi(%s)", ("b" * 64,)).fetchall() == []
    yonetici.execute("UPDATE hukuk.kullanici SET aktif = true WHERE id = %s", (veri["mert"],))
    assert mert.deger("SELECT hukuk.takvim_baglantisi_kapat()") is True
    assert uygulama.c.execute("SELECT * FROM hukuk.takvim_sahibi(%s)", ("b" * 64,)).fetchall() == []


def test_portal_kullanicisi_sifre_degistirir(uygulama, veri, yonetici):
    # Portal oturumu: kiracı bağlamı boş, yalnızca kullanıcı.
    uygulama.c.execute("SELECT set_config('app.kiraci_id', '', false), set_config('app.kullanici_id', %s, false)",
                       (str(veri["elif"]),))
    uygulama.c.execute("SELECT hukuk.sifre_degistir(%s, %s)", ("$argon2id$v=19$m=65536,t=3,p=4$eg$eg", "z" * 64))
    assert yonetici.execute("SELECT kiraci_id FROM hukuk.denetim_kaydi WHERE nesne_id = %s AND aciklama LIKE 'Şifre%%'",
                            (str(veri["elif"]),)).fetchone()[0] == veri["k1"]
