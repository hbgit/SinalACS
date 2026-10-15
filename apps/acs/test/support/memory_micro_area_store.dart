import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_client/sinalacs_client.dart' show MicroAreaPatient;

/// Store em memória: o que se testa aqui é a REGRA (quando serve cache), não o SQLite.
class MemoryMicroAreaStore implements MicroAreaCacheStore {
  @override
  String get databaseName => 'em_memoria';
  @override
  bool get allowUnencryptedForTesting => true;

  String? owner;
  List<MicroAreaPatient>? patients;
  DateTime? at;
  int clears = 0;
  bool falhaAoGravar = false;

  @override
  Future<CachedMicroArea?> read({required String owner}) async {
    if (this.owner == null) return null;
    if (this.owner != owner) {
      await clear();
      return null;
    }
    return CachedMicroArea(patients: patients!, fetchedAt: at!);
  }

  @override
  Future<void> write({required String owner, required List<MicroAreaPatient> patients, required DateTime at}) async {
    if (falhaAoGravar) throw StateError('disco cheio');
    this.owner = owner;
    this.patients = patients;
    this.at = at;
  }

  @override
  Future<void> clear() async {
    clears++;
    owner = null;
    patients = null;
    at = null;
  }
}
