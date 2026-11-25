# Uygulama sunucusu: derlenmiş tek dosya, root olmayan kullanıcı.
FROM dart:stable AS derleme
WORKDIR /kaynak
COPY packages/hukuk_cekirdek packages/hukuk_cekirdek
COPY backend/sunucu backend/sunucu
WORKDIR /kaynak/backend/sunucu
RUN dart pub get && dart compile exe bin/sunucu.dart -o /sunucu

FROM debian:stable-slim
RUN useradd --uid 10002 hukuk
COPY --from=derleme /runtime/ /
COPY --from=derleme /sunucu /usr/local/bin/sunucu
USER hukuk
EXPOSE 8080
CMD ["/usr/local/bin/sunucu"]
