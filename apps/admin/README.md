# SinalACS — Backoffice Admin

Backoffice administrativo (Flutter Web e Android, desktop-first com layout compacto para celular): login de desenvolvimento, painel de indicadores por risco clínico, listagem de microáreas e vínculo ACS, consulta filtrável de alertas e logs de auditoria.

## Rodar no Android

```bash
flutter run -d emulator-5554              # emulador de celular
flutter build apk --debug                 # valida a configuração Gradle
flutter test integration_test -d emulator-5554
```

Os testes de integração deste app são **herméticos** — rodam sobre `MockAdminDataSource` e não precisam do `docker compose`, do seed nem de `--dart-define`, ao contrário dos apps ACS e do paciente.

Ver o [README.md](../../README.md) na raiz do repositório para pré-requisitos, comandos de execução/teste e o estado atual do projeto. Documentação visual das telas em [docs/telas-admin.md](../../docs/telas-admin.md).
