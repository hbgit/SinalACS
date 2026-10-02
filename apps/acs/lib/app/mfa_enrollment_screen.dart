import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show TotpEnrollmentStart;

/// Ativação da verificação em duas etapas (RF07 / LGPD-RT06).
///
/// Sem token: o ACS acabou de provar matrícula e senha. O segredo aparece só
/// aqui, em QR e em texto, e **não** é gravado no aparelho.
class MfaEnrollmentScreen extends StatefulWidget {
  const MfaEnrollmentScreen({
    super.key,
    required this.backend,
    required this.matricula,
    required this.senha,
  });

  final AcsBackend backend;
  final String matricula;
  final String senha;

  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  final _codigo = TextEditingController();
  TotpEnrollmentStart? _inicio;
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      final inicio = await widget.backend.beginTotpEnrollment(matricula: widget.matricula, senha: widget.senha);
      if (mounted) setState(() => _inicio = inicio);
    } on BackendFailure catch (falha) {
      if (mounted) setState(() => _erro = falha.message);
    }
  }

  Future<void> _confirmar() async {
    if (_ocupado) return;
    setState(() { _ocupado = true; _erro = null; });
    try {
      await widget.backend.confirmTotpEnrollment(
        matricula: widget.matricula,
        senha: widget.senha,
        code: _codigo.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BackendFailure catch (falha) {
      if (mounted) setState(() { _erro = falha.message; _ocupado = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicio = _inicio;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificação em duas etapas')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('Leia o QR no aplicativo autenticador (ou digite a chave) e informe o código de 6 dígitos que ele mostrar.'),
          const SizedBox(height: 16),
          if (inicio == null && _erro == null) const Center(child: CircularProgressIndicator()),
          if (inicio != null) ...[
            // Fundo branco com módulos escuros por exigência de leitura: não usa token de tema.
            Center(child: QrImageView(data: inicio.otpauthUri, size: 200, backgroundColor: Colors.white)),
            const SizedBox(height: 12),
            SelectableText(inicio.secretBase32, key: const Key('mfa_secret')),
          ],
          if (_erro != null)
            Semantics(liveRegion: true, child: Text(_erro!, key: const Key('mfa_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          TextField(
            key: const Key('mfa_code_field'),
            controller: _codigo,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Código de 6 dígitos'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('mfa_confirm_button'),
            onPressed: inicio == null || _ocupado ? null : _confirmar,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            child: const Text('Ativar'),
          ),
        ],
      ),
    );
  }
}
