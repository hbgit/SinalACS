import 'package:sinalacs_acs/core/database/micro_area_cache_store.dart';
import 'package:sinalacs_acs/core/network/backend_client.dart';
import 'package:sinalacs_acs/core/security/database_key_store.dart';
import 'package:sinalacs_acs/core/services/micro_area_directory.dart';

/// Monta o diretório da microárea sobre o backend e a base SQLCipher do aparelho.
///
/// [cacheStore] existe só para um teste inspecionar o que foi gravado; em
/// produção a chamada não passa nada e usa o padrão, respaldado pelo
/// Keystore/Keychain.
MicroAreaDirectory buildMicroAreaDirectory({
  required AcsBackend backend,
  MicroAreaCacheStore? cacheStore,
}) =>
    MicroAreaDirectory(
      fetch: backend.listPatients,
      session: () => backend.session,
      store: cacheStore ?? MicroAreaCacheStore(keyStore: SecureStorageDatabaseKeyStore()),
    );
