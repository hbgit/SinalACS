import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Hash de localização enviado ao backend no lugar da coordenada.
///
/// **LGPD:** latitude e longitude cruas não saem do dispositivo e não vão para
/// log. O servidor só precisa distinguir e agrupar locais, não sabê-los — por
/// isso `alerts.createRedAlert` recebe `locationHash`, nunca o par de
/// coordenadas.
///
/// O esquema (sha256 sobre a coordenada com 6 casas, truncado em 12) é o mesmo
/// já usado no app do ACS, para que os dois lados produzam o mesmo hash para o
/// mesmo ponto.
String locationHashFrom(double latitude, double longitude) {
  final normalized =
      '${latitude.toStringAsFixed(6)}:${longitude.toStringAsFixed(6)}';
  return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
}

/// Hash usado quando a localização não está disponível.
///
/// Um alerta vermelho sem GPS ainda precisa chegar à equipe — descartá-lo por
/// falta de coordenada violaria "alerta vermelho nunca some em silêncio". O
/// valor é constante e explicitamente reconhecível como ausência de local.
const String unknownLocationHash = 'sem-local-00';
