"""Saldırı testi: bir kurum, başka kurumun kayıt kimliğini bilse bile kendi kaydını ona bağlayamaz.

Yabancı anahtar denetimi satır güvenliğini aşar; ayni_kiraci tetikleyicisi olmadan portal paylaşımıyla başka
kurumun dosyası kendi müvekkiline gösterilebiliyordu.
"""
import uuid

import psycopg
import pytest


def test_baska_kurumun_dosyasina_baglanamaz(uygulama, veri, yonetici):
    k1, yabanci = veri["k1"], veri["d"]["baska"]  # k2'nin dosyası
    ayse = uygulama.oturum(k1, veri["ayse"])  # k1 yöneticisi
    kisi = ayse.deger("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'gercek', 'Saldırgan Müvekkil') RETURNING id", k1)
    denemeler = [
        ("INSERT INTO hukuk.dosya_taraf VALUES (%s, %s, %s, 'muvekkil')", (k1, yabanci, kisi)),
        ("INSERT INTO hukuk.portal_paylasim (dosya_id, kiraci_id, paylasan) VALUES (%s, %s, %s)", (yabanci, k1, veri["ayse"])),
        ("INSERT INTO hukuk.dosya_ekip (kiraci_id, dosya_id, kullanici_id) VALUES (%s, %s, %s)", (k1, yabanci, veri["mert"])),
        ("INSERT INTO hukuk.gorev (kiraci_id, dosya_id, baslik, atanan) VALUES (%s, %s, 'x', %s)", (k1, yabanci, veri["mert"])),
    ]
    for sql, p in denemeler:
        with pytest.raises(psycopg.errors.ForeignKeyViolation):
            uygulama.oturum(k1, veri["ayse"]).c.execute(sql, p)
    # Başka kurumun kişisi de kullanılamaz.
    yabanci_kisi = yonetici.execute("INSERT INTO hukuk.kisi (kiraci_id, tur, ad) VALUES (%s, 'gercek', 'B Müvekkili') RETURNING id",
                                    (veri["k2"],)).fetchone()[0]
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        uygulama.oturum(k1, veri["ayse"]).c.execute("INSERT INTO hukuk.dosya_taraf VALUES (%s, %s, %s, 'karsiTaraf')",
                                                     (k1, veri["d"]["acik"], yabanci_kisi))
    # Aynı kurum içinde bağlantı çalışmaya devam eder.
    uygulama.oturum(k1, veri["ayse"]).c.execute("INSERT INTO hukuk.dosya_taraf VALUES (%s, %s, %s, 'muvekkil')",
                                                 (k1, veri["d"]["acik"], kisi))


def test_fonksiyonlar_public_kapali(yonetici):
    acik = yonetici.execute("SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'hukuk'::regnamespace "
                            "AND has_function_privilege('public', p.oid, 'EXECUTE')").fetchone()[0]
    assert acik == 0
    tanimsiz = yonetici.execute("SELECT array_agg(p.proname) FROM pg_proc p WHERE p.pronamespace = 'hukuk'::regnamespace "
                                "AND p.prosecdef AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) x "
                                "WHERE x LIKE 'search_path=%')").fetchone()[0]
    assert tanimsiz is None
    rlssiz = yonetici.execute("SELECT array_agg(c.relname) FROM pg_class c WHERE c.relnamespace = 'hukuk'::regnamespace "
                              "AND c.relkind = 'r' AND NOT c.relrowsecurity").fetchone()[0]
    assert rlssiz is None
