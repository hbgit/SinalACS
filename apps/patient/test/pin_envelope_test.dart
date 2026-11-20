import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinalacs_patient/core/security/pin_envelope.dart';

/// O envelope do PIN (C-05, decisão D3 do plano da #136): Argon2id (19 MiB,
/// t=2, p=1) + AES-256-GCM. É o mesmo envelope que a Fase 2 da #136 reutiliza
/// para a chave do banco local — os requisitos dele (PIN de 6+ dígitos e a
/// lista proibida) são os desta issue.
/// Envelope gravado pelo código da #157 (C-05), ANTES da #170 tirar a
/// derivação da thread da UI. PIN e segredo sintéticos. Se m, t, p, o tamanho
/// da saída ou o formato `{v, salt, nonce, ct, mac}` mudarem, a chave derivada
/// muda e este envelope deixa de abrir: é a prova de que os parâmetros do
/// Argon2id ficaram como estavam e de que quem já tem PIN continua entrando.
const _envelopeDaC05 =
    '{"v":1,"salt":"ASt0JqMY-c0vL_HdwFW_1Q==","nonce":"FBH_bPRgAruU9BxB",'
    '"ct":"SmJeTVBpM1OFRauvyq3UG5-5GSaC2QW2sb58QueD","mac":"0VkjnQi6YOSKdX-pWlgB5Q=="}';

void main() {
  test('#170: os parâmetros do Argon2id continuam os da D3', () {
    expect(pinEnvelopeArgon2Memory, 19456, reason: 'm = 19 MiB');
    expect(pinEnvelopeArgon2Iterations, 2, reason: 't = 2');
    expect(pinEnvelopeArgon2Parallelism, 1, reason: 'p = 1');
    expect(pinEnvelopeArgon2HashLength, 32, reason: 'chave AES-256');
  });

  test('#170: a chave só é derivada dentro de Isolate.run, nunca na thread da UI', () {
    // Lê o código-fonte, como `android_backup_manifest_test.dart`: o
    // `flutter test` não tem como medir quadros perdidos, e a medida no
    // aparelho (PROGRESS.md, #170) vale para este desenho. Se alguém voltar
    // a chamar `deriveKey` direto em `encrypt`/`decrypt`, isto falha.
    final src = File('lib/core/security/pin_envelope.dart').readAsStringSync();
    expect(RegExp(r'Isolate\.run\(').allMatches(src), hasLength(1));
    expect(RegExp(r'\.deriveKey\(').allMatches(src), hasLength(1),
        reason: 'uma única derivação, a do isolate');
    final derivacao = src.indexOf('.deriveKey(');
    final funcaoDoIsolate = src.indexOf('Future<List<int>> _deriveKeyBytes(');
    expect(funcaoDoIsolate, greaterThan(-1));
    expect(derivacao, greaterThan(funcaoDoIsolate),
        reason: 'deriveKey só dentro de _deriveKeyBytes, a função do isolate');
    expect(RegExp(r'_deriveInBackground\(pin, salt\)').allMatches(src), hasLength(2),
        reason: 'encrypt e decrypt passam pelo isolate');
  });

  test('#170: envelope gravado antes da mudança continua abrindo', () async {
    final envelope = PinEnvelope();
    expect(
      await envelope.decrypt(pin: '284637', envelopeJson: _envelopeDaC05),
      'segredo-sintetico-da-issue-170',
    );
    await expectLater(
      envelope.decrypt(pin: '284638', envelopeJson: _envelopeDaC05),
      throwsA(isA<WrongPinException>()),
    );
  });

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

  test('o PIN recusado não aparece no toString da exceção', () async {
    final envelope = PinEnvelope();
    // PINs fracos que NÃO são citados nas mensagens da política (as mensagens
    // citam 123456/987654/121212 como exemplo — um teste com esses valores
    // passaria mesmo que o PIN fosse para a exceção).
    for (final fraco in ['654321', '000000', '454545']) {
      await expectLater(
        envelope.encrypt(pin: fraco, plaintext: 'x'),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.toString(), 'toString', isNot(contains(fraco))),
        ),
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
