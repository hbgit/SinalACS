# SinalACS — App ACS

Aplicativo Flutter do Agente Comunitário de Saúde: login institucional com matrícula, senha e TOTP (refresh token no Keystore, liberado por biometria), fila de visitas priorizada por risco e restrita à microárea, mapa e territorialização, registro de visitas offline em banco cifrado com sincronização, e alertas vermelhos por MQTT com confirmação.

Execute com `./scripts/dev/run_acs.sh` a partir da raiz (não com `flutter run` direto): o script injeta a senha do broker, que não tem valor padrão.

Ver o [README.md](../../README.md) na raiz do repositório para pré-requisitos, comandos de execução/teste e o estado atual do projeto, e [PROGRESS.md](../../PROGRESS.md) para o status detalhado dos milestones. Documentação visual das telas em [docs/telas-acs.md](../../docs/telas-acs.md).
