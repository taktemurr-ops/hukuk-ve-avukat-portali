import io
import zipfile

import pytest

from belge_servisi.cikarim import metin_cikar, ocr_var
from belge_servisi.docx_uret import docx_uret, eksik_alanlar
from belge_servisi.guvenlik import BelgeHatasi, tur_belirle


def test_metinli_pdf(pdf_metinli):
    c = metin_cikar(pdf_metinli)
    assert c.tur == "pdf"
    assert c.sayfa_sayisi == 2
    assert "İŞBU SÖZLEŞME" in c.metin
    assert "Ankara Mahkemeleri" in c.metin
    assert not c.ocr
    assert len(c.sha256) == 64


def test_docx_tablo_dahil(docx_metinli):
    c = metin_cikar(docx_metinli, "kira.docx")
    assert c.tur == "docx"
    assert "480.000 TL" in c.metin
    assert "Kiracı | ABC Gıda A.Ş." in c.metin


def test_udf(udf_metinli):
    c = metin_cikar(udf_metinli, "dilekce.udf")
    assert c.tur == "udf"
    assert c.metin.startswith("T.C.\nİSTANBUL 5. ASLİYE TİCARET MAHKEMESİ")


def test_duz_metin():
    assert metin_cikar("Merhaba\r\n\r\n\r\n\r\nDünya  \n".encode()).metin == "Merhaba\n\nDünya"


@pytest.mark.skipif(not ocr_var(), reason="Türkçe OCR yok")
def test_goruntu_ocr(png_metinli):
    c = metin_cikar(png_metinli, "karar.png")
    assert c.ocr
    assert "Gerekçeli karar" in c.metin


@pytest.mark.skipif(not ocr_var(), reason="Türkçe OCR yok")
def test_taranmis_pdf_ocr(pdf_taranmis):
    c = metin_cikar(pdf_taranmis)
    assert c.ocr
    assert "itiraz" in c.metin.lower()
    assert any("OCR" in u for u in c.uyarilar)


def test_reddedilenler():
    with pytest.raises(BelgeHatasi, match="boş"):
        tur_belirle(b"")
    with pytest.raises(BelgeHatasi, match="Desteklenmeyen dosya"):
        tur_belirle(b"\x00\x01\x02binary")
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w") as z:
        z.writestr("x.txt", "a")
    with pytest.raises(BelgeHatasi, match="sıkıştırılmış"):
        tur_belirle(b.getvalue())


def test_sikistirma_bombasi():
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("word/document.xml", "A" * 5_000_000)
    with pytest.raises(BelgeHatasi, match="şüpheli"):
        tur_belirle(b.getvalue())


def test_docx_uret_eksik_vurgulu():
    metin = "# MAZERET DİLEKÇESİ\n\nDosya: [EKSİK: dosya.esasNo]\nMahkeme: İstanbul\n\nSaygılarımla."
    veri = docx_uret("Mazeret", metin)
    assert eksik_alanlar(metin) == ["dosya.esasNo"]
    import docx
    from docx.enum.text import WD_COLOR_INDEX

    d = docx.Document(io.BytesIO(veri))
    assert d.paragraphs[0].text == "MAZERET DİLEKÇESİ"
    assert d.paragraphs[0].runs[0].bold
    vurgulu = [r.text for p in d.paragraphs for r in p.runs if r.font.highlight_color == WD_COLOR_INDEX.YELLOW]
    assert vurgulu == ["[EKSİK: dosya.esasNo]"]
    assert d.paragraphs[-1].text == "Saygılarımla."
