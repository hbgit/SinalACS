import 'dart:developer' as developer;

import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/network/auth_session.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

/// Validade do cache da microárea (spec/lgpd_design.md §5.7).
const microAreaCacheMaxAge = Duration(hours: 72);

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

  String? _owner() {
    final s = _session();
    if (s == null || s.microAreaId == null) return null;
    return '${s.userId}|${s.microAreaId}';
  }

  Future<MicroAreaSnapshot> load() async {
    final owner = _owner();
    try {
      final fresh = await _fetch();
      final at = _clock().toUtc();
      if (owner != null) {
        try {
          await _store.write(owner: owner, patients: fresh, at: at);
        } catch (error, stack) {
          // Gravar o cache é conforto; nunca derruba a lista que acabou de chegar.
          developer.log('não foi possível gravar o cache da microárea',
              name: 'sinalacs.acs.micro_area_directory', error: error, stackTrace: stack);
        }
      }
      return MicroAreaSnapshot(patients: fresh, fetchedAt: at, fromCache: false);
    } on BackendFailure catch (falha) {
      if (!falha.isRecoverable || owner == null) rethrow;
      final guardado = await _lerSemFalhar(owner);
      if (guardado == null) rethrow;
      if (_clock().toUtc().difference(guardado.fetchedAt) > maxAge) {
        await _apagarSemFalhar();
        rethrow;
      }
      return MicroAreaSnapshot(patients: guardado.patients, fetchedAt: guardado.fetchedAt, fromCache: true);
    }
  }

  Future<CachedMicroArea?> _lerSemFalhar(String owner) async {
    try {
      return await _store.read(owner: owner);
    } catch (_) {
      return null; // cache ilegível = sem cache; a falha da rede é a que importa
    }
  }

  Future<void> _apagarSemFalhar() async {
    try {
      await _store.clear();
    } catch (_) {}
  }
}
