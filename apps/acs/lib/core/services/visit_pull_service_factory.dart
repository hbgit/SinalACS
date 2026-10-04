import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sinalacs_acs/core/database/sqlcipher_visit_store.dart';
import 'package:sinalacs_acs/core/database/sync_cursor_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/offline_visit_queue.dart';
import 'package:sinalacs_acs/core/services/visit_pull_service.dart';

/// Monta o serviço de pull central→dispositivo (RF15, decisão §5) como ele
/// roda em produção.
///
/// [localVisits] deve ser o MESMO `VisitStore` que respalda a
/// `OfflineVisitQueue` do app: é o que `VisitPullService` usa para nunca
/// reintroduzir localmente uma visita que já está na fila offline (ver a
/// documentação da própria classe). Passar um store diferente perde essa
/// garantia sem lançar nenhum erro visível.
///
/// [cursorOwner] é o dono do cursor (`visits_pull|<dono>`): o cursor de um ACS
/// nunca vale para outro.
///
/// [cursorDatabase] é o [VisitDatabase] da fila: o cursor é gravado nele
/// (`SyncCursorStore.on`), uma só conexão para o arquivo. É o que o app passa.
///
/// [cursorStore] existe só para o teste poder inspecionar o cursor gravado.
/// Sem nenhum dos dois, abre um banco próprio respaldado pelo Keystore/Keychain
/// do aparelho.
VisitPullService buildVisitPullService({
  required AcsBackend backend,
  required VisitStore localVisits,
  required String cursorOwner,
  VisitDatabase? cursorDatabase,
  SyncCursorStore? cursorStore,
  @visibleForTesting DatabaseKeyStore? keyStore,
  @visibleForTesting String databaseName = 'sinalacs_acs.db',
  @visibleForTesting bool allowUnencryptedForTesting = false,
}) {
  final cursor = cursorStore ??
      (cursorDatabase != null
          ? SyncCursorStore.on(cursorDatabase, owner: cursorOwner)
          : SyncCursorStore(
              keyStore: keyStore ?? SecureStorageDatabaseKeyStore(),
              owner: cursorOwner,
              databaseName: databaseName,
              allowUnencryptedForTesting: allowUnencryptedForTesting,
            ));
  return VisitPullService(backend: backend, cursorStore: cursor, localVisits: localVisits);
}
