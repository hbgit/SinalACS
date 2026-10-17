/// Selo das gravações locais atrasadas durante a limpeza remota (#81).
///
/// Uma operação que começa antes da limpeza e só volta da rede depois dela (a
/// lista da microárea, o pull de visitas) gravaria num banco recriado com
/// chave NOVA — nomes e condições crônicas no aparelho que o servidor registra
/// como limpo. [begin] dá uma ficha no começo da operação; [admits] diz, antes
/// de cada acesso ao disco, se ela ainda vale.
///
/// [seal] invalida toda ficha emitida até ali e recusa novas até [unseal] (o
/// próximo login). Uma ficha emitida com o selo fechado nunca passa a valer:
/// [unseal] não ressuscita o que começou durante a limpeza.
class LocalWriteSeal {
  int _epoch = 0;
  bool _sealed = false;

  bool get isSealed => _sealed;

  /// `null` com o selo fechado: a operação não grava nada.
  int? begin() => _sealed ? null : _epoch;

  bool admits(int? ticket) => ticket != null && !_sealed && ticket == _epoch;

  void seal() {
    _sealed = true;
    _epoch++;
  }

  void unseal() => _sealed = false;
}
