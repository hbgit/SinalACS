#!/usr/bin/env bash
# Conserta as capturas de tela do repositório (item 2 da "Preparação antes de
# gravar" do roteiro).
#
# PROBLEMA: docs/screenshots/acs/01-login.png e
# docs/screenshots/patient/01-emergencia.png são byte-idênticos
# (md5 2d6f1cef705bb806fd7cff4672a558fc), e o conteúdo das DUAS é a tela de
# urgência do paciente. Ou seja, patient/01-emergencia.png está correto e
# acs/01-login.png guarda a imagem errada — nunca existiu captura do login
# institucional do ACS, embora a tela exista em código
# (apps/acs/lib/app/app.dart:16-49) e docs/telas-acs.md a descreva.
#
# Uso: navegue manualmente até a tela do login do ACS e rode este script.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_device

TARGET="$REPO_DIR/docs/screenshots/acs/01-login.png"

echo "Confirme que o aparelho está mostrando o LOGIN INSTITUCIONAL DO ACS"
echo "  (eyebrow 'SEGURANÇA E RASTREABILIDADE', 'Acesso institucional',"
echo "   campos 'Matrícula / CNS' e 'Senha de acesso')."
read -r -p "Pronto? [s/N] " ok
[ "$ok" = "s" ] || die "cancelado"

device_prepare
trap device_reset EXIT

screenshot acs-login "$TARGET"

echo
echo "md5 novo:  $(md5sum "$TARGET" | cut -d' ' -f1)"
echo "md5 antigo: 2d6f1cef705bb806fd7cff4672a558fc  (se for igual, a captura NÃO mudou)"
echo
echo "Confira também que docs/telas-acs.md continua descrevendo esta imagem corretamente."
