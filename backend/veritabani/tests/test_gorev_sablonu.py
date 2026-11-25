"""Görev şablonu yalnızca yöneticilerce yazılır; dosyada mahkeme + esas no tekildir."""
import json

import psycopg
import pytest

ADIM = json.dumps([{"baslik": "Dilekçe taslağı", "gunSonra": 3, "rol": "sorumlu", "oncelik": "normal"}])


def test_sablon_yetkisi(uygulama, veri):
    ayse = uygulama.oturum(veri["k1"], veri["ayse"])
    sid = ayse.deger("INSERT INTO hukuk.gorev_sablonu (kiraci_id, ad, adimlar) VALUES (%s, 'Kira tahliye', %s) RETURNING id",
                     veri["k1"], ADIM)
    mert = uygulama.oturum(veri["k1"], veri["mert"])
    assert mert.deger("SELECT ad FROM hukuk.gorev_sablonu WHERE id = %s", sid) == "Kira tahliye"
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        mert.c.execute("INSERT INTO hukuk.gorev_sablonu (kiraci_id, ad, adimlar) VALUES (%s, 'Başka', %s)", (veri["k1"], ADIM))
    assert mert.c.execute("UPDATE hukuk.gorev_sablonu SET aktif = false WHERE id = %s", (sid,)).rowcount == 0
    with pytest.raises(psycopg.errors.CheckViolation):
        uygulama.oturum(veri["k1"], veri["ayse"]).c.execute(
            "INSERT INTO hukuk.gorev_sablonu (kiraci_id, ad, adimlar) VALUES (%s, 'Boş şablon', '[]')", (veri["k1"],))


def test_mahkeme_esas_tekil(uygulama, veri):
    u = uygulama.oturum(veri["k1"], veri["ayse"])
    u.c.execute("UPDATE hukuk.dosya SET mahkeme = 'İstanbul 5. Asliye Ticaret', esas_no = '2026/123 E.' WHERE id = %s",
                (veri["d"]["acik"],))
    with pytest.raises(psycopg.errors.UniqueViolation):
        u.c.execute("UPDATE hukuk.dosya SET mahkeme = 'istanbul 5. asliye ticaret', esas_no = '2026/123 E.' WHERE id = %s",
                    (veri["d"]["duvarli"],))
    with pytest.raises(psycopg.errors.CheckViolation):
        u.c.execute("UPDATE hukuk.dosya SET esas_no = '123/2026' WHERE id = %s", (veri["d"]["duvarli"],))


def test_esas_var_gizli_dosyayi_da_bilir_ama_baska_kiraciyi_degil(uygulama, veri, yonetici):
    yonetici.execute("UPDATE hukuk.dosya SET mahkeme = 'Ankara 2. İş Mahkemesi', esas_no = '2026/9 E.' WHERE id = %s",
                     (veri["d"]["gizli"],))
    elif_ = uygulama.oturum(veri["k1"], veri["elif"])
    assert elif_.deger("SELECT count(*) FROM hukuk.dosya WHERE id = %s", veri["d"]["gizli"]) == 0  # göremez
    assert elif_.deger("SELECT hukuk.dosya_esas_var(%s, 'ankara 2. iş mahkemesi', '2026/9 E.')", veri["k1"]) is True
    assert elif_.deger("SELECT hukuk.dosya_esas_var(%s, 'Ankara 2. İş Mahkemesi', '2026/9 E.')", veri["k2"]) is False
