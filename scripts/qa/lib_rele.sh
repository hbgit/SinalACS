# Funções compartilhadas pelos runners que sobem o relé de credenciais do e2e
# (scripts/qa/otp_relay.py — nome histórico; ver o docstring dele).
# Uso: source "$(dirname "${BASH_SOURCE[0]}")/lib_rele.sh"

# Sucesso (0) se ALGUM processo escuta na porta TCP $1, em qualquer endereço
# (127.0.0.1, 0.0.0.0, [::] ou o IP da rede). Um relé antigo esquecido num
# deles responderia com a credencial de uma execução anterior; olhar só
# 127.0.0.1 deixava passar os outros e o erro só aparecia no bind do relé
# novo, sem dizer o motivo.
porta_ocupada() {
  ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN
}
