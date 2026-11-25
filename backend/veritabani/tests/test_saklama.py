"""Saklama ve imha: yalnızca kapalı ve engelsiz dosyalar; dört göz; onay sonrası engel konulmuşsa reddedilir."""
import psycopg
import pytest


def test_imha_tutanagi(uygulama, veri, yonetici):
    yonetici.execute("UPDATE hukuk.dosya SET kapanis = '2014-05-01', acilis = '2010-01-01' WHERE id IN (%s, %s)",
                     (veri["d"]["acik"], veri["d"]["duvarli"]))
    yonetici.execute("INSERT INTO hukuk.kullanici_rol VALUES (%s, %s, 'yoneticiOrtak')", (veri["k1"], veri["mert"]))
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    ekle = "INSERT INTO hukuk.imha_tutanagi (kiraci_id, no, dosyalar, yontem) VALUES (%s, %s, %s, 'silme') RETURNING id"
    with pytest.raises(psycopg.errors.CheckViolation):  # gizli dosya açık
        a.c.execute(ekle, (veri["k1"], "IT-1", [veri["d"]["gizli"]]))
    t = a.c.execute(ekle, (veri["k1"], "IT-2", [veri["d"]["acik"], veri["d"]["duvarli"]])).fetchone()[0]
    with pytest.raises(psycopg.errors.CheckViolation, match="hazırlayan"):
        a.c.execute("SELECT hukuk.imha_tutanagi_onayla(%s)", (t,))
    e = uygulama.oturum(veri["k1"], veri["elif"])
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        e.c.execute("SELECT hukuk.imha_tutanagi_onayla(%s)", (t,))
    # Onaydan önce dosyaya dava nedeniyle saklama engeli konursa onay reddedilir.
    a = uygulama.oturum(veri["k1"], veri["ayse"])
    a.c.execute("UPDATE hukuk.dosya SET saklama_engeli = 'Rücu davası devam ediyor' WHERE id = %s", (veri["d"]["duvarli"],))
    m = uygulama.oturum(veri["k1"], veri["mert"])
    with pytest.raises(psycopg.errors.CheckViolation, match="engeli"):
        m.c.execute("SELECT hukuk.imha_tutanagi_onayla(%s)", (t,))
    t2 = uygulama.oturum(veri["k1"], veri["ayse"]).c.execute(ekle, (veri["k1"], "IT-3", [veri["d"]["acik"]])).fetchone()[0]
    m = uygulama.oturum(veri["k1"], veri["mert"])
    m.c.execute("SELECT hukuk.imha_tutanagi_onayla(%s)", (t2,))
    assert yonetici.execute("SELECT imha_tutanagi FROM hukuk.dosya WHERE id = %s", (veri["d"]["acik"],)).fetchone()[0] == "IT-3"
    assert m.deger("SELECT hukuk.son_periyodik_imha() = current_date") is True
    with pytest.raises(psycopg.errors.CheckViolation):  # zaten imha edilmiş dosya
        uygulama.oturum(veri["k1"], veri["ayse"]).c.execute(ekle, (veri["k1"], "IT-4", [veri["d"]["acik"]]))
