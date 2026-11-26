"""Saldırı testleri: XML varlık bombası, XXE, görüntü bombası, aşırı büyük rapor."""
import io
import zipfile

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from belge_servisi.app import app

from belge_servisi.cikarim import metin_cikar
from belge_servisi.guvenlik import BelgeHatasi


def _udf(xml: bytes) -> bytes:
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("content.xml", xml)
    return b.getvalue()


def test_xml_varlik_bombasi_reddedilir():
    bomba = (b'<?xml version="1.0"?><!DOCTYPE l [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">'
             b'<!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]><template><content>&c;</content></template>')
    with pytest.raises(BelgeHatasi):
        metin_cikar(_udf(bomba), "x.udf")


def test_xxe_dosya_okuyamaz():
    xxe = (b'<?xml version="1.0"?><!DOCTYPE t [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
           b'<template><content>&x;</content></template>')
    with pytest.raises(BelgeHatasi):
        metin_cikar(_udf(xxe), "x.udf")


def test_goruntu_bombasi_reddedilir():
    # 9000x9000 = 81 milyon piksel; sıkıştırılmış PNG küçük ama açılınca büyük.
    b = io.BytesIO()
    Image.new("1", (9000, 9000)).save(b, "PNG")
    with pytest.raises(BelgeHatasi):
        metin_cikar(b.getvalue(), "x.png")


def test_cok_satirli_rapor_reddedilir():
    yanit = TestClient(app).post("/rapor", json={"baslik": "r", "sayfalar": [
        {"basliklar": ["a"], "satirlar": [["x"]] * 100_001}]})
    assert yanit.status_code == 422
