import 'package:flutter/material.dart';

/// Aviso do limite da cifra local do app do paciente (#136).
///
/// Mostrado em "Lembretes" (onde o usuário do pilar A chega) e em "Meus
/// dados". O texto promete só o que existe: o banco local é cifrado, e isso
/// não protege de quem usa o celular desbloqueado. Não cita expiração nem
/// "Apagar meus dados" (C-10, #131, ainda não implementada). Usa as cores
/// normais do tema; cor clínica não entra aqui.
class LocalProtectionNotice extends StatelessWidget {
  const LocalProtectionNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('local_protection_notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Proteção dos dados neste aparelho.',
              style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'O que o SinalACS guarda neste celular fica cifrado. Isso protege '
            'se alguém copiar os arquivos do aparelho, mas não protege de quem '
            'usa o seu celular desbloqueado. Não empreste o celular desbloqueado.',
            style: TextStyle(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
