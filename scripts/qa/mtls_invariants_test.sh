#!/usr/bin/env bash
# Confere, sem Docker e sem broker (lê o texto), que scripts/qa/mtls_invariants.sh
# continua provando o desenho do broker da #94 do jeito certo:
#   · os nove grupos A–I existem;
#   · em cada grupo o PRIMEIRO `esperar` é um positivo (`aceito`): um "recusado"
#     sem controle positivo antes seria verdade por acidente (broker parado,
#     certificado ilegível, porta errada);
#   · a CRL original é copiada no início e restaurada pelo `trap` de saída, com
#     recarga, para o broker voltar à CRL do backend mesmo quando o script falha;
#   · nenhuma senha aparece (a identidade é o certificado; o único `-u` é o do
#     Grupo G, que prova justamente que o username do CONNECT é ignorado);
#   · `set -euo pipefail` e a saída 4 para falha de infraestrutura.
# E, no mesmo espírito, que o sidecar valida a CRL (sintaxe e assinatura) antes
# de sinalizar o broker, e que o mosquitto.conf não tem mais password_file.
set -euo pipefail
cd "$(dirname "$0")/../.."
s=scripts/qa/mtls_invariants.sh
r=infra/docker/mosquitto/crl_reload.sh
c=infra/docker/mosquitto/mosquitto.conf
falhas=0
conferir() { if ! eval "$2"; then echo "FALHOU: $1" >&2; falhas=$((falhas+1)); fi; }
# Corpo de uma função de primeiro nível do script: da linha `nome() {` até `}`.
corpo() { awk -v f="$1" '$0 ~ "^"f"\\(\\) \\{" {d=1} d {print} d && /^}/ {exit}' "$s"; }

conferir 'o script existe e é bash válido' "[[ -f $s ]] && bash -n $s"
conferir 'set -euo pipefail' "grep -qx 'set -euo pipefail' $s"
conferir 'falha de infraestrutura sai com 4 dentro do esperar' "corpo esperar | grep -qF 'exit 4'"

for g in A B C D E F G H I; do
  conferir "o grupo $g existe" "grep -qE \"^grupo $g \" $s"
done

# Em cada grupo, o primeiro `esperar` é aceito; e cada grupo tem ao menos um.
ordem="$(awk '
  /^grupo [A-I] / { if (g != "" && n == 0) print "grupo " g " sem esperar"; g = $2; n = 0; next }
  /^[[:space:]]*esperar (aceito|recusado) / {
    if (g == "") { print "esperar fora de grupo: " $0; next }
    n++
    if (n == 1 && $2 == "recusado") print "grupo " g ": negativo antes de qualquer positivo"
  }
  END { if (g != "" && n == 0) print "grupo " g " sem esperar" }
' "$s")"
conferir "cada negativo é precedido de um positivo no mesmo grupo${ordem:+ ($ordem)}" "[[ -z \"\$ordem\" ]]"
conferir 'há negativos de verdade (recusado) no script' "[[ \$(grep -cE '^[[:space:]]*esperar recusado ' $s) -ge 6 ]]"

# CRL: cópia no início, restauração no trap.
conferir 'copia a crl.pem original antes da primeira troca' \
  "awk '/^cp \"\\\$devices\\/crl.pem\" \"\\\$tmp\\/crl-original.pem\"/{c=NR} /^esperar .*trocar_crl /{if(!g)g=NR} END{exit !(c && g && c<g)}' $s"
conferir 'trap de saída chama limpar' "grep -qx 'trap limpar EXIT' $s"
conferir 'limpar restaura a CRL' "corpo limpar | grep -qF 'restaurar_crl'"
conferir 'restaurar_crl grava a cópia original e espera a recarga' \
  "corpo restaurar_crl | grep -qF 'gravar_crl crl-original.pem' && corpo restaurar_crl | grep -qF 'CRL recarregada'"
conferir 'gravação atômica (temporário + mv)' "corpo gravar_crl | grep -qF 'mv /d/crl.pem.tmp /d/crl.pem'"

# Sem senha: nada de -P, de variável de senha ou de passwordfile; um só `-u`, no G.
conferir 'nenhuma senha (-P, --pw, PASSWORD, passwordfile)' \
  "! grep -qE '(^|[[:space:]])-P[[:space:]]|--pw|PASSWORD|passwordfile|password_file' $s"
conferir 'um único publicar com -u, o -u backend do Grupo G' \
  "[[ \$(grep -cE '^[[:space:]]*publicar [^#]*[[:space:]]-u[[:space:]]' $s) -eq 1 ]] && awk '/^grupo G /{g=1} /^grupo H /{g=0} g && /^[[:space:]]*publicar [^#]*[[:space:]]-u backend[[:space:]]/{f=1} END{exit !f}' $s"
conferir 'assinantes nunca mandam -u' "! corpo assinar | grep -qE '[[:space:]]-u[[:space:]]'"

# O que cada grupo precisa tocar para provar o que diz.
conferir 'D emite o certificado compartilhado antigo com a CA do servidor' \
  "grep -qF '/s/ca.key' $s && grep -qF 'CN=acs-area-12' $s"
conferir 'E e I esperam o log do sidecar' "grep -qF \"'CRL recarregada'\" $s && grep -qF \"'CRL recusada pelo sidecar'\" $s"
conferir 'E revoga por openssl ca -revoke e -gencrl' "grep -qF 'openssl ca -batch -config /f/aparelhos.cnf -revoke' $s && grep -qF 'openssl ca -batch -config /f/aparelhos.cnf -gencrl' $s"
conferir 'F derruba a sessão conectando como backend com o client id de A' "grep -qF 'publicar /d/backend -i \"\$id_a\"' $s"
conferir 'I grava lixo e uma CRL válida de outra CA' "grep -qF 'trocar_crl lixo.pem' $s && grep -qF 'trocar_crl crl-fora.pem' $s"
conferir 'H exige nextUpdate de pelo menos 7 dias' "grep -qF 'proxima_atualizacao_em_dias crl-original.pem 7' $s"

# Sidecar e configuração do broker.
conferir 'o sidecar existe e é sh válido' "[[ -f $r ]] && sh -n $r"
conferir 'o sidecar valida assinatura (-CAfile) e exige verify OK' \
  "grep -qF 'openssl crl -in \"\$crl\" -CAfile \"\$ca\" -noout' $r && grep -qF 'verify OK' $r"
conferir 'o sidecar só sinaliza o broker no ramo validado' \
  "awk '/verify OK/{v=NR} /kill -HUP/{k=NR} END{exit !(v && k && v<k)}' $r"
conferir 'o sidecar loga recarga e recusa' "grep -qF 'CRL recarregada' $r && grep -qF 'CRL recusada pelo sidecar, não recarregada' $r"
conferir 'mosquitto.conf sem password_file' "! grep -qE '^[[:space:]]*password_file' $c"
for linha in 'use_identity_as_username true' 'require_certificate true' 'allow_anonymous false' \
             'crlfile /mosquitto/devices/crl.pem' 'cafile /mosquitto/devices/ca.crt' 'tls_version tlsv1.3'; do
  conferir "mosquitto.conf: $linha" "grep -qx '$linha' $c"
done

if [[ $falhas -gt 0 ]]; then echo "$falhas conferência(s) falharam" >&2; exit 1; fi
echo OK
