# Documentação do SinalACS

- [Telas do app paciente](telas-paciente.md)
- [Telas do app ACS](telas-acs.md)
- [Telas do backoffice admin](telas-admin.md)
- [Roteiro de vídeo para o sponsor](roteiro-video-sponsor.md)
- [AVD Android para validação](android-avd.md)
- [Publicação na Google Play](publicacao-google-play.md)
- [Auditoria da CI (2026-09-28)](ci-audit/2026-09-28-avaliacao-ci-develop.md)
- [Apresentação (showcase)](showcase/slides.md)

As capturas de tela usam dados sintéticos e podem estar defasadas em relação às telas atuais; a data de cada captura é a do commit que a adicionou.

**Duas CAs de desenvolvimento, de propósito.** A stack gera uma CA própria para o
Mosquitto (broker MQTT em 8883) e outra para o RPC (HTTPS em 443, terminado pelo
Traefik, RNF04); `scripts/dev/sync_dev_ca.sh` copia as duas para os assets dos
apps. Elas não foram unificadas porque a do broker já é consumida por caminhos
que hoje funcionam — o próprio broker, os assets dos apps e a conexão de saída do
backend (`MQTT_CA_CERT_PATH`) —, e reaproveitá-la obrigaria a mexer no `init.sh` e
nos `runtime/` do Mosquitto. Consolidar as duas numa só é uma limpeza possível,
sem prazo. Ver
[plano de TLS](superpowers/plans/2026-09-18-tls-rpc-rnf04-l08.md).
