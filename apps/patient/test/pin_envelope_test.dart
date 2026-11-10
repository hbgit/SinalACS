import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/security/pin_envelope.dart';

/// O envelope do PIN (C-05, decisão D3 do plano da #136): Argon2id (19 MiB,
/// t=2, p=1) + AES-256-GCM. É o mesmo envelope que a Fase 2 da #136 reutiliza
/// para a chave do banco local — os requisitos dele (PIN de 6+ dígitos e a
/// lista proibida) são os desta issue.
void main() {
  test('fecha e abre com o mesmo PIN', () async {
    final envelope = PinEnvelope();
    final sealed = await envelope.encrypt(pin: '284637', plaintext: 'segredo');
    final aberto = await envelope.decrypt(pin: '284637', envelopeJson: sealed);
    expect(aberto, 'segredo');
  });

  test('PIN errado é WrongPinException, o certo abre', () async {
    final envelope = PinEnvelope();
    final sealed = await envelope.encrypt(pin: '284637', plaintext: 'segredo');

    await expectLater(
      envelope.decrypt(pin: '999999', envelopeJson: sealed),
      throwsA(isA<WrongPinException>()),
    );
    expect(
      await envelope.decrypt(pin: '284637', envelopeJson: sealed),
      'segredo',
    );
  });

  test('salt e nonce são sorteados por envelope: nada se repete', () async {
    final envelope = PinEnvelope();
    final a = jsonDecode(await envelope.encrypt(pin: '284637', plaintext: 'x'))
        as Map<String, dynamic>;
    final b = jsonDecode(await envelope.encrypt(pin: '284637', plaintext: 'x'))
        as Map<String, dynamic>;
    expect(a['salt'], isNot(b['salt']));
    expect(a['nonce'], isNot(b['nonce']));
  });

  test('o envelope não contém o PIN nem o segredo', () async {
    final envelope = PinEnvelope();
    final sealed = await envelope.encrypt(pin: '284637', plaintext: 'segredo');
    expect(sealed.contains('284637'), isFalse);
    expect(sealed.contains('segredo'), isFalse);
  });

  test('recusa PIN fora da política (defesa em profundidade da tela)', () async {
    final envelope = PinEnvelope();
    for (final fraco in ['12345', '000000', '123456', '987654', '121212']) {
      await expectLater(
        envelope.encrypt(pin: fraco, plaintext: 'x'),
        throwsArgumentError,
      );
    }
  });

  test('envelope corrompido é WrongPinException, como PIN errado', () async {
    final envelope = PinEnvelope();
    final sealed = await envelope.encrypt(pin: '284637', plaintext: 'segredo');

    // Estrutura inválida e texto cifrado adulterado produzem a MESMA recusa:
    // o tempo da falha não pode distinguir "errou o PIN" de "corrompeu".
    await expectLater(
      envelope.decrypt(pin: '284637', envelopeJson: 'não-é-json'),
      throwsA(isA<WrongPinException>()),
    );
    final adulterado = (jsonDecode(sealed) as Map<String, dynamic>)..['ct'] = 'AAAA';
    await expectLater(
      envelope.decrypt(pin: '284637', envelopeJson: jsonEncode(adulterado)),
      throwsA(isA<WrongPinException>()),
    );
  });

  test('versão desconhecida do envelope é recusada', () async {
    final envelope = PinEnvelope();
    final sealed = await envelope.encrypt(pin: '284637', plaintext: 'segredo');
    final velho = (jsonDecode(sealed) as Map<String, dynamic>)..['v'] = 0;
    await expectLater(
      envelope.decrypt(pin: '284637', envelopeJson: jsonEncode(velho)),
      throwsA(isA<WrongPinException>()),
    );
  });
}
