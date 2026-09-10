#!/usr/bin/env bash
# Bloco 4 — Demo do app do ACS (1:15–2:05, 50 s).
#
# NAVEGAÇÃO: o login faz pushReplacement para o shell cujo destino inicial é
# AcsDestination.queue (apps/acs/lib/app/app.dart:55) — o app abre no Dashboard,
# não na Territorialização. Por isso há um toque extra na aba "Área".
#
# NÃO FILMAR (tabela de guardrails do roteiro): "Atualizar dados da microárea",
# "Traçar rota eficiente", "Ligar para o SAMU (192)", "Encaminhar para UBS
# Central", "Abrir formulário da visita", "Preparar aviso", o card verde da Ana
# Costa e o card amarelo do João (que abre o formulário com o nome da Maria).
# Este script não toca em nenhum deles — não acrescente toques sem reler a
# tabela.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/coords.env"

PKG="${ACS_PKG:-com.example.sinalacs_acs}"

check_coords() {
  for name in ACS_LOGIN ACS_TAB_AREA ACS_TAB_QUEUE ACS_TAB_VISIT \
              ACS_VISIT_OUTCOME ACS_VISIT_NOTES ACS_VISIT_SAVE; do
    [ "${!name}" != "0 0" ] || die "coords.env: $name ainda é placeholder. Rode ./discover.sh primeiro."
  done
}

require_device
check_coords
trap device_reset EXIT
device_prepare

info "abrindo o app do ACS (do zero)"
# force-stop é obrigatório: sem ele o app reabre já logado, numa aba qualquer,
# e a tomada começa na tela errada.
"$ADB" shell input keyevent KEYCODE_WAKEUP
"$ADB" shell am force-stop "$PKG"
sleep 1
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5

start_record acs

# Login: matrícula e senha já vêm pré-preenchidas (app.dart:23-24), um toque só.
tap $ACS_LOGIN 5.0

# 1:15 — Territorialização. Só exibir. O botão "Atualizar dados da microárea"
# NÃO pode ser tocado.
tap $ACS_TAB_AREA 3.0
info "Territorialização — 9 s parados"
sleep 9

# 1:26 — fila priorizada. Corte seco vindo do 'Risco: Vermelho' do bloco 3 cai
# aqui, no card vermelho da Maria no topo.
tap $ACS_TAB_QUEUE 2.0
# O roteiro marca o formulário de visita em 1:45, ou seja 19 s de fila. Com 8 s
# a cena de visita entrava cedo demais e a legenda "a cor nunca é decoração"
# corria sobre o formulário em vez da fila colorida.
info "Dashboard — 13 s, com rolagem lenta"
sleep 6
"$ADB" shell input swipe 540 1600 540 1150 1200   # rolagem devagar, mostra os 3 cards
sleep 6

# 1:45 — registro de visita, com o aparelho SEM REDE. É a prova visual mais
# forte do bloco; filmar o toque e o SnackBar em plano contínuo.
airplane_on
tap $ACS_TAB_VISIT 3.0

# O dropdown "Status do atendimento" já vem com "Realizada com sucesso"
# (visível em quadro). Não o abrimos: o menu suspenso taparia o formulário e
# o valor certo já está lá — abrir e fechar seria risco sem ganho na tomada.
info "formulário em quadro — 3 s antes de digitar"
sleep 3

tap $ACS_VISIT_NOTES 1.2
type_text "Paciente orientada e encaminhada"
sleep 1.5
"$ADB" shell input keyevent KEYCODE_BACK   # fecha o teclado, libera o botão em quadro
sleep 2

info "salvando — SnackBar de enfileiramento"
tap $ACS_VISIT_SAVE 5.0

airplane_off
stop_record acs
