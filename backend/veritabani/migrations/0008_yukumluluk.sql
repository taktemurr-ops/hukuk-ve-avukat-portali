-- Sözleşme yükümlülükleri (teslim, ödeme, raporlama…): son tarih uyarıları için.
CREATE TABLE hukuk.sozlesme_yukumluluk (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id   uuid NOT NULL REFERENCES hukuk.kiraci(id),
  sozlesme_id uuid NOT NULL REFERENCES hukuk.sozlesme(id),
  aciklama    text NOT NULL CHECK (length(trim(aciklama)) >= 3),
  taraf       text NOT NULL CHECK (taraf IN ('biz', 'karsiTaraf')),
  son_tarih   date NOT NULL,
  sorumlu     uuid,
  tamamlanma  timestamptz,
  tamamlayan  uuid,
  CHECK ((tamamlanma IS NULL) = (tamamlayan IS NULL))
);
CREATE INDEX sozlesme_yukumluluk_sozlesme ON hukuk.sozlesme_yukumluluk (sozlesme_id);
ALTER TABLE hukuk.sozlesme_yukumluluk ENABLE ROW LEVEL SECURITY;
CREATE POLICY kiraci_ayrimi ON hukuk.sozlesme_yukumluluk
  USING (kiraci_id = hukuk.aktif_kiraci()) WITH CHECK (kiraci_id = hukuk.aktif_kiraci());
GRANT SELECT, INSERT, UPDATE ON hukuk.sozlesme_yukumluluk TO hukuk_uygulama;
