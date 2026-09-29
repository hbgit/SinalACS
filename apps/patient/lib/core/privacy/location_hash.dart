import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';

import 'location_cell.dart';

/// Hash de localização enviado ao backend no lugar da coordenada.
///
/// **LGPD:** latitude e longitude cruas não saem do dispositivo e não vão para
/// log. O servidor só precisa distinguir e agrupar locais, não sabê-los — por
/// isso `alerts.createRedAlert` recebe `locationHash`, nunca o par de
/// coordenadas.
///
/// O esquema (sha256 sobre a coordenada com 3 casas, truncado em 12) é o
/// mesmo usado no app do ACS — ambos devem mudar juntos se a precisão for
/// revista. Precisão de 3 casas (~111 m) por decisão de produto
/// (docs/superpowers/specs/2026-09-16-decisoes-produto-pos-validacao.md §1.1):
/// aumenta o conjunto de anonimato de qualquer hash sem adicionar dado novo
/// ao payload. Era 6 casas (~11 cm) antes desta decisão.
String locationHashFrom(double latitude, double longitude) {
  final normalized =
      '${latitude.toStringAsFixed(3)}:${longitude.toStringAsFixed(3)}';
  return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
}

/// Hash usado quando a localização não está disponível.
///
/// Um alerta vermelho sem GPS ainda precisa chegar à equipe — descartá-lo por
/// falta de coordenada violaria "alerta vermelho nunca some em silêncio". O
/// valor é constante e explicitamente reconhecível como ausência de local.
const String unknownLocationHash = 'sem-local-00';

/// Motivo pelo qual [GeolocatorLocationReader] não conseguiu ler a posição.
///
/// Existe para a UI poder ser honesta sobre o que aconteceu (permissão
/// negada não é a mesma coisa que GPS desligado), mas a resolução — cair para
/// [unknownLocationHash] e seguir enviando o alerta — é igual para todos os
/// motivos.
enum LocationUnavailableReason { permissionDenied, serviceDisabled, timeout, unknown }

/// Resultado de uma tentativa de leitura de localização no dispositivo.
sealed class LocationReading {
  const LocationReading();
}

/// Leitura bem-sucedida: hash (para idempotência/dedupe) e célula (para o
/// mapa). A coordenada crua morre dentro de
/// [GeolocatorLocationReader.read] e nunca chega a este tipo.
class LocationAvailable extends LocationReading {
  const LocationAvailable(this.hash, this.cell);

  final String hash;
  final String cell;
}

/// Localização não pôde ser lida. O chamador deve tratar isso como estado
/// explícito — nunca substituir silenciosamente por uma coordenada inventada.
class LocationUnavailable extends LocationReading {
  const LocationUnavailable(this.reason);

  final LocationUnavailableReason reason;
}

/// Abstração testável para leitura de localização.
///
/// `geolocator` fala com canal de plataforma (MethodChannel); sem esta
/// costura não haveria como testar os estados de permissão/GPS/timeout em
/// teste hermético (ver `location_hash_test.dart` e
/// `patient_app_mvp_test.dart`) — só em emulador/dispositivo real.
abstract class LocationReader {
  Future<LocationReading> read({Duration timeout = const Duration(seconds: 8)});
}

/// Implementação real usada em produção, sobre o plugin `geolocator`.
///
/// Solicita permissão em fluxo de usuário (nunca em background) e nunca
/// deixa uma falha de qualquer tipo (permissão, serviço, timeout, erro
/// inesperado) escapar como exceção não tratada — tudo vira
/// [LocationUnavailable] para o alerta continuar persistível sem GPS.
class GeolocatorLocationReader implements LocationReader {
  const GeolocatorLocationReader();

  @override
  Future<LocationReading> read({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationUnavailable(
          LocationUnavailableReason.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationUnavailable(
          LocationUnavailableReason.permissionDenied,
        );
      }

      final position = await Geolocator.getCurrentPosition(timeLimit: timeout);
      return LocationAvailable(
        locationHashFrom(position.latitude, position.longitude),
        locationCellFrom(position.latitude, position.longitude),
      );
    } on TimeoutException {
      return const LocationUnavailable(LocationUnavailableReason.timeout);
    } on LocationServiceDisabledException {
      return const LocationUnavailable(
        LocationUnavailableReason.serviceDisabled,
      );
    } catch (_) {
      // Cobre permissão mal configurada no manifest, canal de plataforma
      // ausente (teste hermético) e qualquer outra falha do plugin: em
      // nenhum caso isso deve virar exceção não tratada na tela de alerta.
      return const LocationUnavailable(LocationUnavailableReason.unknown);
    }
  }
}
