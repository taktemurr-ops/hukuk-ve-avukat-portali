-- Haftalık özet e-postası (pazartesi sabahı): kişinin süre, görev ve duruşma SAYILARI; yöneticilere kurum geneli.
-- Müvekkil adı, dosya başlığı ya da numarası yoktur. Kullanıcı kapatabilir; her hafta bir kez gider.
BEGIN;

ALTER TABLE hukuk.kullanici ADD COLUMN haftalik_ozet boolean NOT NULL DEFAULT true;
GRANT SELECT (haftalik_ozet) ON hukuk.kullanici TO hukuk_uygulama;

CREATE TABLE hukuk.haftalik_ozet_gonderimi (
  kullanici_id uuid NOT NULL REFERENCES hukuk.kullanici(id),
  hafta        date NOT NULL,
  zaman        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (kullanici_id, hafta)
);
ALTER TABLE hukuk.haftalik_ozet_gonderimi ENABLE ROW LEVEL SECURITY;  -- politika yok

CREATE FUNCTION hukuk.haftalik_ozet_tercihi(p_acik boolean) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
  UPDATE hukuk.kullanici SET haftalik_ozet = p_acik WHERE id = hukuk.aktif_kullanici()
$$;

-- Görev: p_hafta (pazartesi) için henüz gönderilmemiş özetleri kuyruğa yazar; yazılan e-posta sayısını döner.
CREATE FUNCTION hukuk.haftalik_ozetleri_yaz(p_hafta date, p_portal text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = hukuk, pg_temp AS $$
DECLARE
  u record;
  v_sayi integer := 0;
  v_acik integer; v_yakin integer; v_gecmis integer; v_teyit integer; v_gorev integer; v_geciken integer; v_durusma integer;
  v_buro_teyit integer; v_buro_gecmis integer;
  v_metin text;
  v_yonetici boolean;
BEGIN
  FOR u IN SELECT k.id, k.kiraci_id, k.eposta FROM hukuk.kullanici k
           WHERE k.aktif AND k.haftalik_ozet AND k.kisi_id IS NULL AND k.eposta_dogrulandi IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM hukuk.haftalik_ozet_gonderimi g WHERE g.kullanici_id = k.id AND g.hafta = p_hafta)
  LOOP
    SELECT count(*) FILTER (WHERE true),
           count(*) FILTER (WHERE son_gun BETWEEN p_hafta AND p_hafta + 6),
           count(*) FILTER (WHERE son_gun < p_hafta),
           count(*) FILTER (WHERE durum = 'teyitBekliyor')
      INTO v_acik, v_yakin, v_gecmis, v_teyit
      FROM hukuk.sure_kaydi WHERE kiraci_id = u.kiraci_id AND durum IN ('teyitBekliyor', 'teyitli')
        AND (asil_sorumlu = u.id OR yedek_sorumlu = u.id);
    SELECT count(*), count(*) FILTER (WHERE son_tarih < p_hafta) INTO v_gorev, v_geciken
      FROM hukuk.gorev WHERE kiraci_id = u.kiraci_id AND atanan = u.id AND durum = 'acik';
    SELECT count(*) INTO v_durusma FROM hukuk.durusma
      WHERE kiraci_id = u.kiraci_id AND katilan = u.id
        AND baslangic >= p_hafta::timestamp AT TIME ZONE 'Europe/Istanbul'
        AND baslangic < (p_hafta + 7)::timestamp AT TIME ZONE 'Europe/Istanbul';
    v_yonetici := EXISTS (SELECT 1 FROM hukuk.kullanici_rol r WHERE r.kullanici_id = u.id
                          AND r.rol IN ('buroSahibi', 'yoneticiOrtak', 'hukukDirektoru'));
    INSERT INTO hukuk.haftalik_ozet_gonderimi (kullanici_id, hafta) VALUES (u.id, p_hafta);
    IF v_acik + v_gorev + v_durusma = 0 AND NOT v_yonetici THEN
      CONTINUE;  -- boş özet gönderilmez
    END IF;
    v_metin := 'Bu haftanın özeti (' || to_char(p_hafta, 'DD.MM.YYYY') || ' haftası):' || E'\n\n'
      || '• Bu hafta son günü dolan süre: ' || v_yakin || E'\n'
      || '• Son günü geçmiş ve kapatılmamış süre: ' || v_gecmis || E'\n'
      || '• Teyit bekleyen süre: ' || v_teyit || E'\n'
      || '• Toplam açık süre: ' || v_acik || E'\n'
      || '• Açık görev: ' || v_gorev || ' (geciken ' || v_geciken || ')' || E'\n'
      || '• Bu haftaki duruşma: ' || v_durusma || E'\n';
    IF v_yonetici THEN
      SELECT count(*) FILTER (WHERE durum = 'teyitBekliyor'), count(*) FILTER (WHERE son_gun < p_hafta)
        INTO v_buro_teyit, v_buro_gecmis
        FROM hukuk.sure_kaydi WHERE kiraci_id = u.kiraci_id AND durum IN ('teyitBekliyor', 'teyitli');
      v_metin := v_metin || E'\nKurum geneli: teyit bekleyen ' || v_buro_teyit || ', son günü geçmiş ' || v_buro_gecmis || E' süre.\n';
    END IF;
    v_metin := v_metin || E'\nAyrıntılar için portala giriş yapın' || CASE WHEN coalesce(p_portal, '') = '' THEN '' ELSE ': ' || p_portal END
      || E'.\nGüvenliğiniz için bu e-postada müvekkil ya da dosya bilgisi yer almaz. Bu e-postayı Ayarlar → Haftalık özet bölümünden kapatabilirsiniz.';
    PERFORM hukuk.eposta_ekle(u.kiraci_id, u.eposta, 'Haftalık özet · ' || to_char(p_hafta, 'DD.MM.YYYY'), v_metin, 'haftalikOzet');
    v_sayi := v_sayi + 1;
  END LOOP;
  RETURN v_sayi;
END $$;

REVOKE ALL ON FUNCTION hukuk.haftalik_ozet_tercihi(boolean), hukuk.haftalik_ozetleri_yaz(date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hukuk.haftalik_ozet_tercihi(boolean), hukuk.haftalik_ozetleri_yaz(date, text) TO hukuk_uygulama;

COMMIT;
