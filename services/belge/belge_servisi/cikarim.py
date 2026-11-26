"""Belgeden metin çıkarma. Taranmış PDF ve görüntülerde Türkçe OCR (Tesseract) kullanılır."""

from __future__ import annotations

import hashlib
import io
import re
import shutil
import subprocess
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

import defusedxml.ElementTree as ET
from defusedxml import DefusedXmlException

from .guvenlik import BelgeHatasi, tur_belirle

AZAMI_OCR_SAYFA = 50
# Sayfa başına bundan az karakter çıkıyorsa PDF taranmış kabul edilir.
TARANMIS_ESIGI = 30


@dataclass
class Cikarim:
    tur: str
    metin: str
    sayfa_sayisi: int
    sha256: str
    ocr: bool = False
    uyarilar: list[str] = field(default_factory=list)

    def sozluk(self) -> dict:
        return {
            "tur": self.tur,
            "metin": self.metin,
            "sayfaSayisi": self.sayfa_sayisi,
            "karakter": len(self.metin),
            "sha256": self.sha256,
            "ocr": self.ocr,
            "uyarilar": self.uyarilar,
        }


def ocr_var() -> bool:
    if shutil.which("tesseract") is None:
        return False
    try:
        cikti = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True, timeout=10)
        return "tur" in cikti.stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return False


def _ocr_goruntu(veri: bytes) -> str:
    import pytesseract
    from PIL import Image

    try:
        with Image.open(io.BytesIO(veri)) as img:
            img.load()
            return pytesseract.image_to_string(img, lang="tur", timeout=120)
    except (Image.DecompressionBombError, Image.DecompressionBombWarning) as e:
        raise BelgeHatasi("Görüntü çok büyük.") from e
    except RuntimeError as e:  # pytesseract zaman aşımı
        raise BelgeHatasi("Görüntü işlenemedi (zaman aşımı).") from e


def _goruntu_boyut_kontrol(veri: bytes) -> None:
    """Piksel sayısı, görüntü açılmadan (yalnızca başlıktan) denetlenir: küçük dosya, büyük bellek bombası olamaz."""
    from PIL import Image

    try:
        with Image.open(io.BytesIO(veri)) as img:
            g, y = img.size
    except (Image.DecompressionBombError, Image.DecompressionBombWarning) as e:
        raise BelgeHatasi("Görüntü çok büyük.") from e
    except OSError as e:
        raise BelgeHatasi("Görüntü okunamadı.") from e
    if g * y > 40_000_000:
        raise BelgeHatasi("Görüntü çok büyük (en fazla 40 megapiksel).")


def _bosluk_duzelt(metin: str) -> str:
    metin = metin.replace("\r\n", "\n").replace("\r", "\n")
    metin = re.sub(r"[ \t]+\n", "\n", metin)
    metin = re.sub(r"\n{3,}", "\n\n", metin)
    return metin.strip()


def _pdf(veri: bytes) -> Cikarim:
    from pypdf import PdfReader
    from pypdf.errors import PdfReadError

    try:
        okuyucu = PdfReader(io.BytesIO(veri))
        if okuyucu.is_encrypted and not okuyucu.decrypt(""):
            raise BelgeHatasi("Şifreli PDF açılamadı; şifresiz hâlini yükleyin.")
        sayfalar = [s.extract_text() or "" for s in okuyucu.pages]
    except PdfReadError as e:
        raise BelgeHatasi("PDF okunamadı.") from e
    metin = "\n\n".join(sayfalar)
    sonuc = Cikarim("pdf", _bosluk_duzelt(metin), len(sayfalar), "")
    if len(sonuc.metin) < TARANMIS_ESIGI * max(1, len(sayfalar)):
        if not ocr_var():
            sonuc.uyarilar.append("PDF taranmış görünüyor ancak OCR motoru kurulu değil.")
        elif len(sayfalar) > AZAMI_OCR_SAYFA:
            sonuc.uyarilar.append(f"Taranmış PDF {AZAMI_OCR_SAYFA} sayfadan uzun; OCR yapılmadı.")
        elif shutil.which("pdftoppm") is None:
            sonuc.uyarilar.append("PDF taranmış görünüyor ancak sayfa görüntüleme aracı (pdftoppm) yok.")
        else:
            sonuc.metin = _bosluk_duzelt(_pdf_ocr(veri))
            sonuc.ocr = True
            sonuc.uyarilar.append("Metin OCR ile çıkarıldı; hatalı karakterler olabilir, kontrol edin.")
    return sonuc


def _pdf_ocr(veri: bytes) -> str:
    with tempfile.TemporaryDirectory() as d:
        kaynak = Path(d) / "belge.pdf"
        kaynak.write_bytes(veri)
        subprocess.run(
            ["pdftoppm", "-r", "300", "-png", "-l", str(AZAMI_OCR_SAYFA), str(kaynak), str(Path(d) / "s")],
            check=True,
            capture_output=True,
            timeout=600,
        )
        parcalar = [_ocr_goruntu(p.read_bytes()) for p in sorted(Path(d).glob("s-*.png"))]
    return "\n\n".join(parcalar)


def _docx(veri: bytes) -> Cikarim:
    import docx

    belge = docx.Document(io.BytesIO(veri))
    satirlar = [p.text for p in belge.paragraphs]
    for tablo in belge.tables:
        for satir in tablo.rows:
            satirlar.append(" | ".join(h.text.strip() for h in satir.cells))
    return Cikarim("docx", _bosluk_duzelt("\n".join(satirlar)), 0, "")


def _udf(veri: bytes) -> Cikarim:
    """UYAP Doküman Editörü (.udf): içindeki content.xml'den metin. Biçim ayrıntıları gerçek dosyalarla doğrulanmalı."""
    with zipfile.ZipFile(io.BytesIO(veri)) as z:
        xml = z.read("content.xml")
    uyarilar: list[str] = []
    try:
        kok = ET.fromstring(xml)
        icerik = kok.find(".//content")
        metin = icerik.text if icerik is not None and icerik.text else "".join(kok.itertext())
    except DefusedXmlException as e:
        raise BelgeHatasi("UDF içeriği güvenli değil (XML varlık tanımı).") from e
    except ET.ParseError:
        metin = re.sub(r"<[^>]+>", " ", xml.decode("utf-8", errors="replace"))
        uyarilar.append("UDF içeriği tam çözümlenemedi; metin yaklaşık çıkarıldı.")
    return Cikarim("udf", _bosluk_duzelt(metin), 0, "", uyarilar=uyarilar)


def metin_cikar(veri: bytes, dosya_adi: str = "") -> Cikarim:
    tur = tur_belirle(veri, dosya_adi)
    if tur == "pdf":
        sonuc = _pdf(veri)
    elif tur == "docx":
        sonuc = _docx(veri)
    elif tur == "udf":
        sonuc = _udf(veri)
    elif tur == "xlsx":
        raise BelgeHatasi("Excel dosyaları metin çıkarma için değil, veri aktarımı için kullanılır.")
    elif tur == "txt":
        sonuc = Cikarim("txt", _bosluk_duzelt(veri.decode("utf-8")), 0, "")
    else:
        _goruntu_boyut_kontrol(veri)
        if not ocr_var():
            raise BelgeHatasi("Görüntüden metin çıkarmak için OCR motoru kurulu değil.")
        sonuc = Cikarim(tur, _bosluk_duzelt(_ocr_goruntu(veri)), 1, "", ocr=True,
                        uyarilar=["Metin OCR ile çıkarıldı; hatalı karakterler olabilir, kontrol edin."])
    sonuc.sha256 = hashlib.sha256(veri).hexdigest()
    if not sonuc.metin:
        sonuc.uyarilar.append("Belgeden metin çıkarılamadı.")
    return sonuc
