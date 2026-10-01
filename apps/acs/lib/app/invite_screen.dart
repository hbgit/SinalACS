import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sinalacs_acs/app/acs_theme.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/network/backend_scope.dart';
import 'package:sinalacs_client/sinalacs_client.dart'
    show EnrollmentTokenResult, MicroAreaPatient;

/// Convite de onboarding (RF02): o ACS escolhe um paciente da própria
/// microárea e mostra o QR Code que o app do paciente lê.
///
/// O token em claro existe só na memória desta tela — nunca vai para disco,
/// log ou fila offline; o servidor guarda só o hash (`enrollment_tokens`).
/// Sai da tela, some o token. A lista mostra nome e condições crônicas, a
/// mesma minimização do seletor da visita de rotina (spec/lgpd_design.md:364).
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

/// Validade de um convite, igual à do servidor.
const _inviteLifetime = Duration(minutes: 15);

class _InviteScreenState extends State<InviteScreen> {
  List<MicroAreaPatient>? _patients;
  MicroAreaPatient? _selected;
  EnrollmentTokenResult? _invite;
  String? _error;
  bool _loading = true;
  bool _generating = false;
  Timer? _expiryTimer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    // `BackendScope.of` depende de herança: não pode rodar dentro do
    // `initState` em si.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _clearExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expired = false;
  }

  /// Agenda o aviso de que o convite deixou de valer.
  ///
  /// `expiresAt` vem do relógio do servidor; comparar com o do aparelho falha
  /// nos dois sentidos. Aparelho adiantado: o convite chegaria "já vencido" e a
  /// tela nunca mostraria um QR que o servidor aceitaria. Aparelho atrasado: o
  /// QR ficaria de pé depois de morto. Por isso a espera é limitada a
  /// [_inviteLifetime] (o mesmo TTL do servidor, `_tokenLifetime` em
  /// `onboarding_service.dart`), contado do recebimento, e um `expiresAt` que já
  /// passou para o aparelho usa o prazo inteiro em vez de valer como vencido.
  /// O servidor segue sendo quem recusa um convite expirado.
  void _watchExpiry(DateTime expiresAt) {
    _clearExpiry();
    var remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero || remaining > _inviteLifetime) {
      remaining = _inviteLifetime;
    }
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() => _expired = true);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await BackendScope.of(context).listPatients();
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _loading = false;
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  void _select(MicroAreaPatient patient) {
    setState(() {
      // O convite exibido pertence ao paciente anterior: nunca deixá-lo na
      // tela sob o nome de outra pessoa.
      if (_selected?.patientId != patient.patientId) {
        _invite = null;
        _clearExpiry();
      }
      _selected = patient;
      _error = null;
    });
  }

  Future<void> _generate() async {
    final patient = _selected;
    if (patient == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final invite = await BackendScope.of(
        context,
      ).generateInvite(patientId: patient.patientId);
      if (!mounted) return;
      setState(() {
        _generating = false;
        // A resposta pode chegar depois de o ACS trocar de paciente (rede
        // lenta): o token é de quem foi pedido, nunca do selecionado agora.
        if (_selected?.patientId == patient.patientId) {
          _invite = invite;
          _watchExpiry(invite.expiresAt);
        }
      });
    } on BackendFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        if (_selected?.patientId != patient.patientId) return;
        _invite = null;
        _clearExpiry();
        _error = failure.message;
      });
    }
  }

  String _hhmm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final patients = _patients;
    final invite = _invite;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Convidar paciente',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Escolha o paciente e mostre o QR Code para ele ler no app SinalACS '
          'Paciente. O convite vale por 15 minutos e só pode ser usado uma vez.',
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (patients == null)
          OutlinedButton.icon(
            key: const Key('invite_retry'),
            onPressed: _load,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          )
        else if (patients.isEmpty)
          const Text(
            'Nenhum paciente cadastrado na sua microárea.',
            key: Key('invite_no_patients'),
          )
        else ...[
          for (final patient in patients)
            ListTile(
              key: Key('invite_patient_${patient.patientId}'),
              selected: _selected?.patientId == patient.patientId,
              title: Text(patient.name),
              subtitle: patient.chronicConditions.isEmpty
                  ? null
                  : Text(patient.chronicConditions.join(', ')),
              trailing: _selected?.patientId == patient.patientId
                  ? Icon(
                      Icons.check_circle,
                      color: context.acsRisk.accentOnSurface,
                    )
                  : null,
              onTap: () => _select(patient),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('generate_invite_button'),
            onPressed: _selected == null || _generating ? null : _generate,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            icon: const Icon(Icons.qr_code_2),
            label: Text(
              invite == null ? 'Gerar convite' : 'Gerar novo convite',
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const Key('invite_error'),
                style: TextStyle(
                  color: context.acsRisk.redOnSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (invite != null && _expired)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Semantics(
              liveRegion: true,
              child: const Text(
                'O convite expirou. Gere um novo.',
                key: Key('invite_expired'),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        if (invite != null && _selected != null && !_expired) ...[
          const SizedBox(height: 24),
          Center(
            child: Container(
              key: const Key('invite_qr'),
              // Fundo branco com margem: leitores de QR precisam da "zona
              // silenciosa" clara em volta, e o tema do app é escuro.
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: invite.token,
                size: 240,
                backgroundColor: Colors.white,
                semanticsLabel: 'QR Code do convite de ${_selected!.name}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Convite de ${_selected!.name} · Válido até ${_hhmm(invite.expiresAt.toLocal())} · uso único',
            key: const Key('invite_expires_at'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Se a câmera do paciente não funcionar, ele pode digitar este código:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          SelectableText(
            invite.token,
            key: const Key('invite_token_text'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ],
    );
  }
}
