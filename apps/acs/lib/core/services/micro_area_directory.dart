import 'dart:async';
import 'dart:developer' as developer;

import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/services/local_write_seal.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

/// Validade do cache da microárea (spec/lgpd_design.md §5.11).
const microAreaCacheMaxAge = Duration(hours: 72);

/// Teto da espera, em [MicroAreaDirectory.seal], por uma gravação do cache já
/// em andamento: é E/S local, não rede.
const microAreaCacheSealWait = Duration(seconds: 5);

class MicroAreaSnapshot {
  const MicroAreaSnapshot({required this.patients, required this.fetchedAt, required this.fromCache});

  final List<MicroAreaPatient> patients;
  final DateTime fetchedAt;

  /// `true` quando a lista veio do aparelho porque a central não respondeu.
  final bool fromCache;
}

/// Lista da microárea com cache no aparelho (RF08).
///
/// Regra única, em um lugar só: o cache entra **apenas** no lugar de uma falha
/// recuperável (`isRecoverable`) e **apenas** para o mesmo `userId|microAreaId`
/// e dentro da validade. Recusa do servidor (`isRecoverable: false`) sobe como
/// veio — um território negado não pode ser contornado por um cache antigo.
class MicroAreaDirectory {
  MicroAreaDirectory({
    required Future<List<MicroAreaPatient>> Function() fetch,
    required AuthSession? Function() session,
    required MicroAreaCacheStore store,
    DateTime Function()? clock,
    this.maxAge = microAreaCacheMaxAge,
  })  : _fetch = fetch,
        _session = session,
        _store = store,
        _clock = clock ?? DateTime.now;

  final Future<List<MicroAreaPatient>> Function() _fetch;
  final AuthSession? Function() _session;
  final MicroAreaCacheStore _store;
  final DateTime Function() _clock;
  final Duration maxAge;

  final LocalWriteSeal _seal = LocalWriteSeal();

  /// Gravações e leituras do cache em andamento (as que já passaram pelo selo).
  final Set<Future<void>> _inFlight = <Future<void>>{};

  /// Limpeza remota (#81): nenhuma carga em andamento ou futura toca no cache
  /// — nem grava, nem lê, nem apaga, porque qualquer acesso reabriria o banco
  /// e criaria uma chave nova depois do apagador — até [unseal]. Espera, com
  /// teto, o acesso que já tinha começado, para o apagador não correr com ele.
  Future<void> seal() async {
    _seal.seal();
    if (_inFlight.isEmpty) return;
    try {
      await Future.wait(_inFlight.toList()).timeout(microAreaCacheSealWait);
    } catch (_) {}
  }

  /// O próximo login depois da limpeza: o cache volta a valer para as cargas
  /// que começarem daqui em diante.
  void unseal() => _seal.unseal();

  /// Roda [op] sobre o cache só se a ficha ainda vale, e a registra como em
  /// andamento para [seal] esperar. `false`: o cache foi selado.
  Future<bool> _acessarCache(int? ticket, Future<void> Function() op) async {
    if (!_seal.admits(ticket)) return false;
    final running = op();
    _inFlight.add(running);
    try {
      await running;
    } finally {
      _inFlight.remove(running);
    }
    return true;
  }

  String? _owner() {
    final s = _session();
    if (s == null || s.microAreaId == null) return null;
    return '${s.userId}|${s.microAreaId}';
  }

  Future<MicroAreaSnapshot> load() async {
    final ticket = _seal.begin();
    final owner = _owner();
    try {
      final fresh = await _fetch();
      final at = _clock().toUtc();
      if (owner != null) {
        try {
          // A resposta pode chegar depois da limpeza remota: aí não grava.
          await _acessarCache(ticket, () => _store.write(owner: owner, patients: fresh, at: at));
        } catch (error, stack) {
          // Gravar o cache é conforto; nunca derruba a lista que acabou de chegar.
          developer.log('não foi possível gravar o cache da microárea',
              name: 'sinalacs.acs.micro_area_directory', error: error, stackTrace: stack);
        }
      }
      return MicroAreaSnapshot(patients: fresh, fetchedAt: at, fromCache: false);
    } on BackendFailure catch (falha) {
      if (!falha.isRecoverable || owner == null) rethrow;
      final guardado = await _lerSemFalhar(ticket, owner);
      if (guardado == null) rethrow;
      if (_clock().toUtc().difference(guardado.fetchedAt) > maxAge) {
        await _apagarSemFalhar(ticket);
        rethrow;
      }
      return MicroAreaSnapshot(patients: guardado.patients, fetchedAt: guardado.fetchedAt, fromCache: true);
    }
  }

  Future<CachedMicroArea?> _lerSemFalhar(int? ticket, String owner) async {
    CachedMicroArea? lido;
    try {
      await _acessarCache(ticket, () async => lido = await _store.read(owner: owner));
    } catch (_) {
      return null; // cache ilegível = sem cache; a falha da rede é a que importa
    }
    return lido;
  }

  Future<void> _apagarSemFalhar(int? ticket) async {
    try {
      await _acessarCache(ticket, _store.clear);
    } catch (_) {}
  }
}
