-- Belge metni (PDF/Word/UDF'den çıkarılan ya da taranmış belgede OCR ile okunan) ve Türkçe tam metin arama.
-- Metin, belgenin kendisiyle aynı yetkiyle görünür (belge → dosya görünürlüğü, gizli dosya ve etik duvar dahil).
-- Çıkarma işini sunucudaki görev yapar; uygulama rolü metni doğrudan yazamaz, yalnızca fonksiyonla kaydeder.
BEGIN;

CREATE TABLE hukuk.belge_metni (
  belge_id   uuid PRIMARY KEY REFERENCES hukuk.belge(id),
  kiraci_id  uuid NOT NULL REFERENCES hukuk.kiraci(id),
  surum_no   integer NOT NULL,
  durum      text NOT NULL CHECK (durum IN ('tamam', 'hata')),
  metin      text NOT NULL DEFAULT '',
  ocr        boolean NOT NULL DEFAULT false,
  hata       text,
  deneme     integer NOT NULL DEFAULT 1,
  zaman      timestamptz NOT NULL DEFAULT now(),
  arama      tsvector GENERATED ALWAYS AS (to_tsvector('turkish', metin)) STORED
);
CREATE INDEX belge_metni_arama ON hukuk.belge_metni USING gin (arama);
ALTER TABLE hukuk.belge_metni ENABLE ROW LEVEL SECURITY;
CREATE POLICY belge_uzerinden ON hukuk.belge_metni FOR SELECT
  USING (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (SELECT 1 FROM hukuk.belge b WHERE b.id = belge_id));
GRANT SELECT ON hukuk.belge_metni TO hukuk_uygulama;

-- Metni çıkarılmamış (ya da yeni sürümü gelmiş) belgelerin son sürümleri; hatalılar 3 denemeye kadar, saatte bir.
CREATE FUNCTION hukuk.metin_bekleyenler(p_adet integer)
RETURNS TABLE (kiraci_id uuid, belge_id uuid, surum_no integer, dosya_adi text, depo_anahtari text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT s.kiraci_id, s.belge_id, s.no, s.dosya_adi, s.depo_anahtari
  FROM hukuk.belge_surum s
  LEFT JOIN hukuk.belge_metni m ON m.belge_id = s.belge_id
  WHERE s.no = (SELECT max(x.no) FROM hukuk.belge_surum x WHERE x.belge_id = s.belge_id)
    AND (m.belge_id IS NULL OR m.surum_no < s.no
         OR (m.durum = 'hata' AND m.deneme < 3 AND m.zaman < now() - interval '1 hour'))
  ORDER BY s.zaman
  LIMIT p_adet
$$;

CREATE FUNCTION hukuk.belge_metni_kaydet(p_belge uuid, p_surum integer, p_metin text, p_ocr boolean, p_hata text)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  INSERT INTO hukuk.belge_metni (belge_id, kiraci_id, surum_no, durum, metin, ocr, hata)
  SELECT b.id, b.kiraci_id, p_surum, CASE WHEN p_hata IS NULL THEN 'tamam' ELSE 'hata' END,
         left(coalesce(p_metin, ''), 2000000), coalesce(p_ocr, false), left(p_hata, 500)
  FROM hukuk.belge b WHERE b.id = p_belge
  ON CONFLICT (belge_id) DO UPDATE SET
    surum_no = EXCLUDED.surum_no, durum = EXCLUDED.durum, metin = EXCLUDED.metin, ocr = EXCLUDED.ocr, hata = EXCLUDED.hata,
    deneme = CASE WHEN EXCLUDED.durum = 'hata' AND hukuk.belge_metni.surum_no = EXCLUDED.surum_no
                  THEN hukuk.belge_metni.deneme + 1 ELSE 1 END,
    zaman = now()
$$;

REVOKE ALL ON FUNCTION hukuk.metin_bekleyenler(integer), hukuk.belge_metni_kaydet(uuid, integer, text, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.metin_bekleyenler(integer), hukuk.belge_metni_kaydet(uuid, integer, text, boolean, text)
  TO hukuk_uygulama;

COMMIT;
