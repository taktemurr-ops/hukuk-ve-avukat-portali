-- Çıkar çatışması taraması sunucuda ve kurumun TÜM dosyalarında yapılır: kullanıcının göremediği (gizli, etik
-- duvarlı) dosyalardaki taraflar da bulunur, ama bu dosyaların adı ve kimliği gösterilmez ("Korumalı dosya").
-- İş kabul kararı değiştirilemez; çatışma varken kabulü karar verenden farklı bir yönetici onaylar.
BEGIN;

-- Tarama için taraf kayıtları: görünmeyen ya da gizli dosya "korumali" işaretlenir (adı boş döner).
CREATE FUNCTION hukuk.cikar_tarama_taraflari()
RETURNS TABLE (dosya_id uuid, dosya_adi text, kisi_id uuid, sifat text, korumali boolean, kapali boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT t.dosya_id,
         CASE WHEN d.gizli OR NOT hukuk.dosya_gorunur(d.id, d.gizli, d.sorumlu, d.yedek_sorumlu) THEN ''
              ELSE d.ic_no || ' · ' || d.baslik END,
         t.kisi_id, t.sifat,
         d.gizli OR NOT hukuk.dosya_gorunur(d.id, d.gizli, d.sorumlu, d.yedek_sorumlu),
         d.kapanis IS NOT NULL
  FROM hukuk.dosya_taraf t JOIN hukuk.dosya d ON d.id = t.dosya_id
  WHERE t.kiraci_id = hukuk.aktif_kiraci() AND hukuk.aktif_kullanici() IS NOT NULL
$$;

CREATE TABLE hukuk.is_kabul_karari (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  adaylar       jsonb NOT NULL CHECK (jsonb_typeof(adaylar) = 'array' AND jsonb_array_length(adaylar) BETWEEN 1 AND 50),
  -- Sunucunun yaptığı taramanın özeti (dosya adları maskeli): [{"aday","kisiAdi","tur","seviye","dosyaAdi"}]
  eslesmeler    jsonb NOT NULL DEFAULT '[]',
  en_yuksek     text CHECK (en_yuksek IN ('bilgi', 'dikkat', 'catisma')),
  tur           text NOT NULL CHECK (tur IN ('kabul', 'kosulluKabul', 'ret')),
  gerekce       text NOT NULL CHECK (length(trim(gerekce)) >= 10),
  kosullar      text,
  karar_veren   uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  zaman         timestamptz NOT NULL DEFAULT now(),
  durum         text NOT NULL CHECK (durum IN ('gecerli', 'onayBekliyor')),
  onaylayan     uuid,
  onay_zamani   timestamptz,
  CHECK (tur <> 'kosulluKabul' OR length(trim(coalesce(kosullar, ''))) > 0),
  -- Çatışmada kabul yönetici onayı olmadan geçerli olamaz.
  CHECK (NOT (en_yuksek = 'catisma' AND tur <> 'ret' AND durum = 'gecerli' AND onaylayan IS NULL)),
  CHECK (onaylayan IS NULL OR onaylayan <> karar_veren),
  CHECK ((durum = 'onayBekliyor') = (en_yuksek = 'catisma' AND tur <> 'ret' AND onaylayan IS NULL))
);
ALTER TABLE hukuk.is_kabul_karari ENABLE ROW LEVEL SECURITY;
CREATE POLICY is_kabul_okuma ON hukuk.is_kabul_karari FOR SELECT USING (kiraci_id = hukuk.aktif_kiraci());
CREATE POLICY is_kabul_ekleme ON hukuk.is_kabul_karari FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND karar_veren = hukuk.aktif_kullanici() AND onaylayan IS NULL);
GRANT SELECT, INSERT ON hukuk.is_kabul_karari TO hukuk_uygulama;  -- güncelleme ve silme yok

CREATE FUNCTION hukuk.is_kabul_onayla(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  k hukuk.is_kabul_karari;
BEGIN
  SELECT * INTO k FROM hukuk.is_kabul_karari WHERE id = p_id AND kiraci_id = hukuk.aktif_kiraci() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Karar bulunamadı.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT hukuk.tum_yetkili() THEN
    RAISE EXCEPTION 'Çatışmalı işi yalnızca yöneticiler onaylayabilir.' USING ERRCODE = '42501';
  END IF;
  IF k.karar_veren = hukuk.aktif_kullanici() THEN
    RAISE EXCEPTION 'Kararı veren kendi kararını onaylayamaz.' USING ERRCODE = '42501';
  END IF;
  IF k.durum <> 'onayBekliyor' THEN
    RAISE EXCEPTION 'Bu karar onay beklemiyor.' USING ERRCODE = '23514';
  END IF;
  UPDATE hukuk.is_kabul_karari SET durum = 'gecerli', onaylayan = hukuk.aktif_kullanici(), onay_zamani = now()
  WHERE id = p_id;
  INSERT INTO hukuk.denetim_kaydi (kiraci_id, kullanici_id, islem, nesne_turu, nesne_id, aciklama, onceki_ozet, ozet)
  VALUES (k.kiraci_id, hukuk.aktif_kullanici(), 'kararKaydi', 'is_kabul', p_id::text, 'Çatışmalı iş kabulü onaylandı', '', '');
END $$;

REVOKE ALL ON FUNCTION hukuk.cikar_tarama_taraflari(), hukuk.is_kabul_onayla(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.cikar_tarama_taraflari(), hukuk.is_kabul_onayla(uuid) TO hukuk_uygulama;

COMMIT;
