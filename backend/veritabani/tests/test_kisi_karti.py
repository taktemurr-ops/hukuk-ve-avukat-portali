"""Kişi kartı: unvan geçmişi yalnızca büyür, tür değişmez; ilişkiler kiracı içinde ve tekil."""
import psycopg
import pytest


def _kisi(u, k, ad, tur="tuzel"):
    return u.deger("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, %s, %s) RETURNING id", k, tur, ad)


def test_unvan_gecmisi(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    k = _kisi(u, veri["k1"], "Delta İnşaat Ltd. Şti.")
    u.c.execute("UPDATE hukuk.kisi SET ad = 'Delta Yapı A.Ş.', telefon = '0212 000 00 00', tur = 'gercek', "
                "unvan_gecmisi = '[]' WHERE id = %s", (k,))
    ad, tur, gecmis, tel = u.c.execute("SELECT ad, tur, unvan_gecmisi, telefon FROM hukuk.kisi WHERE id = %s", (k,)).fetchone()
    assert (ad, tur, tel) == ("Delta Yapı A.Ş.", "tuzel", "0212 000 00 00")
    assert [g["unvan"] for g in gecmis] == ["Delta İnşaat Ltd. Şti."]
    # Geçmiş istemciden silinemez; ad değişmeden yapılan güncelleme geçmişe dokunmaz.
    u.c.execute("UPDATE hukuk.kisi SET unvan_gecmisi = '[]', adres = 'İstanbul' WHERE id = %s", (k,))
    assert len(u.deger("SELECT unvan_gecmisi FROM hukuk.kisi WHERE id = %s", k)) == 1
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.kisi SET mersis_no = '123' WHERE id = %s", (k,))


def test_iliski(uygulama, veri, yonetici):
    u = uygulama.oturum(veri["k1"], veri["mert"])
    a, b = _kisi(u, veri["k1"], "ABC Holding"), _kisi(u, veri["k1"], "ABC Gıda")
    u.c.execute("INSERT INTO hukuk.kisi_iliski (kiraci_id, kisi_a, kisi_b, tur) VALUES (%s, %s, %s, 'istirak')", (veri["k1"], a, b))
    assert u.deger("SELECT olusturan FROM hukuk.kisi_iliski WHERE kisi_a = %s", a) == veri["mert"]
    with pytest.raises(psycopg.errors.UniqueViolation):  # ters yönde aynı ilişki
        u.c.execute("INSERT INTO hukuk.kisi_iliski (kiraci_id, kisi_a, kisi_b, tur) VALUES (%s, %s, %s, 'istirak')", (veri["k1"], b, a))
    baska = yonetici.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'tuzel', 'Yabancı') RETURNING id",
                             (veri["k2"],)).fetchone()[0]
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        u.c.execute("INSERT INTO hukuk.kisi_iliski (kiraci_id, kisi_a, kisi_b, tur) VALUES (%s, %s, %s, 'ortak')", (veri["k1"], a, baska))
    # Başka kiracı göremez.
    assert uygulama.oturum(veri["k2"], veri["baska"]).deger("SELECT count(*) FROM hukuk.kisi_iliski") == 0
