-- Etik duvarı yalnızca tüm dosyalara yetkili yöneticiler kurar ve kaldırır; dosya ekibindeki kişiye duvar kurulamaz.
-- Duvar kaydını (gerekçe dahil) yöneticiler ve dosyayı görebilenler görür; engellenen kişi (yönetici olsa da) görmez.

-- Görünürlük fonksiyonu duvar ve ekip tablolarını kendi yetkisiyle okur (aksi hâlde duvarın okuma politikası
-- dosyaya, dosyanın politikası duvara bakarak sonsuz döngüye girer). Kural aynıdır; yalnızca oturumdaki kullanıcı için.
CREATE OR REPLACE FUNCTION hukuk.dosya_gorunur(p_dosya uuid, p_gizli boolean, p_sorumlu uuid, p_yedek uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT NOT EXISTS (
           SELECT 1 FROM hukuk.etik_duvar e
           WHERE e.dosya_id = p_dosya AND e.kullanici_id = hukuk.aktif_kullanici() AND e.kaldirma IS NULL)
     AND (NOT p_gizli
          OR hukuk.aktif_kullanici() IN (p_sorumlu, p_yedek)
          OR EXISTS (SELECT 1 FROM hukuk.dosya_ekip x WHERE x.dosya_id = p_dosya AND x.kullanici_id = hukuk.aktif_kullanici())
          OR hukuk.tum_yetkili())
$$;

DROP POLICY kiraci_ayrimi ON hukuk.etik_duvar;
CREATE POLICY etik_duvar_okuma ON hukuk.etik_duvar FOR SELECT
  USING (kiraci_id = hukuk.aktif_kiraci() AND kullanici_id <> hukuk.aktif_kullanici()
         AND (hukuk.tum_yetkili() OR EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id)));
CREATE POLICY etik_duvar_kurma ON hukuk.etik_duvar FOR INSERT
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili() AND kuran = hukuk.aktif_kullanici());
CREATE POLICY etik_duvar_kaldirma ON hukuk.etik_duvar FOR UPDATE
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.tum_yetkili())
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND kaldiran = hukuk.aktif_kullanici());

CREATE FUNCTION hukuk.etik_duvar_ekip_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = NEW.dosya_id AND NEW.kullanici_id IN (d.sorumlu, d.yedek_sorumlu))
     OR EXISTS (SELECT 1 FROM hukuk.dosya_ekip e WHERE e.dosya_id = NEW.dosya_id AND e.kullanici_id = NEW.kullanici_id) THEN
    RAISE EXCEPTION 'Kullanıcı dosya ekibinde; önce ekipten çıkarılmalı' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER etik_duvar_ekip_kontrol BEFORE INSERT ON hukuk.etik_duvar
FOR EACH ROW EXECUTE FUNCTION hukuk.etik_duvar_ekip_kontrol();

-- Etik duvarı olan kişi dosya ekibine eklenemez.
CREATE FUNCTION hukuk.dosya_ekip_duvar_kontrol() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM hukuk.etik_duvar e WHERE e.dosya_id = NEW.dosya_id AND e.kullanici_id = NEW.kullanici_id
             AND e.kaldirma IS NULL) THEN
    RAISE EXCEPTION 'Etik duvarı olan kullanıcı dosya ekibine eklenemez' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER dosya_ekip_duvar_kontrol BEFORE INSERT ON hukuk.dosya_ekip
FOR EACH ROW EXECUTE FUNCTION hukuk.dosya_ekip_duvar_kontrol();
GRANT EXECUTE ON FUNCTION hukuk.etik_duvar_ekip_kontrol(), hukuk.dosya_ekip_duvar_kontrol() TO hukuk_uygulama;
