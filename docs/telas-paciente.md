# Telas do App Paciente

Documentação visual do protótipo Flutter do paciente. As imagens foram capturadas no emulador Android `sdk gphone64 x86 64` usando somente dados sintéticos.

## Navegação

Os destinos principais são **Urgência**, **Triagem** e **Status**. O item **Mais** reúne **Perfil clínico**, **Lembretes** e **Meus dados** (o "Canal de dúvidas" foi removido em 2026-09-21 — contradizia a exclusão explícita de mensageria assíncrona do escopo MVP, `spec/PRD_system.md` §6.1).

## Autenticação inclusiva

A tela inicial apresenta CPF, data de nascimento, entrada sem senha e acesso de QR Code. O fluxo atual encaminha diretamente para a triagem; OTP e leitura de QR Code ainda dependem de integração.

## Alerta de urgência

![Estado inicial do alerta de urgência](screenshots/patient/01-emergencia.png)

O botão circular de emergência possui confirmação antes de alterar o estado local. A tela informa que a localização disponível será incluída. Nesta fase, o alerta é um estado local demonstrativo: MQTT, geolocalização real e confirmação de entrega ainda não estão conectados.

## Triagem rápida

Fluxo de três perguntas com indicador de progresso e uma alternativa por etapa. A classificação é determinística e não pode ser editada pela pessoa usuária. Ao finalizar, encaminha para o acompanhamento da solicitação.

## Perfil clínico

Permite marcar condições crônicas (diabetes, hipertensão, uso contínuo de insulina) e mostra o estado ativo ou inativo de cada uma. Desde 2026-09-21, lê e grava de verdade em `patients.myChronicConditions`/`updateChronicConditions`, cifrado em repouso (AES-256-GCM) — não é mais estado só do protótipo.

## Acompanhamento de solicitação

Apresenta a linha do tempo `Enviado`, `Visualizado`, `Em análise` e `Agendado`, acompanhada de risco e atualização de exemplo da equipe ACS. Os dados são locais e sintéticos.

## Lembretes

Lista lembretes de medicamentos e de rotina, com controles de ativação. A criação e o agendamento de notificações do sistema ainda não foram integrados.

## Meus dados

Painel de direitos LGPD (adicionado em 2026-09-21): confirmação de que os dados do paciente estão sendo tratados, o cadastro (nome, data de nascimento, contato de emergência, condições crônicas), o histórico de consentimentos e o histórico de classificação de risco (triagens e alertas — nunca o conteúdo bruto de uma triagem nem a localização de um alerta). Um botão copia tudo como JSON para a área de transferência, para a pessoa guardar ou compartilhar onde quiser.

## Referências

- [Implementação Flutter](../apps/patient/lib/app/app.dart)
- [Protótipos de referência](../spec/ui_paciente)
- [Guia visual](../spec/ui_design.md)
