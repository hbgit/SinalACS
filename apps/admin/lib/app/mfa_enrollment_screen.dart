import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';

/// Ativação da verificação em duas etapas do staff.
///
/// Sem token: matrícula e senha acabaram de ser provadas. O segredo aparece só
/// aqui, em QR e em texto, e **não** é gravado no aparelho. Fecha com
/// `pop(true)` quando o servidor confirma o código.
class MfaEnrollmentScreen extends StatefulWidget {
  const MfaEnrollmentScreen({super.key, required this.auth, required this.matricula, required this.senha});

  final AdminAuthBackend auth;
  final String matricula;
  final String senha;

  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  final _codigo = TextEditingController();
  ({String secret, String otpauthUri})? _inicio;
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
    setState(() => _erro = null);
    try {
      final inicio = await widget.auth.beginMfaEnrollment(matricula: widget.matricula, senha: widget.senha);
      if (mounted) setState(() => _inicio = inicio);
    } on AdminAuthFailure catch (falha) {
      if (mounted) setState(() => _erro = falha.message);
    }
  }

  Future<void> _confirmar() async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await widget.auth.confirmMfaEnrollment(
        matricula: widget.matricula,
        senha: widget.senha,
        code: _codigo.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AdminAuthFailure catch (falha) {
      if (mounted) {
        setState(() {
          _erro = falha.message;
          _ocupado = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inicio = _inicio;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificação em duas etapas')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Leia o QR no aplicativo autenticador (ou digite a chave) e informe o código de 6 dígitos que ele mostrar.'),
              const SizedBox(height: 16),
              if (inicio == null && _erro == null) const Center(child: CircularProgressIndicator()),
              if (inicio != null) ...[
                // Fundo branco com módulos escuros por exigência de leitura: não usa token de tema.
                Center(child: QrImageView(data: inicio.otpauthUri, size: 200, backgroundColor: Colors.white)),
                const SizedBox(height: 12),
                SelectableText(inicio.secret, key: const Key('mfa_secret')),
              ],
              if (_erro != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _erro!,
                    key: const Key('mfa_error'),
                    style: const TextStyle(color: AdminColors.redOnSurface, fontWeight: FontWeight.bold),
                  ),
                ),
              if (inicio == null && _erro != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('mfa_retry_button'),
                    onPressed: _iniciar,
                    child: const Text('Tentar de novo'),
                  ),
                ),
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
        ),
      ),
    );
  }
}
