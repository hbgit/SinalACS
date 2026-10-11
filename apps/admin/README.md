# SinalACS — Backoffice Admin

Backoffice administrativo (Flutter Web e Android, desktop-first com layout compacto para celular): login institucional real (matrícula + senha + TOTP, `auth.loginStaff`), painel de indicadores por risco clínico, listagem de microáreas **com a gestão de contas de ACS** (cadastro, vínculo de microárea, redefinição de senha e de MFA, ativação/desativação) e a seção Equipe do backoffice para o administrador, consulta filtrável de alertas e logs de auditoria (escopados à UBS para o coordenador desde a #43).

## Rodar no Android

```bash
flutter run -d emulator-5554              # emulador de celular
flutter build apk --debug                 # valida a configuração Gradle
flutter test integration_test -d emulator-5554
```

O login é real e **sem atalho de desenvolvimento**: precisa da stack no ar (`docker compose up`, que semeia `ADM-001` com a senha de `DEV_ADMIN_PASSWORD` do `.env`), de `./scripts/dev/sync_dev_ca.sh` (copia a CA do RPC para `assets/certs/`) e de um host HTTPS (`--dart-define=SINALACS_HOST=https://10.0.2.2/`, o padrão no emulador). No primeiro acesso a conta ativa a verificação em duas etapas pela própria tela. Os dados do painel vêm do backend desde a #40 (o `MockAdminDataSource` só serve aos testes de widget). Os roteiros de prova contra o banco de teste são `./scripts/qa/admin_login_e2e.sh` (login e MFA do staff) e `./scripts/qa/admin_acs_gestao_e2e.sh` (gestão de contas: cadastro, vínculo, redefinições e desativação), ambos verdes no emulador `emulator-5554` — o primeiro também em celular Android 15; ver `PROGRESS.md`.

Os testes de integração `*_test.dart` deste app são **herméticos** — rodam sobre `MockAdminDataSource` e não precisam do `docker compose`, do seed nem de `--dart-define`, ao contrário dos apps ACS e do paciente.

Ver o [README.md](../../README.md) na raiz do repositório para pré-requisitos, comandos de execução/teste e o estado atual do projeto. Documentação visual das telas em [docs/telas-admin.md](../../docs/telas-admin.md).
