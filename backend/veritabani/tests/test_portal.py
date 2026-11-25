"""Müvekkil portalı: yalnızca paylaşılan ve müvekkili olduğu dosyalar; büro tablolarına doğrudan erişim yok."""
import uuid

import psycopg
import pytest

OZET = "$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA"


@pytest.fixture
def portal(veri, yonetici):
    k1, d = veri["k1"], veri["d"]
    kisi = yonetici.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'tuzel', 'ABC Gıda A.Ş.') RETURNING id",
                            (k1,)).fetchone()[0]
    baska_kisi = yonetici.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'gercek', 'Karşı Taraf') RETURNING id",
                                  (k1,)).fetchone()[0]
    m = uuid.uuid4()
    yonetici.execute("INSERT INTO hukuk.kullanici (id, kiraci_id, eposta, ad_soyad, sifre_ozeti, kisi_id) "
                     "VALUES (%s, %s, 'm@abc.com.tr', 'Ali Veli', %s, %s)", (m, k1, OZET, kisi))
    yonetici.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'muvekkil')", (k1, m))
    # Açık dosyada müvekkil, duvarlı dosyada karşı taraf; gizli dosyada müvekkil ama paylaşılmamış.
    yonetici.execute("INSERT INTO hukuk.dosya_taraf VALUES (%s, %s, %s, 'muvekkil'), (%s, %s, %s, 'muvekkil'), "
                     "(%s, %s, %s, 'muvekkil'), (%s, %s, %s, 'karsiTaraf')",
                     (k1, d["acik"], kisi, k1, d["gizli"], kisi, k1, d["duvarli"], baska_kisi, k1, d["duvarli"], kisi))
    yonetici.execute("INSERT INTO hukuk.portal_paylasim (dosya_id, kiraci_id, paylasan) VALUES (%s, %s, %s), (%s, %s, %s)",
                     (d["acik"], k1, veri["mert"], d["duvarli"], k1, veri["ayse"]))
    b1 = yonetici.execute("INSERT INTO hukuk.belge (kiraci_id, dosya_id, ad, tur, portalda) VALUES (%s, %s, 'Dava dilekçesi', "
                          "'dilekce', true) RETURNING id", (k1, d["acik"])).fetchone()[0]
    b2 = yonetici.execute("INSERT INTO hukuk.belge (kiraci_id, dosya_id, ad, tur) VALUES (%s, %s, 'İç not', 'diger') RETURNING id",
                          (k1, d["acik"])).fetchone()[0]
    for b in (b1, b2):
        yonetici.execute("INSERT INTO hukuk.belge_surum (belge_id, kiraci_id, no, sha256, boyut, dosya_adi, yukleyen, depo_anahtari) "
                         "VALUES (%s, %s, 1, %s, 10, 'a.pdf', %s, 'x')", (b, k1, "a" * 64, veri["mert"]))
    return {"kullanici": m, "kisi": kisi, "b1": b1, "b2": b2}


def _portal_oturumu(uygulama, veri, p):
    u = uygulama
    u.c.execute("SELECT set_config('app.kiraci_id', '', false), set_config('app.kullanici_id', %s, false), "
                "set_config('app.portal_kisi', %s, false)", (str(p["kullanici"]), str(p["kisi"])))
    return u


def test_muvekkil_yalnizca_paylasilan_ve_muvekkili_oldugu_dosyayi_gorur(uygulama, veri, portal):
    u = _portal_oturumu(uygulama, veri, portal)
    dosyalar = u.c.execute("SELECT id, baslik FROM hukuk.portal_dosyalari()").fetchall()
    assert [r[1] for r in dosyalar] == ["Açık dosya"]  # gizli: paylaşılmadı; duvarlı: karşı taraf
    # Büro tabloları doğrudan görünmez.
    for tablo in ["dosya", "kisi", "kullanici", "belge", "sure_kaydi", "portal_mesaj"]:
        assert u.deger(f"SELECT count(*) FROM hukuk.{tablo}") == 0
    belgeler = u.c.execute("SELECT ad FROM hukuk.portal_belgeleri(%s)", (veri["d"]["acik"],)).fetchall()
    assert belgeler == [("Dava dilekçesi",)]
    assert u.c.execute("SELECT * FROM hukuk.portal_belge_icerigi(%s)", (portal["b2"],)).fetchone() is None
    assert u.c.execute("SELECT * FROM hukuk.portal_belgeleri(%s)", (veri["d"]["duvarli"],)).fetchall() == []


def test_portal_mesajlasma(uygulama, veri, portal):
    u = _portal_oturumu(uygulama, veri, portal)
    u.c.execute("SELECT hukuk.portal_mesaj_gonder(%s, 'Duruşma ne zaman?')", (veri["d"]["acik"],))
    with pytest.raises(psycopg.errors.NoDataFound):
        u.c.execute("SELECT hukuk.portal_mesaj_gonder(%s, 'x')", (veri["d"]["gizli"],))
    # Avukat (dosyayı gören) yanıtlar.
    a = uygulama.oturum(veri["k1"], veri["mert"])
    a.c.execute("SELECT set_config('app.portal_kisi', '', false)")
    assert a.deger("SELECT count(*) FROM hukuk.portal_mesaj WHERE muvekkilden") == 1
    a.c.execute("INSERT INTO hukuk.portal_mesaj (kiraci_id, dosya_id, gonderen, muvekkilden, metin) VALUES (%s, %s, %s, false, %s)",
                (veri["k1"], veri["d"]["acik"], veri["mert"], "3 Aralık 10.30"))
    u = _portal_oturumu(uygulama, veri, portal)
    assert u.c.execute("SELECT okunmamis FROM hukuk.portal_dosyalari()").fetchone()[0] == 1
    u.c.execute("SELECT hukuk.portal_mesajlari_oku(%s)", (veri["d"]["acik"],))
    assert u.c.execute("SELECT okunmamis FROM hukuk.portal_dosyalari()").fetchone()[0] == 0
    assert [r[0] for r in u.c.execute("SELECT metin FROM hukuk.portal_mesajlari(%s)", (veri["d"]["acik"],))] == \
        ["Duruşma ne zaman?", "3 Aralık 10.30"]


def test_pasif_muvekkil_ve_baskasinin_kisisi_erisemez(uygulama, veri, portal, yonetici):
    u = _portal_oturumu(uygulama, veri, portal)
    # Kendi kişisi yerine başka kişi ayarlansa bile kullanıcının kişi kartıyla eşleşmez.
    u.c.execute("SELECT set_config('app.portal_kisi', %s, false)", (str(uuid.uuid4()),))
    assert u.c.execute("SELECT count(*) FROM hukuk.portal_dosyalari()").fetchone()[0] == 0
    yonetici.execute("UPDATE hukuk.kullanici SET aktif = false WHERE id = %s", (portal["kullanici"],))
    u = _portal_oturumu(uygulama, veri, portal)
    assert u.c.execute("SELECT count(*) FROM hukuk.portal_dosyalari()").fetchone()[0] == 0
