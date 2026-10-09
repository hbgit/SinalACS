import 'dart:math';

/// Senha inicial do ACS recém-cadastrado (issue #43): sorteada pelo servidor e
/// mostrada ao operador **uma única vez**.
///
/// **Por que não vem do operador.** Uma senha digitada pelo coordenador é uma
/// senha escolhida por quem tem pressa, e ela vira a credencial do RF07: o
/// login institucional não tem como exigir força de uma senha que já nasceu
/// fraca, e a política de bloqueio por tentativas (achado F6) protege contra
/// força bruta, não contra `acs1234`. O caminho escolhido é o que o repositório
/// já usa para credencial entregue fora de banda — o código de ativação do
/// staff (issue #48) e as senhas semeadas de desenvolvimento: o servidor
/// **sorteia**, mostra uma vez e não guarda, porque só o hash Argon2id vai para
/// `user_credentials`. Quem cadastra repassa a senha ao ACS e não a vê de novo;
/// perdê-la significa redefinir, nunca recuperar.
///
/// **Formato.** 16 caracteres de um alfabeto de 31 símbolos — 31^16 ≈ 2^79,3,
/// os "~80 bits" da issue —, em quatro grupos de quatro, como o
/// `StaffActivationCode`. O alfabeto é `ABC…Z` e `2…9` **sem** `0`/`O` e
/// `1`/`I`/`L`: são os pares que se confundem quando a senha é lida em voz
/// alta, copiada de um papel ou digitada num teclado de celular, e uma senha
/// inicial que chega trocada ao ACS vira uma tentativa falha a mais (ou um
/// bloqueio de conta) que ninguém sabe explicar. Os grupos fazem o mesmo
/// trabalho: quem digita confere bloco a bloco e um erro fica visível no grupo
/// errado, em vez de no meio de 16 caracteres indistinguíveis.
class AcsInitialPassword {
  const AcsInitialPassword._();

  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _length = 16;
  static const _groupSize = 4;

  /// Sorteia uma senha nova. [random] existe para os testes; sem ele o sorteio
  /// é [Random.secure]. Um `Random()` comum **não** serve em produção: ele é
  /// determinístico a partir da semente, e quem adivinha a semente recebe a
  /// credencial de todo ACS cadastrado naquele dia.
  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    final caracteres = List.generate(
      _length,
      (_) => _alphabet[r.nextInt(_alphabet.length)],
    );
    return [
      for (var i = 0; i < _length; i += _groupSize)
        caracteres.sublist(i, i + _groupSize).join(),
    ].join('-');
  }
}
