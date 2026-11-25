-- Hukuk ve Avukat Portalı: temel veritabanı şeması (PostgreSQL 16).
--
-- İlkeler
--  * Çok müşterili (kiracılı) yapı: her satır kiraci_id taşır; satır düzeyi güvenlik (RLS) başka müşterinin
--    verisini veritabanı seviyesinde görünmez kılar. Uygulama her işlemde app.kiraci_id ve app.kullanici_id ayarlar.
--  * Gizli dosya ve etik duvar kuralları uygulamadaki tek kapı yetki denetçisiyle aynıdır ve burada ikinci kez
--    uygulanır (derinlemesine savunma). Dosyası görünmeyen süre/belge de görünmez.
--  * Denetim kaydı yalnızca eklenebilir; her kayıt öncekinin özetini içerir (SHA-256 zinciri).
--  * Belge sürümleri değiştirilemez ve silinemez.
--  * Veri yalnızca Türkiye'de: kiraci.veri_bolgesi yalnızca 'TR' olabilir.

BEGIN;

CREATE SCHEMA IF NOT EXISTS hukuk;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hukuk_uygulama') THEN
    CREATE ROLE hukuk_uygulama NOLOGIN;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Oturum bağlamı
-- ---------------------------------------------------------------------------

CREATE FUNCTION hukuk.aktif_kiraci() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.kiraci_id', true), '')::uuid $$;

CREATE FUNCTION hukuk.aktif_kullanici() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.kullanici_id', true), '')::uuid $$;

-- ---------------------------------------------------------------------------
-- Kiracı, kullanıcı, rol
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.kiraci (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ad           text NOT NULL CHECK (length(trim(ad)) > 0),
  hesap_turu   text NOT NULL CHECK (hesap_turu IN ('avukatlikBurosu', 'hukukBurosu', 'kurumsal')),
  veri_bolgesi text NOT NULL DEFAULT 'TR' CHECK (veri_bolgesi = 'TR'),
  olusturma    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE hukuk.kullanici (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id   uuid NOT NULL REFERENCES hukuk.kiraci(id),
  eposta      text NOT NULL CHECK (eposta ~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'),
  ad_soyad    text NOT NULL,
  -- Argon2id özeti; düz şifre asla saklanmaz.
  sifre_ozeti text NOT NULL CHECK (sifre_ozeti LIKE '$argon2id$%'),
  aktif       boolean NOT NULL DEFAULT true,
  iki_adimli  boolean NOT NULL DEFAULT false,
  olusturma   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kiraci_id, id)
);
CREATE UNIQUE INDEX kullanici_eposta_tekil ON hukuk.kullanici (kiraci_id, lower(eposta));

CREATE TABLE hukuk.kullanici_rol (
  kiraci_id    uuid NOT NULL,
  kullanici_id uuid NOT NULL,
  rol          text NOT NULL,
  PRIMARY KEY (kullanici_id, rol),
  FOREIGN KEY (kiraci_id, kullanici_id) REFERENCES hukuk.kullanici (kiraci_id, id)
);

CREATE FUNCTION hukuk.tum_yetkili() RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM hukuk.kullanici_rol r
    WHERE r.kullanici_id = hukuk.aktif_kullanici()
      AND r.rol IN ('buroSahibi', 'yoneticiOrtak', 'hukukDirektoru'))
$$;

-- ---------------------------------------------------------------------------
-- Taraflar ve dosyalar
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.kisi (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id  uuid NOT NULL REFERENCES hukuk.kiraci(id),
  tur        text NOT NULL CHECK (tur IN ('gercek', 'tuzel')),
  ad         text NOT NULL,
  kimlik_no  text CHECK (kimlik_no ~ '^[0-9]{10,11}$'),
  eposta     text
);
CREATE UNIQUE INDEX kisi_kimlik_tekil ON hukuk.kisi (kiraci_id, kimlik_no) WHERE kimlik_no IS NOT NULL;

CREATE TABLE hukuk.dosya (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  ic_no         text NOT NULL,
  tur           text NOT NULL,
  baslik        text NOT NULL,
  sorumlu       uuid NOT NULL,
  yedek_sorumlu uuid,
  gizli         boolean NOT NULL DEFAULT false,
  asama         text NOT NULL DEFAULT 'onDegerlendirme',
  acilis        date NOT NULL DEFAULT current_date,
  kapanis       date,
  UNIQUE (kiraci_id, ic_no),
  CHECK (yedek_sorumlu IS NULL OR yedek_sorumlu <> sorumlu),
  CHECK (kapanis IS NULL OR kapanis >= acilis),
  FOREIGN KEY (kiraci_id, sorumlu) REFERENCES hukuk.kullanici (kiraci_id, id),
  FOREIGN KEY (kiraci_id, yedek_sorumlu) REFERENCES hukuk.kullanici (kiraci_id, id)
);

CREATE TABLE hukuk.dosya_ekip (
  kiraci_id    uuid NOT NULL,
  dosya_id     uuid NOT NULL REFERENCES hukuk.dosya(id) ON DELETE CASCADE,
  kullanici_id uuid NOT NULL,
  PRIMARY KEY (dosya_id, kullanici_id),
  FOREIGN KEY (kiraci_id, kullanici_id) REFERENCES hukuk.kullanici (kiraci_id, id)
);

CREATE TABLE hukuk.etik_duvar (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id          uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id           uuid NOT NULL REFERENCES hukuk.dosya(id),
  kullanici_id       uuid NOT NULL,
  gerekce            text NOT NULL CHECK (length(trim(gerekce)) >= 10),
  kuran              uuid NOT NULL,
  kurma              timestamptz NOT NULL DEFAULT now(),
  kaldiran           uuid,
  kaldirma_gerekcesi text,
  kaldirma           timestamptz,
  CHECK (kullanici_id <> kuran),
  CHECK ((kaldiran IS NULL) = (kaldirma IS NULL)),
  CHECK (kaldiran IS NULL OR (kaldiran <> kullanici_id AND coalesce(length(trim(kaldirma_gerekcesi)), 0) >= 10))
);
CREATE UNIQUE INDEX etik_duvar_etkin ON hukuk.etik_duvar (dosya_id, kullanici_id) WHERE kaldirma IS NULL;

-- Tek kapı yetki denetçisiyle aynı kural: etik duvar her şeyi yener; gizli dosyayı yalnızca ekip ve tüm yetkili roller görür.
CREATE FUNCTION hukuk.dosya_gorunur(p_dosya uuid, p_gizli boolean, p_sorumlu uuid, p_yedek uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (
           SELECT 1 FROM hukuk.etik_duvar e
           WHERE e.dosya_id = p_dosya AND e.kullanici_id = hukuk.aktif_kullanici() AND e.kaldirma IS NULL)
     AND (NOT p_gizli
          OR hukuk.aktif_kullanici() IN (p_sorumlu, p_yedek)
          OR EXISTS (SELECT 1 FROM hukuk.dosya_ekip x WHERE x.dosya_id = p_dosya AND x.kullanici_id = hukuk.aktif_kullanici())
          OR hukuk.tum_yetkili())
$$;

-- ---------------------------------------------------------------------------
-- Süreler ve belgeler
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.sure_kaydi (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id     uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id      uuid NOT NULL REFERENCES hukuk.dosya(id),
  aciklama      text NOT NULL,
  kural_kodu    text NOT NULL,
  son_gun       date NOT NULL,
  durum         text NOT NULL DEFAULT 'teyitBekliyor'
                CHECK (durum IN ('teyitBekliyor', 'teyitli', 'tamamlandi', 'iptal')),
  olusturan     uuid NOT NULL,
  asil_sorumlu  uuid NOT NULL,
  yedek_sorumlu uuid,
  teyit_eden    uuid,
  teyit_zamani  timestamptz,
  kanit         text,
  CHECK (yedek_sorumlu IS NULL OR yedek_sorumlu <> asil_sorumlu),
  -- Dört göz: hesabı yapan kendi süresini teyit edemez.
  CHECK (teyit_eden IS NULL OR teyit_eden <> olusturan),
  CHECK (durum <> 'teyitli' OR teyit_eden IS NOT NULL),
  CHECK (durum <> 'tamamlandi' OR coalesce(length(trim(kanit)), 0) > 0)
);

CREATE TABLE hukuk.belge (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kiraci_id uuid NOT NULL REFERENCES hukuk.kiraci(id),
  dosya_id  uuid REFERENCES hukuk.dosya(id),
  ad        text NOT NULL,
  tur       text NOT NULL,
  gizli     boolean NOT NULL DEFAULT false
);

CREATE TABLE hukuk.belge_surum (
  belge_id   uuid NOT NULL REFERENCES hukuk.belge(id),
  kiraci_id  uuid NOT NULL REFERENCES hukuk.kiraci(id),
  no         integer NOT NULL CHECK (no >= 1),
  sha256     char(64) NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  boyut      bigint NOT NULL CHECK (boyut >= 0),
  dosya_adi  text NOT NULL,
  yukleyen   uuid NOT NULL,
  zaman      timestamptz NOT NULL DEFAULT now(),
  -- Nesne deposundaki konum (Türkiye'deki depo).
  depo_anahtari text NOT NULL,
  PRIMARY KEY (belge_id, no),
  UNIQUE (belge_id, sha256)
);

-- ---------------------------------------------------------------------------
-- Denetim kaydı (yalnızca ekleme, SHA-256 zinciri)
-- ---------------------------------------------------------------------------

CREATE TABLE hukuk.denetim_kaydi (
  kiraci_id    uuid NOT NULL REFERENCES hukuk.kiraci(id),
  sira         bigint NOT NULL,
  zaman        timestamptz NOT NULL DEFAULT now(),
  kullanici_id uuid,
  islem        text NOT NULL,
  nesne_turu   text NOT NULL,
  nesne_id     text NOT NULL,
  aciklama     text NOT NULL DEFAULT '',
  onceki_ozet  char(64) NOT NULL,
  ozet         char(64) NOT NULL,
  PRIMARY KEY (kiraci_id, sira)
);

CREATE FUNCTION hukuk.denetim_ozeti(d hukuk.denetim_kaydi) RETURNS char(64)
LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(sha256(convert_to(concat_ws('|',
    d.onceki_ozet, d.sira::text, to_char(d.zaman AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    d.kiraci_id::text, coalesce(d.kullanici_id::text, ''), d.islem, d.nesne_turu, d.nesne_id, d.aciklama), 'UTF8')), 'hex')
$$;

CREATE FUNCTION hukuk.denetim_zincirle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  onceki hukuk.denetim_kaydi;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.kiraci_id::text, 0));
  SELECT * INTO onceki FROM hukuk.denetim_kaydi WHERE kiraci_id = NEW.kiraci_id ORDER BY sira DESC LIMIT 1;
  NEW.sira := coalesce(onceki.sira, 0) + 1;
  NEW.onceki_ozet := coalesce(onceki.ozet, repeat('0', 64));
  NEW.zaman := date_trunc('microseconds', clock_timestamp());
  NEW.kullanici_id := coalesce(NEW.kullanici_id, hukuk.aktif_kullanici());
  NEW.ozet := hukuk.denetim_ozeti(NEW);
  RETURN NEW;
END $$;

CREATE TRIGGER denetim_zincirle BEFORE INSERT ON hukuk.denetim_kaydi
FOR EACH ROW EXECUTE FUNCTION hukuk.denetim_zincirle();

-- Zincir sağlamsa NULL, değilse bozulan ilk sıra numarası.
CREATE FUNCTION hukuk.denetim_dogrula(p_kiraci uuid) RETURNS bigint
LANGUAGE plpgsql STABLE AS $$
DECLARE
  d hukuk.denetim_kaydi;
  beklenen char(64) := repeat('0', 64);
  sayac bigint := 0;
BEGIN
  FOR d IN SELECT * FROM hukuk.denetim_kaydi WHERE kiraci_id = p_kiraci ORDER BY sira LOOP
    sayac := sayac + 1;
    IF d.sira <> sayac OR d.onceki_ozet <> beklenen OR d.ozet <> hukuk.denetim_ozeti(d) THEN
      RETURN d.sira;
    END IF;
    beklenen := d.ozet;
  END LOOP;
  RETURN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- Satır düzeyi güvenlik
-- ---------------------------------------------------------------------------

ALTER TABLE hukuk.kiraci ENABLE ROW LEVEL SECURITY;
CREATE POLICY kiraci_kendi ON hukuk.kiraci USING (id = hukuk.aktif_kiraci());

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['kullanici', 'kullanici_rol', 'kisi', 'dosya_ekip', 'etik_duvar', 'denetim_kaydi'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY kiraci_ayrimi ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci()) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci())', t);
  END LOOP;
END $$;

ALTER TABLE hukuk.dosya ENABLE ROW LEVEL SECURITY;
CREATE POLICY dosya_gorunurluk ON hukuk.dosya
  USING (kiraci_id = hukuk.aktif_kiraci() AND hukuk.dosya_gorunur(id, gizli, sorumlu, yedek_sorumlu))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci());

-- Dosyaya bağlı kayıtlar, dosya görünüyorsa görünür (alt sorgu dosya politikasından geçer).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['sure_kaydi', 'belge'] LOOP
    EXECUTE format('ALTER TABLE hukuk.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY dosya_uzerinden ON hukuk.%I USING (kiraci_id = hukuk.aktif_kiraci() AND '
                   '(dosya_id IS NULL OR EXISTS (SELECT 1 FROM hukuk.dosya d WHERE d.id = dosya_id))) '
                   'WITH CHECK (kiraci_id = hukuk.aktif_kiraci())', t);
  END LOOP;
END $$;

ALTER TABLE hukuk.belge_surum ENABLE ROW LEVEL SECURITY;
CREATE POLICY belge_uzerinden ON hukuk.belge_surum
  USING (kiraci_id = hukuk.aktif_kiraci() AND EXISTS (SELECT 1 FROM hukuk.belge b WHERE b.id = belge_id))
  WITH CHECK (kiraci_id = hukuk.aktif_kiraci());

-- ---------------------------------------------------------------------------
-- Uygulama rolünün yetkileri
-- ---------------------------------------------------------------------------

GRANT USAGE ON SCHEMA hukuk TO hukuk_uygulama;
GRANT SELECT, INSERT, UPDATE ON hukuk.kiraci, hukuk.kullanici, hukuk.kisi, hukuk.dosya, hukuk.sure_kaydi, hukuk.belge
  TO hukuk_uygulama;
GRANT SELECT, INSERT, DELETE ON hukuk.kullanici_rol, hukuk.dosya_ekip TO hukuk_uygulama;
-- Etik duvar silinmez, yalnızca kaldırma bilgisi işlenir.
GRANT SELECT, INSERT ON hukuk.etik_duvar TO hukuk_uygulama;
GRANT UPDATE (kaldiran, kaldirma_gerekcesi, kaldirma) ON hukuk.etik_duvar TO hukuk_uygulama;
-- Değiştirilemez kayıtlar: yalnızca okuma ve ekleme.
GRANT SELECT, INSERT ON hukuk.belge_surum, hukuk.denetim_kaydi TO hukuk_uygulama;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA hukuk TO hukuk_uygulama;

COMMIT;
