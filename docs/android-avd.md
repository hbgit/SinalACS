# AVD Android para validação SinalACS

O E2E usa um emulador Android com API 36, arquitetura `x86_64` e identificador
`emulator-5554`. Os comandos abaixo criam a AVD em uma máquina de desenvolvimento
com Android SDK instalado.

```bash
sdkmanager "platform-tools" "platforms;android-36" "system-images;android-36;google_apis;x86_64"
echo no | avdmanager create avd \
  --name sinalacs-api36 \
  --package "system-images;android-36;google_apis;x86_64" \
  --device "pixel_7"
emulator -avd sinalacs-api36 -no-snapshot -no-boot-anim
adb wait-for-device
adb devices
```

O dispositivo listado pelo `adb devices` deve estar como `emulator-5554\tdevice`.
O teste pode então ser executado com:

```bash
./scripts/qa/e2e.sh --emulator
```

A AVD deve usar somente seed sintético. Nunca carregue dados reais, credenciais
institucionais ou chaves de produção no emulador.
