/// Um lembrete local de saúde (medicamento, pesagem, etc.).
///
/// Local ao dispositivo, sem endpoint de backend (decisão §3.1 de
/// docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md):
/// trocar de aparelho recria os lembretes, não há sincronização.
class Reminder {
  const Reminder({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.active,
  });

  /// Identificador local, também usado como id da notificação agendada —
  /// precisa caber em 31 bits (`flutter_local_notifications` usa `int` de
  /// notificação no Android).
  final int id;
  final String label;
  final int hour;
  final int minute;
  final bool active;

  Reminder copyWith({String? label, int? hour, int? minute, bool? active}) => Reminder(
        id: id,
        label: label ?? this.label,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        active: active ?? this.active,
      );
}
