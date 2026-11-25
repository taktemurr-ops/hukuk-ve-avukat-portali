-- Büro işleri: dosya tarafları, görevler, duruşmalar, tebligatlar ve vekâletnameler.

CREATE TABLE hukuk.dosya_taraf (
  kiraci_id uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id  uuid NOT NULL REFERENCES hukuk.dosya(id),
  kisi_id   uuid NOT NULL REFERENCES hukuk.kisi(id),
  sifat     text NOT NULL CHECK (sifat IN ('muvekkil', 'karsiTaraf', 'diger')),
  PRIMARY KEY (dosya_id, kisi_id, sifat)
);
-- Aynı kişi aynı dosyada hem müvekkil hem karşı taraf olamaz.
CREATE UNIQUE INDEX dosya_taraf_tek_sifat ON hukuk.dosya_taraf (dosya_id, kisi_id) WHERE sifat IN ('muvekkil', 'karsiTaraf');

CREATE TABLE hukuk.gorev (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id       uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id        uuid REFERENCES hukuk.dosya(id),
  baslik          text NOT NULL CHECK (length(trim(baslik)) >= 3),
  atanan          uuid NOT NULL,
  yedek           uuid,
  son_tarih       date,
  oncelik         text NOT NULL DEFAULT 'normal' CHECK (oncelik IN ('dusuk', 'normal', 'yuksek', 'kritik')),
  durum           text NOT NULL DEFAULT 'acik' CHECK (durum IN ('acik', 'tamamlandi', 'iptal')),
  kaynak_sure_id  uuid REFERENCES hukuk.sure_kaydi(id),
  kanit_gerekir   boolean NOT NULL DEFAULT false,
  kapanis_kaniti  text,
  olusturan       uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  kapanis         timestamptz,
  FOREIGN KEY (kiraci_id, atanan) REFERENCES hukuk.kullanici (kiraci_id, id),
  CHECK (yedek IS NULL OR yedek <> atanan),
  -- Kritik süreden doğan veya kanıt isteyen görev kanıtsız kapanamaz.
  CHECK (durum <> 'tamamlandi' OR NOT (kanit_gerekir OR kaynak_sure_id IS NOT NULL)
         OR coalesce(length(trim(kapanis_kaniti)), 0) > 0),
  CHECK ((durum = 'acik') = (kapanis IS NULL))
);

CREATE TABLE hukuk.durusma (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id   uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id    uuid NOT NULL REFERENCES hukuk.dosya(id),
  baslangic   timestamptz NOT NULL,
  sure_dakika integer NOT NULL DEFAULT 60 CHECK (sure_dakika BETWEEN 5 AND 720),
  yer         text NOT NULL CHECK (length(trim(yer)) > 0),
  katilan     uuid NOT NULL,
  tur         text NOT NULL DEFAULT 'Duruşma',
  FOREIGN KEY (kiraci_id, katilan) REFERENCES hukuk.kullanici (kiraci_id, id)
);

CREATE TABLE hukuk.tebligat (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id      uuid NOT NULL REFERENCES hukuk.kiraci(id),
  kanal          text NOT NULL CHECK (kanal IN ('uets', 'kep', 'uyap', 'elektronik', 'fiziki')),
  ulasma_tarihi  date NOT NULL,
  teblig_tarihi  date NOT NULL,
  gonderen       text NOT NULL,
  konu           text NOT NULL,
  esas_no        text,
  taraflar       text[] NOT NULL DEFAULT '{}',
  belge_ozeti    char(64),
  tekillik       text NOT NULL,
  dosya_id       uuid REFERENCES hukuk.dosya(id),
  kaydeden       uuid NOT NULL DEFAULT hukuk.aktif_kullanici(),
  zaman          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kiraci_id, tekillik),
  CHECK (teblig_tarihi >= ulasma_tarihi)
);

CREATE TABLE hukuk.vekaletname (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id      uuid NOT NULL REFERENCES hukuk.kiraci(id),
  muvekkil_id    uuid NOT NULL REFERENCES hukuk.kisi(id),
  avukatlar      uuid[] NOT NULL CHECK (cardinality(avukatlar) > 0),
  duzenleme      date NOT NULL CHECK (duzenleme <= current_date),
  noter          text,
  yevmiye_no     text,
  genel          boolean NOT NULL DEFAULT true,
  ozel_yetkiler  text[] NOT NULL DEFAULT '{}',
  dosyalar       uuid[] NOT NULL DEFAULT '{}',
  bitis          date,
  durum          text NOT NULL DEFAULT 'gecerli' CHECK (durum IN ('gecerli', 'azil', 'istifa', 'sureDoldu')),
  durum_tarihi   date,
  asil_evrak_yeri text,
  CHECK (genel OR cardinality(dosyalar) > 0),
  CHECK (bitis IS NULL OR bitis >= duzenleme),
  CHECK ((durum = 'gecerli') = (durum_tarihi IS NULL))
);
-- Azledilen, istifa edilen veya süresi dolan vekâletname yeniden geçerli yapılamaz.
CREATE FUNCTION hukuk.vekaletname_kilidi() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.durum <> 'gecerli' THEN
    RAISE EXCEPTION 'Sona ermiş vekâletname değiştirilemez' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER vekaletname_kilidi BEFORE UPDATE ON hukuk.vekaletname
FOR EACH ROW EXECUTE FUNCTION hukuk.vekaletname_kilidi();

-- Satır düzeyi güvenlik: dosyaya bağlı kayıtlar dosyayı görenlere; dosyasız görev ve eşleşmemiş tebligat kurum içine.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['dosya_taraf', 'durusma'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY dosya_uzerinden ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci() AND '
                   'EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id)) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id))', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['gorev', 'tebligat'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY dosya_uzerinden ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci() AND '
                   '(dosya_id IS NULL OR EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id))) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci() AND '
                   '(dosya_id IS NULL OR EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id)))', t);
  END LOOP;
END $$;
ALTER TABLE hukuk.vekaletname ENABLE ROW LEVEL SECURITY;
CREATE POLICY kiraci_ayrimi ON hukuk.vekaletname
  USING (kiraci_id = hukuk.aktif_kiraci()) WITH CHECK (kiraci_id = hukuk.aktif_kiraci());

GRANT SELECT, INSERT ON hukuk.dosya_taraf TO hukuk_uygulama;
GRANT SELECT, INSERT, UPDATE ON hukuk.gorev, hukuk.durusma, hukuk.tebligat, hukuk.vekaletname TO hukuk_uygulama;
GRANT DELETE ON hukuk.durusma TO hukuk_uygulama;
GRANT EXECUTE ON FUNCTION hukuk.vekaletname_kilidi() TO hukuk_uygulama;

-- Dosya numarası tüm dosyalara göre verilir. Uygulama rolü gizli dosyaları göremediği için sayım
-- SECURITY DEFINER fonksiyonda, yalnızca oturumdaki kiracı için yapılır (aksi hâlde numara çakışırdı).
CREATE FUNCTION hukuk.sonraki_dosya_no(p_yil integer) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  SELECT p_yil || '/' || lpad((coalesce(max(CAST(split_part(ic_no, '/', 2) AS integer)), 0) + 1)::text, 4, '0')
  FROM hukuk.dosya WHERE kiraci_id = hukuk.aktif_kiraci() AND ic_no LIKE p_yil || '/%'
$$;
GRANT EXECUTE ON FUNCTION hukuk.sonraki_dosya_no(integer) TO hukuk_uygulama;
