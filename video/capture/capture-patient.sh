#!/usr/bin/env bash
# Bloco 3 — Demo do app do paciente (0:35–1:15, 40 s).
#
# Percurso e tempos vêm da tabela do bloco 3 em docs/roteiro-video-sponsor.md.
#
# BEAT CENTRAL: "Risco: Vermelho" é renderizado sob `if (_step == 2)`
# (apps/patient/lib/app/app.dart:279), portanto aparece assim que a tela do
# passo 3 monta — ANTES de marcar a terceira resposta. E tocar "Concluir
# triagem" (`:273`) troca a TriageScreen pela StatusScreen, fazendo o texto
# sumir. Por isso o script para 6 s no passo 3 antes de tocar em qualquer coisa:
# é esse intervalo que a edição congela e amplia.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/coords.env"

PKG="${PATIENT_PKG:-com.example.sinalacs_patient}"

check_coords() {
  for name in PATIENT_CPF_FIELD PATIENT_BIRTH_FIELD PATIENT_ENTER \
              PATIENT_Q1_BREATH PATIENT_NEXT_1 PATIENT_Q2_SUDDEN PATIENT_NEXT_2 \
              PATIENT_Q3_CHEST PATIENT_CONCLUDE; do
    [ "${!name}" != "0 0" ] || die "coords.env: $name ainda é placeholder. Rode ./discover.sh primeiro."
  done
}

require_device
check_coords
trap device_reset EXIT
device_prepare

info "abrindo o app do paciente (do zero)"
# force-stop é obrigatório: sem ele o app reabre no meio do fluxo anterior e a
# tomada começa na tela errada.
"$ADB" shell input keyevent KEYCODE_WAKEUP
"$ADB" shell am force-stop "$PKG"
sleep 1
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5

start_record patient

# 0:35 — login sem senha. Dados sintéticos: nunca CPF real (invariante LGPD).
# O KEYCODE_BACK fecha o teclado entre os campos; sem isso o teclado tapa o
# botão "Entrar sem senha" e o toque seguinte cai no lugar errado.
tap $PATIENT_CPF_FIELD 0.8
type_text "12345678900"
"$ADB" shell input keyevent KEYCODE_BACK; sleep 0.8
tap $PATIENT_BIRTH_FIELD 0.8
type_text "10041954"
"$ADB" shell input keyevent KEYCODE_BACK; sleep 1.2
tap $PATIENT_ENTER 3.0

# 0:42 — passo 1. "Falta de ar" leva SEMPRE a vermelho (_risk, app.dart:251),
# o que torna a tomada repetível.
tap $PATIENT_Q1_BREATH 2.5
tap $PATIENT_NEXT_1 2.5

# 0:50 — passo 2. O botão sobe para Y=983: são 2 opções em vez das 4 do passo 1.
tap $PATIENT_Q2_SUDDEN 2.0
tap $PATIENT_NEXT_2 2.0

# 0:56 — passo 3. NÃO TOCAR: "Risco: Vermelho" já está em tela. Este é o quadro
# que a edição congela por 1,5 s com zoom suave.
info "beat de 'Risco: Vermelho' — 7 s parados, sem tocar"
sleep 7

# 1:01 — marca a terceira resposta e conclui.
tap $PATIENT_Q3_CHEST 2.0
tap $PATIENT_CONCLUDE 3.0

# 1:05 — StatusScreen: "Triagem Vermelha" e a linha do tempo de 4 estados.
# O bloco 3 tem 40 s. Gravamos ~45 s de propósito: a montagem corta o excedente
# e a folga evita ter de voltar ao aparelho se um beat precisar de mais ar.
info "StatusScreen — 12 s"
sleep 12

stop_record patient
