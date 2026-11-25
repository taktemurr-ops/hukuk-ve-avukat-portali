"""E-posta kuyruğu: doğrudan okunamaz, sırayla alınır, hatada yeniden denenir, başarıda içerik silinir."""
import psycopg
import pytest


def test_kuyruk_akisi(uygulama, veri, yonetici):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    i = u.deger("SELECT hukuk.eposta_ekle(%s, 'Selin@Ornek.com.tr', 'Davet', 'gizli bağlantı', 'davet')", veri["k1"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        u.c.execute("SELECT * FROM hukuk.eposta_kuyrugu")
    alinan = u.c.execute("SELECT id, alici FROM hukuk.eposta_al(10)").fetchall()
    assert alinan == [(i, "selin@ornek.com.tr")]
    assert u.c.execute("SELECT * FROM hukuk.eposta_al(10)").fetchall() == []  # zaten alındı
    u.c.execute("SELECT hukuk.eposta_sonuc(%s, false, 'SMTP 421')", (i,))
    durum, deneme, sonraki = yonetici.execute(
        "SELECT durum, deneme, sonraki_deneme > now() + interval '4 minutes' FROM hukuk.eposta_kuyrugu WHERE id = %s", (i,)).fetchone()
    assert (durum, deneme, sonraki) == ("bekliyor", 1, True)
    yonetici.execute("UPDATE hukuk.eposta_kuyrugu SET sonraki_deneme = now() WHERE id = %s", (i,))
    assert len(u.c.execute("SELECT * FROM hukuk.eposta_al(10)").fetchall()) == 1
    u.c.execute("SELECT hukuk.eposta_sonuc(%s, true, NULL)", (i,))
    assert yonetici.execute("SELECT durum, metin FROM hukuk.eposta_kuyrugu WHERE id = %s", (i,)).fetchone() == ("gonderildi", "")


def test_bes_denemeden_sonra_hata(uygulama, veri, yonetici):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    i = u.deger("SELECT hukuk.eposta_ekle(NULL, 'a@b.com', 'K', 'M', 'deneme')")
    for _ in range(5):
        yonetici.execute("UPDATE hukuk.eposta_kuyrugu SET sonraki_deneme = now() WHERE id = %s", (i,))
        assert len(u.c.execute("SELECT * FROM hukuk.eposta_al(1)").fetchall()) == 1
        u.c.execute("SELECT hukuk.eposta_sonuc(%s, false, 'hata')", (i,))
    assert yonetici.execute("SELECT durum FROM hukuk.eposta_kuyrugu WHERE id = %s", (i,)).fetchone()[0] == "hata"
