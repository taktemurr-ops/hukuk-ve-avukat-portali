-- Uyum: anonim ihbar formu, soruşturma notları ve geri bildirim, kişisel veri ihlali (KVKK 72 saat).

ALTER TABLE hukuk.ihbar
  ADD COLUMN sirket_id uuid REFERENCES hukuk.sirket(id),
  ADD CONSTRAINT ihbar_takip_kodu_tekil UNIQUE (takip_kodu_ozet);

ALTER TABLE hukuk.sorusturma
  ADD COLUMN ilk_geri_bildirim timestamptz,
  ADD CONSTRAINT sorusturma_sonuc_tutarli CHECK (
    (durum = 'kapandi') = (sonuc IS NOT NULL)
    AND (durum NOT IN ('kapandi', 'reddedildi') OR coalesce(length(trim(sonuc_ozeti)), 0) >= 10)
  ),
  ADD CONSTRAINT sorusturma_sonuc_degeri CHECK (sonuc IS NULL OR sonuc IN ('dogrulandi', 'kismen', 'dogrulanamadi', 'asilsiz'));

-- Kapanmış veya reddedilmiş soruşturma yeniden açılamaz ve değiştirilemez.
CREATE FUNCTION hukuk.sorusturma_kapanis_kilidi() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.durum IN ('kapandi', 'reddedildi') THEN
    RAISE EXCEPTION 'Sonuçlanmış soruşturma değiştirilemez' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER sorusturma_kapanis_kilidi BEFORE UPDATE ON hukuk.sorusturma
FOR EACH ROW EXECUTE FUNCTION hukuk.sorusturma_kapanis_kilidi();

-- Soruşturma notları: yalnızca eklenir; yalnızca soruşturmayı görenler okur ve yazar.
CREATE TABLE hukuk.sorusturma_notu (
  id            bigserial PRIMARY KEY,
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  sorusturma_id uuid NOT NULL REFERENCES hukuk.sorusturma(id),
  kullanici_id  uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  metin         text NOT NULL CHECK (length(trim(metin)) > 0),
  zaman         timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hukuk.sorusturma_notu ENABLE ROW LEVEL SECURITY;
CREATE POLICY sorusturma_uzerinden ON hukuk.sorusturma_notu
  USING (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (SELECT 1 FROM hukuk.sorusturma s WHERE s.id = sorusturma_id))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND kullanici_id = hukuk.aktif_kullanici()
              AND EXISTS (SELECT 1 FROM hukuk.sorusturma s WHERE s.id = sorusturma_id));
GRANT SELECT, INSERT ON hukuk.sorusturma_notu TO hukuk_uygulama;
GRANT USAGE ON SEQUENCE hukuk.sorusturma_notu_id_seq TO hukuk_uygulama;

-- Kişisel veri ihlali: öğrenilmeden itibaren 72 saat içinde Kurul'a bildirim (KVKK Kurul kararı 2019/10).
CREATE TABLE hukuk.veri_ihlali (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id          uuid NOT NULL REFERENCES hukuk.kiraci(id),
  ogrenilme          timestamptz NOT NULL,
  aciklama           text NOT NULL CHECK (length(trim(aciklama)) >= 10),
  etkilenen_sayi     integer CHECK (etkilenen_sayi >= 0),
  kurula_bildirim    timestamptz,
  ilgililere_bildirim timestamptz,
  kaydeden           uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  zaman              timestamptz NOT NULL DEFAULT now(),
  CHECK (ogrenilme <= zaman + interval '5 minutes'),
  CHECK (kurula_bildirim IS NULL OR kurula_bildirim >= ogrenilme),
  CHECK (ilgililere_bildirim IS NULL OR ilgililere_bildirim >= ogrenilme)
);
ALTER TABLE hukuk.veri_ihlali ENABLE ROW LEVEL SECURITY;
-- İhlal kaydını hukuk direktörü, uyum sorumlusu ve BT yöneticisi görür.
CREATE POLICY ihlal_ekibi ON hukuk.veri_ihlali
  USING (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (
    SELECT 1 FROM hukuk.kullanici_rol r WHERE r.kullanici_id = hukuk.aktif_kullanici()
      AND r.rol IN ('hukukDirektoru', 'uyumSorumlusu', 'btYoneticisi')))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci());
-- Bildirim zamanları bir kez yazılır; öğrenilme zamanı ve açıklama sonradan değiştirilemez.
CREATE FUNCTION hukuk.veri_ihlali_kilidi() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ogrenilme <> OLD.ogrenilme OR NEW.aciklama <> OLD.aciklama
     OR (OLD.kurula_bildirim IS NOT NULL AND NEW.kurula_bildirim IS DISTINCT FROM OLD.kurula_bildirim)
     OR (OLD.ilgililere_bildirim IS NOT NULL AND NEW.ilgililere_bildirim IS DISTINCT FROM OLD.ilgililere_bildirim) THEN
    RAISE EXCEPTION 'İhlal kaydının öğrenilme zamanı, açıklaması ve yapılmış bildirimleri değiştirilemez'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER veri_ihlali_kilidi BEFORE UPDATE ON hukuk.veri_ihlali
FOR EACH ROW EXECUTE FUNCTION hukuk.veri_ihlali_kilidi();
GRANT SELECT, INSERT, UPDATE ON hukuk.veri_ihlali TO hukuk_uygulama;

-- Herkese açık ihbar formu (oturum gerektirmez). Takip kodunun yalnızca özeti saklanır.
-- Kötüye kullanıma karşı kurum başına saatte en fazla 30 ihbar kabul edilir.
CREATE FUNCTION hukuk.ihbar_formu(p_kiraci uuid, p_kategori text, p_aciklama text, p_iletisim text, p_kod_ozeti text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hukuk.kiraci WHERE id = p_kiraci AND hesap_turu = 'kurumsal') THEN
    RAISE EXCEPTION 'İhbar formu bulunamadı' USING ERRCODE = 'no_data_found';
  END IF;
  IF (SELECT count(*) FROM hukuk.ihbar WHERE kiraci_id = p_kiraci AND zaman > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION 'Çok sayıda ihbar alındı; lütfen daha sonra tekrar deneyin' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO hukuk.ihbar (kiraci_id, takip_kodu_ozet, kanal, kategori, aciklama, anonim, iletisim)
  VALUES (p_kiraci, p_kod_ozeti, 'web', p_kategori, p_aciklama, p_iletisim IS NULL, p_iletisim);
END $$;

-- İhbarcının takip koduyla göreceği durum: yalnızca aşama ve ilk geri bildirim verildi mi (içerik yok).
CREATE FUNCTION hukuk.ihbar_durumu(p_kod_ozeti text)
RETURNS TABLE (durum text, geri_bildirim boolean, alinma timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT coalesce(s.durum, 'alindi'), s.ilk_geri_bildirim IS NOT NULL, i.zaman
  FROM hukuk.ihbar i LEFT JOIN hukuk.sorusturma s ON s.ihbar_id = i.id
  WHERE i.takip_kodu_ozet = p_kod_ozeti
$$;
GRANT EXECUTE ON FUNCTION hukuk.ihbar_formu(uuid, text, text, text, text), hukuk.ihbar_durumu(text),
  hukuk.sorusturma_kapanis_kilidi(), hukuk.veri_ihlali_kilidi() TO hukuk_uygulama;
