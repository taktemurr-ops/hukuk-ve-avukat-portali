"""E-posta doğrulama: kayıtta başlar, kodla tamamlanır, eski hesaplar kilitlenemez, yeniden gönderim sınırlı."""
import hashlib
import uuid

import psycopg
import pytest

OZET = "$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA"


def ozet(kod):
    return hashlib.sha256(kod.encode()).hexdigest()


def test_kayit_dogrulama_akisi(uygulama, yonetici):
    eposta = f"yeni.{uuid.uuid4().hex[:6]}@buro.com.tr"
    k, u = uygulama.c.execute("SELECT * FROM hukuk.hesap_ac('Yeni Büro', 'avukatlikBurosu', %s, 'Av. Yeni', %s)",
                              (eposta, OZET)).fetchone()
    kod = uuid.uuid4().hex
    uygulama.c.execute("SELECT hukuk.eposta_dogrulama_baslat(%s, %s, 'Doğrulama', %s)", (u, ozet(kod), f"kod {kod}"))
    assert uygulama.deger("SELECT hukuk.eposta_dogrulandi_mi(%s)", u) is False
    assert yonetici.execute("SELECT count(*) FROM hukuk.eposta_kuyrugu WHERE alici = %s AND tur = 'epostaDogrulama'",
                            (eposta,)).fetchone()[0] == 1
    assert uygulama.deger("SELECT hukuk.eposta_dogrula(%s)", ozet(kod)) == 1
    assert uygulama.deger("SELECT hukuk.eposta_dogrulandi_mi(%s)", u) is True
    with pytest.raises(psycopg.errors.InvalidParameterValue):
        uygulama.deger("SELECT hukuk.eposta_dogrula(%s)", ozet(kod))


def test_eski_hesap_kilitlenemez_ve_davetliler_dogrulanmis(uygulama, veri, yonetici):
    assert uygulama.deger("SELECT hukuk.eposta_dogrulandi_mi(%s)", veri["mert"]) is True
    yonetici.execute("UPDATE hukuk.kullanici SET olusturma = now() - interval '1 day' WHERE id = %s", (veri["mert"],))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        uygulama.c.execute("SELECT hukuk.eposta_dogrulama_baslat(%s, %s, 'x', 'y')", (veri["mert"], ozet("z" + str(veri["k1"]))))


def test_yenileme_sessiz_ve_sinirli(uygulama, yonetici):
    eposta = f"sinir.{uuid.uuid4().hex[:6]}@buro.com.tr"
    k, u = uygulama.c.execute("SELECT * FROM hukuk.hesap_ac('Sınır Büro', 'avukatlikBurosu', %s, 'Av. S', %s)",
                              (eposta, OZET)).fetchone()
    uygulama.c.execute("SELECT hukuk.eposta_dogrulama_baslat(%s, %s, 'D', 'm')", (u, ozet(eposta + "0")))
    for i in range(1, 6):
        uygulama.c.execute("SELECT hukuk.eposta_dogrulama_yenile(%s, %s, 'D', 'm')", (eposta, ozet(eposta + str(i))))
    assert yonetici.execute("SELECT count(*) FROM hukuk.eposta_dogrulama WHERE eposta = %s", (eposta,)).fetchone()[0] == 3
    # Doğrulanmış ya da olmayan adres için hiçbir şey olmaz.
    uygulama.c.execute("SELECT hukuk.eposta_dogrulama_yenile('yok@ornek.com.tr', %s, 'D', 'm')", (ozet("q"),))
    assert yonetici.execute("SELECT count(*) FROM hukuk.eposta_dogrulama WHERE eposta = 'yok@ornek.com.tr'").fetchone()[0] == 0
