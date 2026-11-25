# Uygulama sunucusu: derlenmiş tek dosya, root olmayan kullanıcı.
FROM dart:stable AS derleme
WORKDIR /kaynak
COPY packages/hukuk_cekirdek packages/hukuk_cekirdek
COPY backend/sunucu backend/sunucu
WORKDIR /kaynak/backend/sunucu
RUN dart pub get && dart compile exe bin/sunucu.dart -o /sunucu

FROM debian:stable-slim
RUN useradd --uid 10002 hukuk && mkdir -p /veri/belgeler && chown hukuk /veri/belgeler
COPY --from=derleme /runtime/ /
COPY --from=derleme /sunucu /usr/local/bin/sunucu
# Belge içerikleri: Türkiye'deki kalıcı ve şifreli diske bağlanmalıdır (S3 uyumlu depo gelene kadar).
ENV BELGE_KLASORU=/veri/belgeler
VOLUME /veri/belgeler
USER hukuk
EXPOSE 8080
CMD ["/usr/local/bin/sunucu"]
