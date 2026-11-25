-- Süre hatırlatma ve eskalasyon e-postaları. Kurallar çekirdekteki EskalasyonMotoru'ndadır (sunucu görevi
-- çalıştırır); veritabanı aynı uyarının aynı gün iki kez gitmemesini ve alıcı adreslerinin uygulamaya hiç
-- çıkmamasını sağlar. E-posta metni müvekkil adı içermez (yalnızca dosya iç numarası ve tarih).
BEGIN;

ALTER TABLE hukuk.sure_kaydi ADD COLUMN olusturma timestamptz NOT NULL DEFAULT now();

CREATE TABLE hukuk.sure_bildirimi (
  kiraci_id    uuid NOT NULL REFERENCES hukuk.kiraci(id),
  sure_id      uuid NOT NULL REFERENCES hukuk.sure_kaydi(id),
  gun          date NOT NULL,
  seviye       text NOT NULL CHECK (seviye IN ('hatirlatma', 'yedekSorumlu', 'yonetici', 'kritik')),
  alici_sayisi integer NOT NULL DEFAULT 0,
  zaman        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (sure_id, gun, seviye)
);
ALTER TABLE hukuk.sure_bildirimi ENABLE ROW LEVEL SECURITY;
CREATE POLICY sure_bildirimi_okuma ON hukuk.sure_bildirimi FOR SELECT
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili());
GRANT SELECT ON hukuk.sure_bildirimi TO hukuk_uygulama;

-- Görev için tüm kiracıların açık süreleri (kiracı bağlamı olmadan çalışır; yalnızca kural için gereken alanlar).
CREATE FUNCTION hukuk.sure_bildirim_adaylari()
RETURNS TABLE (kiraci_id uuid, sure_id uuid, dosya_id uuid, ic_no text, kural_kodu text, son_gun date, durum text,
               olusturma date, olusturan uuid, asil_sorumlu uuid, yedek_sorumlu uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT s.kiraci_id, s.id, s.dosya_id, d.ic_no, s.kural_kodu, s.son_gun, s.durum,
         (s.olusturma AT TIME ZONE 'Europe/Istanbul')::date, s.olusturan, s.asil_sorumlu, s.yedek_sorumlu
  FROM hukuk.sure_kaydi s JOIN hukuk.dosya d ON d.id = s.dosya_id
  WHERE s.durum IN ('teyitBekliyor', 'teyitli') AND d.imha_tarihi IS NULL
  ORDER BY s.son_gun
$$;

-- Bir uyarıyı kaydeder ve alıcılara kuyruğa yazar; aynı süre, gün ve seviye için ikinci çağrı hiçbir şey yapmaz.
-- Alıcılar: verilen kullanıcılar ve istenirse kiracının yöneticileri; yalnızca aktif hesaplar. Dönen: e-posta sayısı.
CREATE FUNCTION hukuk.sure_bildirimi_gonder(p_kiraci uuid, p_sure uuid, p_gun date, p_seviye text,
                                           p_kullanicilar uuid[], p_yoneticiler boolean, p_konu text, p_metin text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  v_eposta text;
  v_sayi integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hukuk.sure_kaydi WHERE id = p_sure AND kiraci_id = p_kiraci) THEN
    RAISE EXCEPTION 'Süre bu kiracıya ait değil.' USING ERRCODE = '42501';
  END IF;
  INSERT INTO hukuk.sure_bildirimi (kiraci_id, sure_id, gun, seviye) VALUES (p_kiraci, p_sure, p_gun, p_seviye)
  ON CONFLICT DO NOTHING;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  FOR v_eposta IN
    SELECT DISTINCT lower(u.eposta) FROM hukuk.kullanici u
    WHERE u.kiraci_id = p_kiraci AND u.aktif AND u.kisi_id IS NULL
      AND (u.id = ANY(coalesce(p_kullanicilar, '{}'))
           OR (p_yoneticiler AND EXISTS (SELECT 1 FROM hukuk.kullanici_rol r WHERE r.kullanici_id = u.id
                 AND r.kiraci_id = p_kiraci AND r.rol IN ('buroSahibi', 'yoneticiOrtak', 'hukukDirektoru'))))
  LOOP
    PERFORM hukuk.eposta_ekle(p_kiraci, v_eposta, p_konu, p_metin, 'sure');
    v_sayi := v_sayi + 1;
  END LOOP;
  UPDATE hukuk.sure_bildirimi SET alici_sayisi = v_sayi WHERE sure_id = p_sure AND gun = p_gun AND seviye = p_seviye;
  RETURN v_sayi;
END $$;

REVOKE ALL ON FUNCTION hukuk.sure_bildirim_adaylari(), hukuk.sure_bildirimi_gonder(uuid, uuid, date, text, uuid[], boolean, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.sure_bildirim_adaylari(), hukuk.sure_bildirimi_gonder(uuid, uuid, date, text, uuid[], boolean, text, text) TO hukuk_uygulama;

COMMIT;
