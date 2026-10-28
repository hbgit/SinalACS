/// Versão do app enviada com cada evento de telemetria: a de
/// `apps/acs/pubspec.yaml` SEM o sufixo `+build` (pubspec `1.0.0+1` vira
/// `'1.0.0'`). `test/app_version_test.dart` compara com o pubspec; ao subir a
/// versão, mude as duas.
const acsAppVersion = '1.0.0';
