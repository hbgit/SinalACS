#!/usr/bin/env bash
# Confere que acs_device_cert_e2e.sh, o teste device_cert_e2e.dart e a
# ferramenta device_cert_second_device.dart provam o certificado por aparelho
# (#94) na sequência do plano: emissão no emulador → conexão no broker → um
# segundo aparelho do MESMO ACS → alerta para os dois → limpeza remota do
# segundo (derrubado e recusado, serial na CRL, recarga do sidecar) → o
# emulador segue recebendo → limpeza do emulador (#81) e reemissão → trilha.
# Também: as linhas marcadoras de cada lado, o `cleanup` que derruba a
# ferramenta e devolve a stack, o manifesto apagado antes do down, a chave da
# ferramenta só em memória e a descoberta do `flutter test` fora (sufixo
# `_e2e`). Sem Docker e sem aparelho: lê o texto.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/acs_device_cert_e2e.sh
t=apps/acs/integration_test/device_cert_e2e.dart
f=apps/acs/tool/device_cert_second_device.dart
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'o teste tem sufixo _e2e (fora da descoberta)' "[[ -f $t ]]"
conferir 'a ferramenta existe em tool/' "[[ -f $f ]]"
conferir 'DEVICE com padrão emulator-5554' "grep -qF 'dev=\"\${DEVICE:-emulator-5554}\"' $s"
conferir 'usa lib_rele.sh' "grep -qF 'lib_rele.sh' $s"
conferir 'sobe a stack de e2e e semeia' "grep -qF 'e2e_stack.sh up' $s && grep -qF 'e2e_stack.sh seed' $s"
conferir 'relé com E2E_FIXTURES_FILE' "grep -qF 'E2E_FIXTURES_FILE=' $s"
conferir 'adb reverse do RPC, do broker e do relé' \
  "grep -qF 'reverse tcp:8443 tcp:443' $s && grep -qF 'reverse tcp:8883 tcp:8883' $s && grep -qF 'reverse tcp:8765 tcp:8765' $s"
conferir 'recusa relé antigo na porta 8765' "grep -qF 'porta_ocupada 8765' $s"
conferir 'credenciais fora do argv (pop do acs e do coordinator)' \
  "grep -qF \"d.pop('acs',None)\" $s && grep -qF \"d.pop('coordinator',None)\" $s"

# cleanup: derruba o teste e a ferramenta, apaga o manifesto ANTES do down e
# devolve a stack de desenvolvimento.
bloco_cleanup="awk '/^cleanup\\(\\)/,/^}/' $s"
conferir 'cleanup derruba a ferramenta' "$bloco_cleanup | grep -qF 'kill \"\$tool_pid\"'"
conferir 'cleanup derruba o teste' "$bloco_cleanup | grep -qF 'kill \"\$teste_pid\"'"
conferir 'o manifesto sai antes do down' \
  "$bloco_cleanup | grep -n -e 'rm -f .e2e/fixtures.json' -e 'e2e_stack.sh down' | head -1 | grep -qF 'fixtures.json'"
conferir 'cleanup desfaz a stack de e2e e diz como voltar a de desenvolvimento' \
  "$bloco_cleanup | grep -qF 'e2e_stack.sh down' && $bloco_cleanup | grep -qF 'docker compose up -d'"
conferir 'trap cleanup EXIT' "grep -qF 'trap cleanup EXIT' $s"

# Marcadores: cada um impresso por quem deve e exigido pelo script.
for marca in E2E_CERT_PAINEL E2E_DISPARAR_ALERTA E2E_ALERTA_NA_TELA E2E_WIPE_DEV2_PEDIDO \
             E2E_DISPARAR_ALERTA2 E2E_ALERTA2_NA_TELA E2E_WIPE_DEV1_PEDIDO E2E_CERT_OK; do
  conferir "o teste imprime $marca" "grep -qF \"print('$marca \" $t"
  conferir "o script lê $marca" "grep -qF '$marca' $s"
done
for marca in E2E_DEV2_CONECTADO E2E_DEV2_ALERTA_RECEBIDO E2E_DEV2_DERRUBADO E2E_DEV2_RECONEXAO_RECUSADA; do
  conferir "a ferramenta imprime $marca" "grep -qF \"'$marca\" $f"
  conferir "o script lê $marca" "grep -qF '$marca' $s"
done

# A ferramenta: mesmo ACS, aparelho próprio, chave só em memória.
conferir 'ferramenta lê o manifesto por E2E_FIXTURES_FILE' "grep -qF \"'E2E_FIXTURES_FILE'\" $f"
conferir 'ferramenta entra pelo login institucional (deviceId próprio)' "grep -qF 'backend.login(' $f && grep -qF 'MemoryDeviceIdStore()' $f"
conferir 'ferramenta gera par e CSR' "grep -qF 'generateDeviceKeyPair()' $f && grep -qF 'buildDeviceCsrPem(' $f"
conferir 'ferramenta pede o certificado ao backend' "grep -qF 'issueDeviceCertificate(' $f"
conferir 'ferramenta usa o client id do aparelho' "grep -qF 'deviceClientId(' $f"
conferir 'ferramenta não grava arquivo' "! grep -qE 'writeAs(String|Bytes)|openWrite' $f"
conferir 'ferramenta nunca imprime a chave' "! grep -qE 'print.*privateKeyPem|writeln\\(.*privateKeyPem' $f"
conferir 'ferramenta sem Flutter' "! grep -qF 'package:flutter' $f"

# O teste: montagem de produção do certificado e o fluxo da #81.
conferir 'o teste usa a loja do Keystore' "grep -qF 'SecureStorageDeviceCertificateStore()' $t"
conferir 'o teste usa o id da instalação real' "grep -qF 'SecureStorageDeviceIdStore()' $t"
conferir 'coordenador pelo relé' "grep -qF 'coordinatorCredentialFromRelay()' $t"
conferir 'acha o segundo aparelho pelo backoffice' "grep -qF 'admin.acsDevices(' $t"
conferir 'pede as duas limpezas' "[[ \$(grep -cF 'orderDeviceWipe(' $t) -ge 1 ]]"
conferir 'espera a tela device_wiped' "grep -qF \"Key('device_wiped')\" $t"
conferir 'entra de novo pela tela' "grep -qF \"Key('device_wiped_login')\" $t"
conferir 'espera o chip de tempo real' "grep -qF \"'Alertas em tempo real'\" $t"

# Sequência no script.
conferir 'insere o alerta e a entrega no outbox' "grep -qiF 'insert into alerts' $s && grep -qiF 'insert into alert_outbox' $s"
conferir 'assert: uma linha de device_certificates do emulador' "grep -qF 'from device_certificates' $s"
conferir 'assert: CN = microárea da fixture' "grep -qF '\\\"microAreaId\\\" = '\"'\"'\$area_id'\"'\"'' $s"
conferir 'assert: conexão no log do broker' "grep -qF 'docker logs sinalacs-mosquitto' $s && grep -qF 'New client connected' $s"
conferir 'assert: revogado como wipe' "[[ \$(grep -cE \"revocationReason.{0,2} = 'wipe'\" $s) -ge 2 ]]"
conferir 'assert: serial na CRL' "grep -qF 'openssl crl' $s"
conferir 'assert: recarga do sidecar' "grep -qF 'sinalacs-mosquitto-crl-reload' $s && grep -qF 'CRL recarregada' $s"
conferir 'assert: derrubada em até 5 s' "grep -qF -- '-le 5000' $s"
conferir 'assert: trilha device_cert_issued × 3' "grep -qF \"result = 'device_cert_issued'\" $s"
conferir 'assert: trilha device_cert_revoked × 2' "grep -qF \"result = 'device_cert_revoked:wipe'\" $s"
conferir 'assert: cadeia de auditoria' "grep -qF 'audit_chain_check' $s"
conferir 'linha final de sucesso' "grep -qF \"echo 'E2E do certificado por aparelho: OK'\" $s"

if [[ $falhas -gt 0 ]]; then echo "$falhas conferência(s) falharam" >&2; exit 1; fi
echo OK
