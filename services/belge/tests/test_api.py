from fastapi.testclient import TestClient

from belge_servisi.app import app

istemci = TestClient(app)


def test_saglik():
    r = istemci.get("/saglik")
    assert r.status_code == 200
    assert r.json()["durum"] == "ok"


def test_metin_pdf(pdf_metinli):
    r = istemci.post("/metin", files={"dosya": ("s.pdf", pdf_metinli, "application/pdf")})
    assert r.status_code == 200
    j = r.json()
    assert j["tur"] == "pdf" and j["sayfaSayisi"] == 2 and j["karakter"] > 50


def test_metin_desteklenmeyen():
    r = istemci.post("/metin", files={"dosya": ("x.bin", b"\x00\x01", "application/octet-stream")})
    assert r.status_code == 422
    assert "Desteklenmeyen" in r.json()["detail"]


def test_docx_ve_eksik_reddi():
    r = istemci.post("/docx", json={"baslik": "İhtarname", "metin": "# İHTARNAME\n\nMuhatap: [EKSİK: karsiTaraf.ad]"})
    assert r.status_code == 200
    assert r.headers["x-eksik-alan-sayisi"] == "1"
    assert r.content.startswith(b"PK")
    assert "%C4%B0htarname.docx" in r.headers["content-disposition"]
    r2 = istemci.post("/docx", json={"baslik": "x", "metin": "[EKSİK: a]", "eksikVarsaReddet": True})
    assert r2.status_code == 422
    assert r2.json()["detail"]["alanlar"] == ["a"]
