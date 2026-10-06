import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinalacs_admin/app/admin_header.dart';
import 'package:sinalacs_admin/app/admin_layout.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/app/app.dart';
import 'package:sinalacs_admin/app/mfa_enrollment_screen.dart';
import 'package:sinalacs_admin/core/auth/admin_auth_backend.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Login institucional do backoffice (staff: coordenador e administrador).
///
/// O painel só abre com a [AdminSession] que `auth.login` devolve: não há
/// atalho de desenvolvimento. Com MFA obrigatória no staff, o servidor pede o
/// código (`AdminMfaCodeRequired`) ou a ativação (`AdminMfaEnrollmentRequired`).
class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.auth, required this.dataSource, this.aviso, super.key});

  final AdminAuthBackend auth;
  final AdminDataSource dataSource;

  /// Mensagem informativa inicial (ex.: sessão encerrada).
  final String? aviso;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _matricula = TextEditingController();
  final _senha = TextEditingController();
  final _totp = TextEditingController();
  bool _pedeCodigo = false;
  bool _ocupado = false;
  String? _erro;
  late String? _aviso = widget.aviso;

  @override
  void dispose() {
    _matricula.dispose();
    _senha.dispose();
    _totp.dispose();
    super.dispose();
  }

  /// O código pertence à sessão que o pediu: mudar matrícula ou senha o descarta.
  void _credencialMudou(String _) {
    if (!_pedeCodigo) return;
    setState(() => _pedeCodigo = false);
    _totp.clear();
  }

  Future<void> _entrar() async {
    if (_ocupado) return;
    final matricula = _matricula.text.trim();
    // A senha não passa por `trim`: espaço faz parte da credencial.
    final senha = _senha.text;
    if (matricula.isEmpty || senha.isEmpty) {
      setState(() {
        _erro = 'Informe matrícula e senha.';
        _aviso = null;
      });
      return;
    }
    setState(() {
      _ocupado = true;
      _erro = null;
      _aviso = null;
    });
    try {
      final session = await widget.auth.login(
        matricula: matricula,
        senha: senha,
        totpCode: _pedeCodigo ? _totp.text.trim() : null,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AdminHomeShell(dataSource: widget.dataSource, session: session, auth: widget.auth),
        ),
      );
    } on AdminMfaCodeRequired {
      if (!mounted) return;
      setState(() {
        _pedeCodigo = true;
        _ocupado = false;
      });
    } on AdminMfaEnrollmentRequired {
      if (!mounted) return;
      setState(() => _ocupado = false);
      final ativou = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => MfaEnrollmentScreen(auth: widget.auth, matricula: matricula, senha: senha),
        ),
      );
      if (ativou == true && mounted) {
        setState(() {
          _pedeCodigo = true;
          _aviso = 'Verificação ativada. Entre com o código do aplicativo.';
        });
      }
    } on AdminAuthFailure catch (falha) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _erro = falha.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AdminHeader('Backoffice SinalACS', 'Acesso administrativo', height: adminHeaderHeight(context)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const CircleAvatar(radius: 32, child: Text('ADM')),
                        const SizedBox(height: 16),
                        const Text('SinalACS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Backoffice administrativo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        TextField(
                          key: const Key('matricula_field'),
                          controller: _matricula,
                          autofillHints: const [AutofillHints.username],
                          onChanged: _credencialMudou,
                          decoration: const InputDecoration(labelText: 'Matrícula / CNS'),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('senha_field'),
                          controller: _senha,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          onChanged: _credencialMudou,
                          decoration: const InputDecoration(labelText: 'Senha de acesso'),
                        ),
                        if (_aviso != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(_aviso!, key: const Key('login_aviso'), textAlign: TextAlign.center),
                            ),
                          ),
                        if (_pedeCodigo) ...[
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('totp_field'),
                            controller: _totp,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Código do autenticador (6 dígitos)'),
                            onSubmitted: (_) => _entrar(),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Semantics(
                          label: 'Entrar no backoffice administrativo',
                          button: true,
                          container: true,
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('login_button'),
                              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                              onPressed: _ocupado ? null : _entrar,
                              child: const Text('Entrar'),
                            ),
                          ),
                        ),
                        if (_erro != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _erro!,
                                key: const Key('login_error'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AdminColors.redOnSurface, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
