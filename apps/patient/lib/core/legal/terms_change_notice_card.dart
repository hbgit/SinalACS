import 'package:flutter/material.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show TermsChangeNotice;
import 'package:sinalacs_patient/app/patient_theme.dart';

/// Aviso, dentro do app, de que os termos vão mudar (LGPD-RF18: 15 dias de
/// antecedência). Dispensável e nunca bloqueia nada: o alerta de urgência não
/// espera por leitura de termos.
class TermsChangeNoticeCard extends StatelessWidget {
  const TermsChangeNoticeCard({
    super.key,
    required this.notice,
    required this.onRead,
    required this.onDismiss,
    this.onReadNew,
  });

  final TermsChangeNotice notice;
  final VoidCallback onRead;
  final VoidCallback onDismiss;

  /// Só passado quando o app carrega o texto da versão anunciada; sem ele o cartão
  /// oferece apenas o texto vigente.
  final VoidCallback? onReadNew;

  /// `dd/mm/aaaa` no fuso local.
  static String formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('terms_change_notice_card'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: PatientColors.accentOnSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: const Text(
                      'Os termos vão mudar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('terms_change_notice_dismiss'),
                  tooltip: 'Dispensar aviso',
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                ),
              ],
            ),
            Text(
              'A versão ${notice.version} passa a valer em ${formatDate(notice.effectiveFrom)}. '
              '${notice.summary}',
            ),
            if (onReadNew != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonal(
                  key: const Key('terms_change_notice_read_new'),
                  onPressed: onReadNew,
                  child: const Text('Ler o texto novo'),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('terms_change_notice_read'),
                onPressed: onRead,
                child: const Text('Ler os termos atuais'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
