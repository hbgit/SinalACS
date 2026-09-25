# Documentação do SinalACS

- [Telas do app paciente](telas-paciente.md)
- [Telas do app ACS](telas-acs.md)
- [Telas do backoffice admin](telas-admin.md)
- [Roteiro de vídeo para o sponsor](roteiro-video-sponsor.md)
- [Briefing dos slides de showcase](showcase/BRIEFING.md)
- [AVD Android para validação](android-avd.md)

As capturas de tela usam dados sintéticos e representam o estado atual de protótipo das interfaces Flutter.

**Duas CAs de desenvolvimento, de propósito.** A stack gera uma CA própria para o
Mosquitto (broker MQTT em 8883) e outra para o RPC (HTTPS em 443, terminado pelo
Traefik, RNF04); `scripts/dev/sync_dev_ca.sh` copia as duas para os assets dos
apps. Elas não foram unificadas porque a do broker já é consumida por caminhos
que hoje funcionam — o próprio broker, os assets dos apps e a conexão de saída do
backend (`MQTT_CA_CERT_PATH`) —, e reaproveitá-la obrigaria a mexer no `init.sh` e
nos `runtime/` do Mosquitto. Consolidar as duas numa só é uma limpeza possível,
sem prazo. Ver
[plano de TLS](superpowers/plans/2026-09-18-tls-rpc-rnf04-l08.md).
