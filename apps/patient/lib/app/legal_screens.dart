import 'package:flutter/material.dart';
import 'package:sinalacs_patient/app/patient_theme.dart';
import 'package:sinalacs_patient/core/legal/legal_documents.dart';
import 'package:sinalacs_patient/core/network/backend_client.dart';
import 'package:sinalacs_patient/core/network/backend_scope.dart';

/// Índice "Privacidade e termos": abre a partir do login (antes do cadastro,
/// para ler antes de aceitar) e do menu "Mais" — Mais → Privacidade e termos →
/// documento, três toques (painel de privacidade em até 3 cliques,
/// LGPD-RF03).
class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key, this.upcoming, this.effectiveLabel});

  /// Quando presente, lista o texto que ainda **não vale** (aviso de 15 dias).
  final UpcomingLegalDocuments? upcoming;

  /// Data em que o texto novo passa a valer (`dd/mm/aaaa`), para o subtítulo.
  final String? effectiveLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(upcoming == null ? 'Privacidade e termos' : 'Termos que passam a valer'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (key, document) in [
              ('legal_open_privacy', upcoming?.privacy ?? privacyPolicy),
              ('legal_open_terms', upcoming?.terms ?? termsOfUse),
            ])
              Card(
                child: ListTile(
                  key: Key(key),
                  leading: Icon(
                    document.id == 'privacy'
                        ? Icons.privacy_tip_outlined
                        : Icons.description_outlined,
                  ),
                  title: Text(document.title),
                  subtitle: Text(
                    upcoming == null
                        ? 'Versão ${document.version} · vigente desde ${document.effectiveDate}'
                        : 'Versão ${document.version} · passa a valer em ${effectiveLabel ?? document.effectiveDate}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LegalDocumentScreen(document: document),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Um documento legal: primeiro o resumo visual (passos numerados, na ordem
/// em que o dado circula — LGPD-RF10), depois a versão completa em seções
/// expansíveis e, por fim, o histórico de versões (LGPD-RF18/RF19).
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Versão ${document.version} · vigente desde ${document.effectiveDate}',
              key: const Key('legal_version'),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'Resumo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Column(
              key: const Key('legal_summary'),
              children: [
                for (final (index, step) in document.summary.indexed)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        // `accentDark`, não `accent`: o dígito é texto normal
                        // e branco sobre `accent` fica abaixo de 4.5:1.
                        backgroundColor: PatientColors.accentDark,
                        foregroundColor: Colors.white,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(
                        step.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(step.text),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Texto completo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            for (final (index, section) in document.sections.indexed)
              ExpansionTile(
                key: Key('legal_section_$index'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                expandedAlignment: Alignment.centerLeft,
                title: Text(section.title),
                children: [Text(section.body)],
              ),
            const SizedBox(height: 16),
            const Text(
              'Histórico de versões',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Column(
              key: const Key('legal_history'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in document.history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${entry.version} · ${entry.version == document.version ? 'vigente desde' : 'de'} ${entry.date}',
                    ),
                    subtitle: Text(entry.changes),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Convite para aceitar o Termo de Uso e a Política de Privacidade vigentes,
/// mostrado depois do login por OTP a quem ainda não aceitou a versão atual
/// (LGPD-RF18).
///
/// **Não é um portão.** "Agora não" segue para a tela inicial e o aviso volta
/// no próximo login: um paciente em emergência precisa chegar ao alerta de
/// urgência sem ler nada antes (invariante "red alerts never dropped").
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({required this.onContinue, super.key});

  /// Chamado depois do aceite gravado, ou ao escolher "Agora não".
  final VoidCallback onContinue;

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _checked = false;
  bool _busy = false;
  bool _left = false;
  String? _error;

  /// Sai da tela uma vez só: um segundo toque em "Agora não" durante a
  /// transição não pode empilhar a tela inicial de novo.
  void _continue() {
    if (_left) return;
    _left = true;
    widget.onContinue();
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackendScope.of(context).acceptTermsOfUse();
      if (!mounted) return;
      _continue();
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termo de Uso e Privacidade')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Para usar o app com tudo em dia, leia e aceite o Termo de Uso e a '
              'Política de Privacidade (versão $legalDocumentsVersion). Você pode '
              'aceitar depois: o alerta de urgência continua disponível.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('terms_gate_read_button'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalDocumentsScreen()),
              ),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Ler o Termo e a Política'),
            ),
            CheckboxListTile(
              key: const Key('terms_gate_checkbox'),
              value: _checked,
              onChanged: _busy ? null : (value) => setState(() => _checked = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Li e aceito o Termo de Uso e a Política de Privacidade.'),
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('terms_gate_error'),
                  style: const TextStyle(color: PatientColors.dangerOnSurface),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('terms_gate_accept_button'),
              onPressed: _checked && !_busy ? _accept : null,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              child: const Text('Aceitar e continuar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('terms_gate_later_button'),
              onPressed: _busy ? null : _continue,
              style: TextButton.styleFrom(minimumSize: const Size(48, 52)),
              child: const Text('Agora não'),
            ),
          ],
        ),
      ),
    );
  }
}
