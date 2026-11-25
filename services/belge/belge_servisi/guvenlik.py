"""Yükleme güvenliği: boyut, tür (sihirli baytlar) ve sıkıştırma bombası kontrolleri."""

from __future__ import annotations

import io
import zipfile

AZAMI_BOYUT = 25 * 1024 * 1024  # 25 MB
AZAMI_ACILMIS_BOYUT = 200 * 1024 * 1024
AZAMI_SIKISTIRMA_ORANI = 100
AZAMI_ZIP_GIRDISI = 2000


class BelgeHatasi(ValueError):
    """Kullanıcıya gösterilebilir hata (Türkçe)."""


def tur_belirle(veri: bytes, dosya_adi: str = "") -> str:
    """Dosya uzantısına değil içeriğe bakarak türü belirler."""
    if len(veri) == 0:
        raise BelgeHatasi("Dosya boş.")
    if len(veri) > AZAMI_BOYUT:
        raise BelgeHatasi("Dosya 25 MB sınırını aşıyor.")
    if veri.startswith(b"%PDF-"):
        return "pdf"
    if veri.startswith(b"PK\x03\x04"):
        adlar = zip_kontrol(veri)
        if "word/document.xml" in adlar:
            return "docx"
        if "content.xml" in adlar:
            return "udf"
        raise BelgeHatasi("Desteklenmeyen sıkıştırılmış dosya.")
    if veri.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if veri.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if veri[:4] in (b"II*\x00", b"MM\x00*"):
        return "tiff"
    if b"\x00" not in veri[:4096]:
        try:
            veri.decode("utf-8")
            return "txt"
        except UnicodeDecodeError:
            pass
    raise BelgeHatasi("Desteklenmeyen dosya türü. PDF, Word (.docx), UDF, görüntü veya metin yükleyin.")


def zip_kontrol(veri: bytes) -> set[str]:
    try:
        z = zipfile.ZipFile(io.BytesIO(veri))
    except zipfile.BadZipFile as e:
        raise BelgeHatasi("Bozuk dosya.") from e
    girdiler = z.infolist()
    if len(girdiler) > AZAMI_ZIP_GIRDISI:
        raise BelgeHatasi("Dosya çok fazla parça içeriyor.")
    toplam = 0
    for g in girdiler:
        if g.flag_bits & 0x1:
            raise BelgeHatasi("Şifreli dosyalar desteklenmiyor.")
        toplam += g.file_size
        if g.compress_size > 0 and g.file_size / g.compress_size > AZAMI_SIKISTIRMA_ORANI:
            raise BelgeHatasi("Dosya şüpheli derecede sıkıştırılmış.")
    if toplam > AZAMI_ACILMIS_BOYUT:
        raise BelgeHatasi("Dosyanın açılmış boyutu çok büyük.")
    return {g.filename for g in girdiler}
