import datetime as dt
import io

import openpyxl
from fastapi.testclient import TestClient

from belge_servisi.app import app

istemci = TestClient(app)


def _xlsx(satirlar, ikinci_sayfa=False):
    k = openpyxl.Workbook()
    s = k.active
    s.title = "Müvekkiller"
    for r in satirlar:
        s.append(r)
    if ikinci_sayfa:
        k.create_sheet("Notlar").append(["x"])
    b = io.BytesIO()
    k.save(b)
    return b.getvalue()


def test_xlsx_satirlar_ve_bicim():
    veri = _xlsx([
        ["Adı Soyadı", "TCKN/VKN", "E-posta", "Doğum", None],
        ["Zeynep Aydın", 10000000146.0, "z@ornek.com", dt.datetime(1990, 5, 1), None],
        [None, None, None, None],
        ["Yeni Şirket A.Ş.", "1234567890", None, None, True],
    ], ikinci_sayfa=True)
    r = istemci.post("/tablo", files={"dosya": ("liste.xlsx", veri, "application/octet-stream")})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["sayfa"] == "Müvekkiller"
    assert j["satirlar"] == [
        ["Adı Soyadı", "TCKN/VKN", "E-posta", "Doğum"],
        ["Zeynep Aydın", "10000000146", "z@ornek.com", "01.05.1990"],
        ["Yeni Şirket A.Ş.", "1234567890", "", "", "Evet"],
    ]
    assert "yalnızca ilk sayfa" in j["uyarilar"][0]


def test_xlsx_olmayan_ve_bozuk():
    r = istemci.post("/tablo", files={"dosya": ("a.txt", b"Ad;TCKN\nA;1", "text/plain")})
    assert r.status_code == 422 and ".xlsx" in r.json()["detail"]
    r = istemci.post("/tablo", files={"dosya": ("a.xls", b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" + b"0" * 100, "x")})
    assert r.status_code == 422 and ".xls" in r.json()["detail"]


def test_rapor_xlsx_sayilar_ve_formul_kacisi():
    r = istemci.post("/rapor", json={"baslik": "Alacak yaşlandırma", "sayfalar": [
        {"ad": "Alacak", "basliklar": ["Müvekkil", "0–30 gün", "Toplam"],
         "satirlar": [["ABC Gıda", "24.000,00 TL", "24.000,00 TL"], ["=HYPERLINK(\"x\")", "-", "1.250,5"]]}]})
    assert r.status_code == 200, r.text
    k = openpyxl.load_workbook(io.BytesIO(r.content))
    s = k["Alacak"]
    assert s["A1"].value == "Müvekkil" and s["A1"].font.bold
    assert s["B2"].value == 24000.0  # sayı olarak
    assert s["A3"].value == "'=HYPERLINK(\"x\")"  # formül çalışmaz
    assert s["C3"].value == 1250.5


def test_rapor_pdf():
    r = istemci.post("/rapor", json={"baslik": "İş yükü", "bicim": "pdf", "sayfalar": [
        {"basliklar": ["Kişi", "Dosya"], "satirlar": [["Av. Ayşe Yılmaz", "2"]]}]})
    assert r.status_code == 200 and r.content.startswith(b"%PDF-")
    from pypdf import PdfReader
    assert "Ayşe Yılmaz" in PdfReader(io.BytesIO(r.content)).pages[0].extract_text()
