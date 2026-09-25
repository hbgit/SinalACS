/// Atrasos entre tentativas de conectar ao broker.
///
/// Existe separada do widget por dois motivos: o cálculo é testável sem relógio
/// falso nem árvore de widgets, e a escala fica num lugar só. Os valores são os
/// mesmos de `MqttAlertDispatcher` no backend — não há razão para as duas pontas
/// divergirem.
///
/// Só aritmética: nenhum `Timer` mora aqui. Quem agenda é o dono do ciclo de
/// vida, que sabe cancelar.
class ReconnectSchedule {
  /// Curto o bastante para o ACS que abre o app logo depois de recuperar sinal
  /// não esperar de pé olhando a tela.
  static const initial = Duration(seconds: 2);

  /// Teto: numa zona sem cobertura, insistir a cada 2 segundos pelo turno
  /// inteiro gastaria bateria sem chance de sucesso.
  static const maximum = Duration(seconds: 60);

  Duration _current = initial;

  /// O atraso desta tentativa. Dobra para a próxima, até [maximum].
  Duration next() {
    final delay = _current;
    final doubled = delay.inSeconds * 2;
    _current = doubled >= maximum.inSeconds ? maximum : Duration(seconds: doubled);
    return delay;
  }

  /// Volta ao início.
  ///
  /// Chamada quando a conexão dá certo e quando o app retorna do segundo plano:
  /// nesse instante a rede é outra, e herdar o atraso de 60s da tentativa
  /// anterior faria o ACS esperar um minuto com sinal na mão.
  void reset() => _current = initial;
}
