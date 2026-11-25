"""Belge metni: belgeyle aynı yetkiyle görünür, Türkçe arama çalışır, hatalı çıkarma sınırlı denenir."""
import uuid

import psycopg
import pytest


def _belge(yonetici, k, dosya, ad, kullanici):
    b = uuid.uuid4()
    yonetici.execute("INSERT INTO hukuk.belge (id, kiraci_id, dosya_id, ad, tur) VALUES (%s, %s, %s, %s, 'diger')",
                     (b, k, dosya, ad))
    yonetici.execute("INSERT INTO hukuk.belge_surum (belge_id, kiraci_id, no, sha256, boyut, dosya_adi, yukleyen, depo_anahtari) "
                     "VALUES (%s, %s, 1, %s, 10, %s, %s, %s)", (b, k, "a" * 64, ad + ".pdf", kullanici, f"{k}/{b}/1"))
    return b


def test_metin_arama_ve_yetki(uygulama, veri, yonetici):
    acik = _belge(yonetici, veri["k1"], veri["d"]["acik"], "Bilirkişi raporu", veri["mert"])
    gizli = _belge(yonetici, veri["k1"], veri["d"]["gizli"], "Gizli rapor", veri["ayse"])
    bekleyen = [r[1] for r in uygulama.c.execute("SELECT * FROM hukuk.metin_bekleyenler(100)").fetchall()]
    assert acik in bekleyen and gizli in bekleyen
    uygulama.c.execute("SELECT hukuk.belge_metni_kaydet(%s, 1, %s, false, NULL)",
                       (acik, "Davacının kıdem tazminatı alacakları hesaplanmıştır."))
    uygulama.c.execute("SELECT hukuk.belge_metni_kaydet(%s, 1, %s, true, NULL)", (gizli, "Tazminat ve soruşturma notları"))
    assert acik not in [r[1] for r in uygulama.c.execute("SELECT * FROM hukuk.metin_bekleyenler(100)").fetchall()]

    elif_ = uygulama.oturum(veri["k1"], veri["elif"])  # gizli dosyayı görmez
    bulunan = elif_.liste("SELECT belge_id FROM hukuk.belge_metni WHERE arama @@ websearch_to_tsquery('turkish', 'tazminat')")
    assert bulunan == [acik]  # gövde eki ("tazminatı") Türkçe kökle eşleşir; gizli dosyadaki görünmez
    ayse = uygulama.oturum(veri["k1"], veri["ayse"])
    assert set(ayse.liste("SELECT belge_id FROM hukuk.belge_metni WHERE arama @@ websearch_to_tsquery('turkish', 'tazminat')")) == {acik, gizli}
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        ayse.c.execute("UPDATE hukuk.belge_metni SET metin = 'x'")


def test_hata_sinirli_denenir(uygulama, veri, yonetici):
    b = _belge(yonetici, veri["k1"], veri["d"]["acik"], "Bozuk tarama", veri["mert"])
    uygulama.c.execute("SELECT hukuk.belge_metni_kaydet(%s, 1, NULL, false, 'OCR yok')", (b,))
    assert b not in [r[1] for r in uygulama.c.execute("SELECT * FROM hukuk.metin_bekleyenler(100)").fetchall()]  # 1 saat bekler
    yonetici.execute("UPDATE hukuk.belge_metni SET zaman = now() - interval '2 hours' WHERE belge_id = %s", (b,))
    assert b in [r[1] for r in uygulama.c.execute("SELECT * FROM hukuk.metin_bekleyenler(100)").fetchall()]
    uygulama.c.execute("SELECT hukuk.belge_metni_kaydet(%s, 1, NULL, false, 'OCR yok')", (b,))
    uygulama.c.execute("SELECT hukuk.belge_metni_kaydet(%s, 1, NULL, false, 'OCR yok')", (b,))
    yonetici.execute("UPDATE hukuk.belge_metni SET zaman = now() - interval '2 hours' WHERE belge_id = %s", (b,))
    assert yonetici.execute("SELECT deneme FROM hukuk.belge_metni WHERE belge_id = %s", (b,)).fetchone()[0] == 3
    assert b not in [r[1] for r in uygulama.c.execute("SELECT * FROM hukuk.metin_bekleyenler(100)").fetchall()]
