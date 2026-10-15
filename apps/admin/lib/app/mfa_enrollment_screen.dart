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
  const MfaEnrollmentScreen({
    super.key,
    required this.auth,
    required this.matricula,
    required this.senha,
  });

  final AdminAuthBackend auth;
  final String matricula;
  final String senha;

  @override
  State<MfaEnrollmentScreen> createState() => _MfaEnrollmentScreenState();
}

class _MfaEnrollmentScreenState extends State<MfaEnrollmentScreen> {
  final _codigo = TextEditingController();
  final _codigoAtivacao = TextEditingController();
  String _ativacaoEnviada = '';
  ({String secret, String otpauthUri})? _inicio;
  String? _erro;
  bool _ocupado = false;

  @override
  void dispose() {
    _codigo.dispose();
    _codigoAtivacao.dispose();
    super.dispose();
  }

  /// Etapa 1 (#48): o segredo só é pedido ao servidor depois do código de
  /// ativação de uso único, que o servidor confere. Sem o código nem se chama.
  Future<void> _iniciar() async {
    final ativacao = _codigoAtivacao.text.trim();
    if (ativacao.isEmpty) {
      setState(() => _erro = 'Informe o código de ativação.');
      return;
    }
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      final inicio = await widget.auth.beginMfaEnrollment(
        matricula: widget.matricula,
        senha: widget.senha,
        activationCode: ativacao,
      );
      if (mounted) {
        setState(() {
          _inicio = inicio;
          _ativacaoEnviada = ativacao;
          _ocupado = false;
        });
      }
    } on AdminAuthFailure catch (falha) {
      if (mounted) {
        setState(() {
          _erro = falha.message;
          _ocupado = false;
        });
      }
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
        activationCode: _ativacaoEnviada,
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
              if (inicio == null) ...[
                const Text(
                  'Informe o código de ativação que a coordenação entregou a você. Ele vale uma única vez.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('activation_code_field'),
                  controller: _codigoAtivacao,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Código de ativação',
                  ),
                  onSubmitted: (_) => _iniciar(),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _erro!,
                      key: const Key('activation_error'),
                      style: const TextStyle(
                        color: AdminColors.redOnSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('activation_continue'),
                  onPressed: _ocupado ? null : _iniciar,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                  child: const Text('Continuar'),
                ),
              ] else ...[
                const Text(
                  'Leia o QR no aplicativo autenticador (ou digite a chave) e informe o código de 6 dígitos que ele mostrar.',
                ),
                const SizedBox(height: 16),
                // Fundo branco com módulos escuros por exigência de leitura: não usa token de tema.
                Center(
                  child: QrImageView(
                    data: inicio.otpauthUri,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(inicio.secret, key: const Key('mfa_secret')),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _erro!,
                      key: const Key('mfa_error'),
                      style: const TextStyle(
                        color: AdminColors.redOnSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const Key('mfa_code_field'),
                  controller: _codigo,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Código de 6 dígitos',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('mfa_confirm_button'),
                  onPressed: _ocupado ? null : _confirmar,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                  child: const Text('Ativar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
