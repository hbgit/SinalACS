/// Espelho local (no aparelho) da decisão de consentimento tomada no
/// onboarding para `ConsentPurpose.localReminders`. A gravação de verdade
/// (evidência para auditoria/LGPD) é em `consent_logs`, no backend, pelo
/// fluxo de onboarding — este store existe só porque RF06 é local ao
/// aparelho, sem endpoint de backend (decisão §3.1 de
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md), e
/// portanto o único jeito de `RemindersScreen` saber a resposta é guardar
/// uma cópia no momento em que ela é conhecida (conclusão do onboarding).
abstract interface class ConsentPreferences {
  /// `false` — inclusive quando não há nenhum registro local ainda — nunca
  /// `true` por omissão. Ausência de dado é tratada como recusa, não como
  /// aceite: o risco de agendar uma notificação sem consentimento é maior
  /// que o de deixar de agendar uma que teria sido permitida.
  Future<bool> localRemindersGranted();

  Future<void> saveLocalRemindersConsent(bool granted);
}
