"""Gelir paylaşım oranları: varsayılan 20/50/30; yalnız yönetici değiştirir; toplam %100 zorunlu."""
import psycopg
import pytest


def test_gelir_paylasimi(uygulama, veri):
    k = veri["k1"]
    assert uygulama.oturum(k, veri["mert"]).c.execute("SELECT * FROM hukuk.gelir_paylasim_kurali()").fetchone() == (20, 50, 30)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        uygulama.oturum(k, veri["mert"]).c.execute("SELECT hukuk.gelir_paylasim_ayarla(30, 40, 30)")
    with pytest.raises(psycopg.errors.CheckViolation):
        uygulama.oturum(k, veri["ayse"]).c.execute("SELECT hukuk.gelir_paylasim_ayarla(30, 40, 40)")
    uygulama.oturum(k, veri["ayse"]).c.execute("SELECT hukuk.gelir_paylasim_ayarla(25, 45, 30)")
    assert uygulama.oturum(k, veri["mert"]).c.execute("SELECT * FROM hukuk.gelir_paylasim_kurali()").fetchone() == (25, 45, 30)
    assert uygulama.oturum(veri["k2"], veri["baska"]).c.execute(
        "SELECT * FROM hukuk.gelir_paylasim_kurali()").fetchone() == (20, 50, 30)
    assert uygulama.oturum(k, veri["ayse"]).deger(
        "SELECT aciklama FROM hukuk.denetim_kaydi WHERE nesne_turu = 'kiraci' ORDER BY sira DESC LIMIT 1").endswith("20/50/30 -> 25/45/30")
