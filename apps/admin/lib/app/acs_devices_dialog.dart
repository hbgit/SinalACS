import 'package:flutter/material.dart';

import 'package:sinalacs_admin/app/admin_accounts.dart';
import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Aparelhos de um ACS e pedido de limpeza remota (#81).
///
/// Lista cada aparelho com o último acesso e o estado do pedido, e oferece
/// "Limpar remotamente" nos que ainda não têm pedido. O pedido é irreversível
/// (sem cancelamento) e passa por duas etapas antes de chegar ao servidor: o
/// motivo (conjunto fechado) e a confirmação destrutiva
/// ([confirmarDestrutiva]). Cancelar em qualquer uma não chama o servidor.
/// A lista é sempre relida do servidor depois do pedido, nunca remendada.

/// "DD/MM às HH:MM" na hora local.
String dataEHoraLocal(DateTime instante) {
  final l = instante.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(l.day)}/${dois(l.month)} às ${dois(l.hour)}:${dois(l.minute)}';
}

String _horaLocal(DateTime instante) {
  final l = instante.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(l.hour)}:${dois(l.minute)}';
}

/// Consequência mostrada antes de confirmar (D2: o remoto ignora o bloqueio de
/// visitas não enviadas, e o diálogo precisa dizer isso).
const consequenciaDaLimpezaRemota =
    'Limpar este aparelho remotamente? Ele perde o acesso agora e apaga os dados '
    'do SinalACS na próxima vez que se conectar, inclusive as visitas que ainda '
    'não foram enviadas. Isso não pode ser desfeito.';

/// Abre o diálogo dos aparelhos de [acs].
Future<void> mostrarAparelhosDoAcs(
  BuildContext context, {
  required AdminDataSource dataSource,
  required AcsSummary acs,
  VoidCallback? aoVencerSessao,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => AcsDevicesDialog(dataSource: dataSource, acs: acs, aoVencerSessao: aoVencerSessao),
    );

class AcsDevicesDialog extends StatefulWidget {
  const AcsDevicesDialog({super.key, required this.dataSource, required this.acs, this.aoVencerSessao});

  final AdminDataSource dataSource;
  final AcsSummary acs;
  final VoidCallback? aoVencerSessao;

  @override
  State<AcsDevicesDialog> createState() => _AcsDevicesDialogState();
}

class _AcsDevicesDialogState extends State<AcsDevicesDialog> {
  List<AcsDevice>? _aparelhos;
  String? _erro;
  String? _aviso;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  /// Texto de uma falha: só o texto fixo do app ([AdminDataFailure]) chega à tela.
  String _textoDaFalha(Object erro) =>
      erro is AdminDataFailure ? erro.message : 'Não foi possível concluir a ação. Tente novamente.';

  void _venceu() {
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.aoVencerSessao?.call();
  }

  Future<void> _carregar() async {
    try {
      final lista = await widget.dataSource.fetchAcsDevices(widget.acs.id);
      if (!mounted) return;
      setState(() {
        _aparelhos = lista;
        _erro = null;
      });
    } on AdminSessionExpired {
      _venceu();
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = _textoDaFalha(erro));
    }
  }

  Future<void> _limpar(AcsDevice aparelho) async {
    if (_ocupado) return;
    final motivo = await showDialog<DeviceWipeReason>(
      context: context,
      builder: (_) => _EscolhaDoMotivo(aparelho: aparelho),
    );
    if (motivo == null || !mounted) return;
    final confirmado = await confirmarDestrutiva(
      context,
      titulo: 'Limpar ${aparelho.label}?',
      consequencia: consequenciaDaLimpezaRemota,
      rotuloConfirmar: 'Limpar aparelho',
    );
    if (!confirmado || !mounted) return;
    setState(() {
      _ocupado = true;
      _aviso = null;
      _erro = null;
    });
    try {
      final r = await widget.dataSource.orderDeviceWipe(
        acsId: widget.acs.id,
        deviceId: aparelho.deviceId,
        reason: motivo,
      );
      if (!mounted) return;
      setState(() => _aviso = r.alreadyOrdered ? 'Este aparelho já tinha um pedido de limpeza.' : null);
      await _carregar();
    } on AdminSessionExpired {
      _venceu();
    } catch (erro) {
      if (mounted) setState(() => _erro = _textoDaFalha(erro));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aparelhos = _aparelhos;
    return AlertDialog(
      scrollable: true,
      title: Text('Aparelhos de ${widget.acs.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_erro != null)
              Semantics(
                liveRegion: true,
                child: Text(_erro!, key: const Key('aparelhos_erro'), style: const TextStyle(color: AdminColors.redOnSurface)),
              ),
            if (_aviso != null)
              Semantics(liveRegion: true, child: Text(_aviso!, key: const Key('aparelhos_aviso'))),
            if (aparelhos == null && _erro == null)
              const Center(child: CircularProgressIndicator())
            else if (aparelhos != null && aparelhos.isEmpty)
              const Text('Nenhum aparelho com acesso registrado para este ACS.')
            else if (aparelhos != null)
              for (final a in aparelhos)
                _LinhaDoAparelho(aparelho: a, ocupado: _ocupado, aoLimpar: () => _limpar(a)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('fechar_aparelhos'),
          style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(48, 52))),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _LinhaDoAparelho extends StatelessWidget {
  const _LinhaDoAparelho({required this.aparelho, required this.ocupado, required this.aoLimpar});

  final AcsDevice aparelho;
  final bool ocupado;
  final VoidCallback aoLimpar;

  String? get _estado => switch (aparelho.wipeState) {
        null => null,
        DeviceWipeState.pending => aparelho.wipeRequestedAt == null
            ? 'Limpeza pedida'
            : 'Limpeza pedida às ${_horaLocal(aparelho.wipeRequestedAt!)}',
        DeviceWipeState.delivered => 'Pedido entregue ao aparelho',
        DeviceWipeState.confirmed => aparelho.wipeConfirmedAt == null
            ? 'Aparelho limpo'
            : 'Aparelho limpo às ${_horaLocal(aparelho.wipeConfirmedAt!)}',
      };

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    return Padding(
      key: Key('aparelho_${aparelho.deviceId}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(aparelho.label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Último acesso em ${dataEHoraLocal(aparelho.lastSeenAt)}'),
          if (estado != null) Text(estado, key: Key('estado_${aparelho.deviceId}')),
          if (aparelho.wipeState == null) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: Key('wipe_device_${aparelho.deviceId}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
              onPressed: ocupado ? null : aoLimpar,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Limpar remotamente'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Primeira etapa do pedido: o motivo, de um conjunto fechado.
class _EscolhaDoMotivo extends StatefulWidget {
  const _EscolhaDoMotivo({required this.aparelho});

  final AcsDevice aparelho;

  @override
  State<_EscolhaDoMotivo> createState() => _EscolhaDoMotivoState();
}

class _EscolhaDoMotivoState extends State<_EscolhaDoMotivo> {
  DeviceWipeReason? _motivo;

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text('Limpar ${widget.aparelho.label}'),
        content: SizedBox(
          width: 360,
          child: DropdownButtonFormField<DeviceWipeReason>(
            key: const Key('wipe_reason'),
            initialValue: _motivo,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Motivo'),
            hint: const Text('Escolha o motivo'),
            items: [
              for (final m in DeviceWipeReason.values) DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (v) => setState(() => _motivo = v),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('cancelar_motivo'),
            style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size(48, 52))),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('continuar_motivo'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: _motivo == null ? null : () => Navigator.of(context).pop(_motivo),
            child: const Text('Continuar'),
          ),
        ],
      );
}
