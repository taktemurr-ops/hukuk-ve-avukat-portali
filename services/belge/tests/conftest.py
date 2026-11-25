import io
import sys
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

FONT = Path(__file__).resolve().parents[3] / "site" / "fonts" / "Inter-400.ttf"
METIN = "İŞBU SÖZLEŞME İstanbul'da imzalanmıştır. Taraflar 60 gün önce bildirimde bulunur."


@pytest.fixture
def pdf_metinli() -> bytes:
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen import canvas

    pdfmetrics.registerFont(TTFont("Inter", str(FONT)))
    b = io.BytesIO()
    c = canvas.Canvas(b, pagesize=A4)
    c.setFont("Inter", 12)
    c.drawString(72, 750, METIN)
    c.showPage()
    c.setFont("Inter", 12)
    c.drawString(72, 750, "İkinci sayfa: Uyuşmazlıklarda Ankara Mahkemeleri yetkilidir.")
    c.save()
    return b.getvalue()


def _goruntu(metin: str):
    from PIL import Image, ImageDraw, ImageFont

    img = Image.new("RGB", (2400, 300), "white")
    d = ImageDraw.Draw(img)
    d.text((40, 100), metin, fill="black", font=ImageFont.truetype(str(FONT), 64))
    return img


@pytest.fixture
def png_metinli() -> bytes:
    b = io.BytesIO()
    _goruntu("Gerekçeli karar tebliğ edildi").save(b, format="PNG")
    return b.getvalue()


@pytest.fixture
def pdf_taranmis() -> bytes:
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.utils import ImageReader
    from reportlab.pdfgen import canvas

    img = _goruntu("Ödeme emrine itiraz dilekçesi")
    b = io.BytesIO()
    c = canvas.Canvas(b, pagesize=A4)
    c.drawImage(ImageReader(img), 30, 600, width=540, height=68)
    c.save()
    return b.getvalue()


@pytest.fixture
def docx_metinli() -> bytes:
    import docx

    d = docx.Document()
    d.add_paragraph("KİRA SÖZLEŞMESİ")
    d.add_paragraph("Aylık kira bedeli 480.000 TL'dir.")
    t = d.add_table(rows=1, cols=2)
    t.rows[0].cells[0].text = "Kiracı"
    t.rows[0].cells[1].text = "ABC Gıda A.Ş."
    b = io.BytesIO()
    d.save(b)
    return b.getvalue()


@pytest.fixture
def udf_metinli() -> bytes:
    b = io.BytesIO()
    with zipfile.ZipFile(b, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(
            "content.xml",
            '<?xml version="1.0" encoding="UTF-8"?><template><content><![CDATA[T.C.\nİSTANBUL 5. ASLİYE TİCARET MAHKEMESİ\nESAS NO: 2026/123]]></content></template>',
        )
    return b.getvalue()
