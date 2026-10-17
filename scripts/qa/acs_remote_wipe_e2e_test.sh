#!/usr/bin/env bash
# Confere que acs_remote_wipe_e2e.sh e o teste remote_wipe_e2e.dart provam a
# limpeza remota (#81) no aparelho real: montagem de produção do id, da chave,
# dos tokens de envio e do diário; visita deixada pendente pelo decorator sem
# "Sair" (o envio do logout a subiria); pedido pelo coordenador do relé; gatilho
# pela volta do segundo plano; e o script terminando nos asserts que só o banco
# responde, com o manifesto apagado antes do down — e que a descoberta do
# `flutter test` não alcança o teste (sufixo `_e2e`). Sem Docker e sem aparelho:
# lê o texto.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/acs_remote_wipe_e2e.sh
t=apps/acs/integration_test/remote_wipe_e2e.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'o teste tem sufixo _e2e (fora da descoberta)' "[[ -f $t ]]"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'usa lib_rele.sh' "grep -qF 'lib_rele.sh' $s"
conferir 'sobe a stack de e2e e semeia' "grep -qF 'e2e_stack.sh up' $s && grep -qF 'e2e_stack.sh seed' $s"
conferir 'relé com E2E_FIXTURES_FILE' "grep -qF 'E2E_FIXTURES_FILE=' $s"
conferir 'adb reverse do RPC e do relé' "grep -qF 'reverse tcp:8443 tcp:443' $s && grep -qF 'reverse tcp:8765 tcp:8765' $s"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
conferir 'credenciais fora do argv (pop do coordinator)' "grep -qF \"d.pop('coordinator',None)\" $s"
conferir 'o manifesto sai antes do down' \
  "awk '/^cleanup\\(\\)/,/^}/' $s | grep -n -e 'rm -f .e2e/fixtures.json' -e 'e2e_stack.sh down' | head -1 | grep -qF 'fixtures.json'"

# Montagem de produção no que a prova mede.
for loja in SecureStorageDeviceIdStore SecureStorageDatabaseKeyStore SecureStorageUploadTokenStore SharedPreferencesWipeJournal; do
  conferir "o teste usa $loja" "grep -qF '$loja()' $t"
done
conferir 'o teste usa o arquivo real do app' "grep -qF \"'sinalacs_acs.db'\" $t"
conferir 'visita pendente pelo decorator de envio' "grep -qF 'EnvioDeVisitasForaDoAr(real)' $t"
conferir 'sem "Sair" antes da limpeza (o envio do logout subiria a visita)' "! grep -qF 'logout_button' $t"
conferir 'coordenador pelo relé' "grep -qF 'coordinatorCredentialFromRelay()' $t"
conferir 'ativação da MFA do coordenador' "grep -qF 'beginStaffTotpEnrollment' $t && grep -qF 'confirmStaffTotpEnrollment' $t"
conferir 'pedido com motivo stolen' "grep -qF 'orderDeviceWipe(' $t && grep -qF 'DeviceWipeReason.stolen' $t"
conferir 'gatilho pela volta do segundo plano' \
  "grep -qF 'AppLifecycleState.paused' $t && grep -qF 'AppLifecycleState.resumed' $t && grep -qF 'handleAppLifecycleStateChanged' $t"
conferir 'espera a tela device_wiped' "grep -qF \"Key('device_wiped')\" $t"
conferir 'entra de novo pela tela' "grep -qF \"Key('device_wiped_login')\" $t"
conferir 'confere o id novo diferente' "grep -qF 'isNot(idAntigo)' $t"
conferir 'confere os tokens de envio vazios' "grep -qF 'uploadTokens.owners(), isEmpty' $t"
conferir 'confere a chave trocada' "grep -qF 'chaveNova == chaveAntiga' $t"
conferir 'a chave nunca é impressa' "! grep -qE 'print\\(.*chave(Nova|Antiga)' $t"

for marca in E2E_WIPE_PEDIDO E2E_WIPE_APARELHO E2E_WIPE_OK; do
  conferir "o teste imprime $marca" "grep -qF \"print('$marca\" $t"
  conferir "o script exige $marca" "grep -qF '$marca' $s"
done

# Asserts que só o banco responde.
conferir 'assert: pedido com motivo stolen' "grep -qF 'from device_wipe_orders' $s && grep -qF '|stolen|' $s"
conferir 'assert: deliveredAt e confirmedAt' "grep -qF '\\\"deliveredAt\\\" is not null and \\\"confirmedAt\\\" is not null' $s"
conferir 'assert: refresh tokens do id antigo revogados' "grep -qF 'from acs_refresh_tokens where \\\"deviceId\\\" = '\"'\"'\$aparelho'\"'\"' and \\\"revokedAt\\\" is null' $s"
conferir 'assert: tokens de envio do id antigo revogados' "grep -qF 'from acs_upload_tokens where \\\"deviceId\\\" = '\"'\"'\$aparelho'\"'\"' and \\\"revokedAt\\\" is null' $s"
for evento in wipe_ordered wipe_delivered wipe_confirmed; do
  conferir "assert: trilha $evento com o resourceId do pedido" "grep -qF \"result = '$evento'\" $s"
done
conferir 'assert: wipe_ordered pelo coordenador' "grep -qF 'and \\\"userId\\\" = '\"'\"'\$coord_id'\"'\"'' $s"
conferir 'assert: a visita não está em visits' "grep -qF 'from visits where \\\"localId\\\" = ' $s"
conferir 'assert: cadeia de auditoria' "grep -qF 'audit_chain_check' $s"
conferir 'linha final de sucesso' "grep -qF \"echo 'E2E de limpeza remota: OK'\" $s"

if [[ $falhas -gt 0 ]]; then echo "$falhas conferência(s) falharam" >&2; exit 1; fi
echo OK
