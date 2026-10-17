import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/session_token_store.dart';

// `shared_preferences` puxa o Flutter: por isso o diário mora aqui, e
// `backend_client.dart` nunca importa este arquivo (guardado por
// `test/session_store_wiring_test.dart`).

/// Fase do diário da limpeza remota (#81, D7).
///
/// `erasing`: a limpeza começou e pode ter parado no meio — a partida refaz
/// tudo (o apagador é idempotente). `erased`: o aparelho já está limpo e só
/// falta o servidor receber a confirmação.
enum WipePhase { erasing, erased }

/// Uma entrada do diário: o pedido e o id ANTIGO da instalação, que é o que o
/// servidor conhece (o apagador troca o id).
typedef WipeJournalEntry = ({String orderId, String deviceId, WipePhase phase});

/// Diário da limpeza remota (D7). Gravado ANTES de qualquer exclusão e
/// apagado só depois de `confirmWipe` responder. Guarda só o `orderId` e o
/// `deviceId` antigo: nada sensível.
abstract interface class WipeJournal {
  Future<WipeJournalEntry?> read();

  Future<void> write(String orderId, String deviceId, WipePhase phase);

  Future<void> clear();
}

/// Duplo de teste: só em memória.
class MemoryWipeJournal implements WipeJournal {
  WipeJournalEntry? _entry;

  @override
  Future<WipeJournalEntry?> read() async => _entry;

  @override
  Future<void> write(String orderId, String deviceId, WipePhase phase) async =>
      _entry = (orderId: orderId, deviceId: deviceId, phase: phase);

  @override
  Future<void> clear() async => _entry = null;
}

/// O diário de produção, em `shared_preferences` (`acs_remote_wipe_journal`),
/// como JSON `{orderId, deviceId, phase}`. Fica fora do Keystore e do banco
/// de propósito: os dois são justamente o que a limpeza apaga.
class SharedPreferencesWipeJournal implements WipeJournal {
  SharedPreferencesWipeJournal({Future<SharedPreferences> Function()? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance;

  static const key = 'acs_remote_wipe_journal';

  final Future<SharedPreferences> Function() _preferences;

  /// Uma entrada ilegível (ou de formato desconhecido) é tratada como
  /// ausente: sem `orderId` não há o que confirmar.
  @override
  Future<WipeJournalEntry?> read() async {
    final raw = (await _preferences()).getString(key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final orderId = json['orderId'] as String;
      final deviceId = json['deviceId'] as String;
      final phase = WipePhase.values.byName(json['phase'] as String);
      return (orderId: orderId, deviceId: deviceId, phase: phase);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String orderId, String deviceId, WipePhase phase) async {
    final saved = await (await _preferences())
        .setString(key, jsonEncode({'orderId': orderId, 'deviceId': deviceId, 'phase': phase.name}));
    if (!saved) throw StateError('O diário da limpeza remota não foi gravado.');
  }

  @override
  Future<void> clear() async {
    await (await _preferences()).remove(key);
  }
}

/// Apaga tudo o que é do aparelho: banco e chave do SQLCipher, tokens de
/// envio, a sessão local e o id da instalação. Idempotente. Montado pelo app
/// (Task 5) a partir de `VisitStorage.destroyAll`, `UploadTokenStore.clearAll`,
/// `AcsBackend.forgetLocalSession` e `DeviceIdStore.delete`.
typedef DeviceEraser = Future<void> Function();

/// Limpeza remota do aparelho do ACS pedida pelo backoffice (#81).
///
/// Três gatilhos podem chegar juntos — a consulta da partida/retorno/rede
/// ([check]), a recusa do servidor no login, na renovação ou no envio
/// diferido ([apply], via `onDeviceWipeRequired`) e o diário pendente
/// ([resumePending]) — e todos compartilham UMA limpeza (single-flight).
///
/// Ordem: diário em `erasing` → apagar → diário em `erased` → `onWiped` →
/// `confirmDeviceWipe` com o id ANTIGO → apagar o diário. Sem rede na
/// confirmação, o diário fica em `erased` e a confirmação é reenviada no
/// próximo gatilho. INV-03: nada aqui chama `acknowledge` nem `resolve`; os
/// alertas seguem `pending` no servidor.
class RemoteWipeCoordinator {
  RemoteWipeCoordinator({
    required AcsBackend backend,
    required DeviceIdStore deviceIds,
    required WipeJournal journal,
    required DeviceEraser erase,
    void Function()? onWiped,
  })  : _backend = backend,
        _deviceIds = deviceIds,
        _journal = journal,
        _erase = erase,
        _onWiped = onWiped;

  final AcsBackend _backend;
  final DeviceIdStore _deviceIds;
  final WipeJournal _journal;
  final DeviceEraser _erase;
  final void Function()? _onWiped;

  Future<void>? _inFlight;

  /// Pedidos já apagados nesta execução do app. Um gatilho atrasado — a
  /// consulta que saiu com o id antigo e respondeu depois da limpeza — não
  /// apaga de novo o aparelho já limpo (que pode ter um login novo).
  final Set<String> _erasedOrders = <String>{};

  /// Na partida, ANTES de abrir o banco: `erasing` termina a limpeza e
  /// confirma; `erased` só reenvia a confirmação. Sem diário, não faz nada.
  /// Uma falha do apagador sobe (o diário continua em `erasing`, e a próxima
  /// partida tenta de novo); a da confirmação, não.
  Future<void> resumePending() => _single(() async {
        final entry = await _readJournal();
        if (entry == null) return;
        await _run(entry.orderId, entry.deviceId, entry.phase);
      });

  /// Pergunta ao servidor se há limpeza pedida para este aparelho e, se há,
  /// aplica. `true` só quando o aparelho foi limpo. Nunca lança: sem rede (ou
  /// com falha do apagador) devolve `false`.
  Future<bool> check() async {
    final String? orderId;
    try {
      final deviceId = await _deviceIds.readOrCreate();
      orderId = await _backend.pendingDeviceWipe(deviceId);
    } catch (_) {
      return false;
    }
    if (orderId == null) return false;
    try {
      await apply(orderId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Aplica a limpeza do pedido [orderId]. Chamadas concorrentes compartilham
  /// o mesmo `Future`. O id lido aqui, ANTES de apagar, é o que vai na
  /// confirmação (o apagador o troca). Falha do apagador sobe com o diário em
  /// `erasing`.
  Future<void> apply(String orderId) => _single(() async {
        final entry = await _readJournal();
        if (entry != null && entry.orderId == orderId) {
          // Mesmo pedido já no diário (outra partida começou ou confirmou
          // pela metade): continua de onde parou, com o id do diário.
          await _run(orderId, entry.deviceId, entry.phase);
          return;
        }
        if (_erasedOrders.contains(orderId)) return;
        final deviceId = await _deviceIds.readOrCreate();
        await _run(orderId, deviceId, WipePhase.erasing);
      });

  Future<void> _single(Future<void> Function() body) {
    final pending = _inFlight;
    if (pending != null) return pending;
    late final Future<void> flight;
    flight = body().whenComplete(() {
      if (identical(_inFlight, flight)) _inFlight = null;
    });
    return _inFlight = flight;
  }

  Future<void> _run(String orderId, String deviceId, WipePhase phase) async {
    if (phase == WipePhase.erasing) {
      // D7: o diário vem ANTES de qualquer exclusão. Se ele não grava, nada
      // é apagado e o erro sobe: o próximo gatilho tenta de novo.
      await _journal.write(orderId, deviceId, WipePhase.erasing);
      await _erase();
      _erasedOrders.add(orderId);
      try {
        await _journal.write(orderId, deviceId, WipePhase.erased);
      } catch (_) {
        // O aparelho já está limpo. Com o diário ainda em `erasing`, a
        // próxima partida só refaz uma limpeza idempotente.
      }
      _onWiped?.call();
    } else {
      _erasedOrders.add(orderId);
    }
    await _confirm(orderId, deviceId);
  }

  /// Confirmação no servidor. Sem rede, o diário fica em `erased` para o
  /// próximo gatilho; só a resposta do servidor apaga o diário.
  Future<void> _confirm(String orderId, String deviceId) async {
    try {
      await _backend.confirmDeviceWipe(deviceId, orderId);
    } catch (_) {
      return;
    }
    try {
      await _journal.clear();
    } catch (_) {
      // Reenviar uma confirmação é inofensivo: o servidor a trata como no-op.
    }
  }

  Future<WipeJournalEntry?> _readJournal() async {
    try {
      return await _journal.read();
    } catch (_) {
      return null;
    }
  }
}
