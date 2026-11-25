"""Excel (.xlsx) dosyasının ilk sayfasını satırlara çevirir (veri aktarımı önizlemesi için).

Formüller değil hesaplanmış değerler okunur; makro ve dış bağlantılar çalıştırılmaz (openpyxl yalnızca okur).
Tarihler GG.AA.YYYY, tam sayıya eşit ondalıklar tam sayı olarak verilir (TCKN/VKN'nin "1234567890.0" olmaması için).
"""

from __future__ import annotations

import datetime as dt
import io
import warnings

from .guvenlik import BelgeHatasi, tur_belirle

AZAMI_SATIR = 5000
AZAMI_SUTUN = 50


def _hucre(v: object) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "Evet" if v else "Hayır"
    if isinstance(v, dt.datetime):
        return v.strftime("%d.%m.%Y") if v.time() == dt.time(0) else v.strftime("%d.%m.%Y %H:%M")
    if isinstance(v, dt.date):
        return v.strftime("%d.%m.%Y")
    if isinstance(v, float) and v.is_integer() and abs(v) < 1e15:
        return str(int(v))
    return str(v).strip()


def tablo_oku(veri: bytes, dosya_adi: str = "") -> dict:
    if veri.startswith(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"):
        raise BelgeHatasi("Eski Excel (.xls) biçimi desteklenmiyor; dosyayı Excel'de .xlsx olarak kaydedip yükleyin.")
    tur = tur_belirle(veri, dosya_adi)
    if tur != "xlsx":
        raise BelgeHatasi("Excel (.xlsx) dosyası bekleniyordu. Eski .xls dosyalarını Excel'de .xlsx olarak kaydedin.")
    import openpyxl  # yalnızca gerektiğinde yüklenir

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            kitap = openpyxl.load_workbook(io.BytesIO(veri), read_only=True, data_only=True)
    except Exception as e:  # bozuk ya da şifreli dosya
        raise BelgeHatasi("Excel dosyası okunamadı (bozuk ya da şifreli olabilir).") from e
    try:
        sayfa = kitap.worksheets[0]
        satirlar: list[list[str]] = []
        kirpildi = False
        for satir in sayfa.iter_rows(values_only=True):
            hucreler = [_hucre(v) for v in satir[:AZAMI_SUTUN]]
            while hucreler and hucreler[-1] == "":
                hucreler.pop()
            if not any(hucreler):
                continue
            if len(satirlar) >= AZAMI_SATIR + 1:  # başlık + 5000 satır
                kirpildi = True
                break
            satirlar.append(hucreler)
        uyarilar = []
        if len(kitap.worksheets) > 1:
            uyarilar.append(f"Dosyada {len(kitap.worksheets)} sayfa var; yalnızca ilk sayfa ({sayfa.title}) okundu.")
        if kirpildi:
            uyarilar.append(f"İlk {AZAMI_SATIR} satır okundu; kalanlar için dosyayı bölün.")
        return {"sayfa": sayfa.title, "satirlar": satirlar, "uyarilar": uyarilar}
    finally:
        kitap.close()
