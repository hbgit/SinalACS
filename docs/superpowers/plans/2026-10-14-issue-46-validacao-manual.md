# Validação manual da #46 no emulador (cartão de termos e aviso agendado)

Este roteiro é **manual**. O passo do cartão de termos (`terms_change_notice_card`) **NÃO foi executado por automação nesta entrega**: exigiria o TOTP de um staff e dirigir dois apps (admin e paciente) no mesmo emulador.

Cobertura automatizada que existe no lugar:
- backend, com Postgres real: `backend/sinalacs_server/test/integration/admin_endpoint_terms_test.dart` (rascunho, revisão jurídica, publicação e as recusas);
- app do paciente: `apps/patient/test/terms_change_notice_test.dart` (o cartão e seus estados);
- aviso agendado até a bandeja: `./scripts/qa/push_e2e.sh --e2e-db --negativos` (log em `docs/superpowers/plans/2026-10-14-issue-46-e2e.log`).

## 1. Subir a stack

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin"
./scripts/dev/bootstrap_env.sh        # só se ainda não houver .env
docker compose up -d
./scripts/dev/sync_dev_ca.sh          # copia a CA do RPC para assets/certs/ dos apps
```

Comprova: backend, Postgres, Mosquitto e Traefik no ar, com a CA que os apps confiam.

## 2. Subir o emulador

```bash
emulator -avd Medium_Phone &
adb wait-for-device
adb devices                           # deve listar emulator-5554
```

## 3. Entrar no app admin

```bash
cd apps/admin && flutter run -d emulator-5554
```

Entre com `ADM-001` e a senha de `DEV_ADMIN_PASSWORD` (no `.env`). No primeiro acesso, ative a verificação em duas etapas pela própria tela e informe o código TOTP.

Comprova: login real do staff (sem atalho de desenvolvimento).

## 4. Termos: rascunho, revisão jurídica e publicação (só admin)

1. Abra a aba **Avisos** e a sub-aba **Termos**.
2. Crie um rascunho: versão `2099.1`, resumo `[TEXTO PLACEHOLDER]`, vigência padrão sugerida pela tela.
   - Comprova: a versão nasce como rascunho.
3. Constate o estado **Aguardando revisão jurídica** e o botão **Publicar desabilitado**.
   - Comprova: a publicação é bloqueada enquanto a revisão jurídica não foi marcada.
4. Marque a versão como revisada.
   - Comprova: a revisão é um passo explícito, registrado.
5. Publique.
   - Comprova: a publicação só ocorre com revisão e com a antecedência mínima de 15 dias (a vigência padrão já a respeita).

## 5. Cartão no app do paciente

```bash
cd apps/patient && flutter run -d emulator-5554
```

Entre por OTP (paciente de seed). Confira o cartão **"Os termos vão mudar"** (`terms_change_notice_card`) com a versão `2099.1` e a data de vigência.

Comprova: o aviso de 15 dias chega ao paciente a partir da versão publicada. **Este passo não foi executado por automação.**

## 6. Aviso agendado

No app admin, aba **Avisos**: agende um aviso para daqui a poucos minutos, escolhendo o alvo. Confira que ele aparece no **histórico** como agendado e, após o disparo (a varredura roda a cada 30 s), que passa a enviado. Com o app do paciente instalado e o consentimento concedido, o aviso aparece na bandeja.

Comprova: agendamento, histórico e disparo pelo `NoticeDispatchLoop`.

## Limpeza

A versão `2099.1` é de teste. Para descartá-la, `docker compose down && rm -rf pg_data/` (apaga também os demais dados de desenvolvimento).
