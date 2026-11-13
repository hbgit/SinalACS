import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// Aviso educativo canônico (RF21, C-02).
///
/// Copiado **literalmente** de `spec/escopo_projeto.md#aviso-educativo`, sem
/// paráfrase: a regra do escopo exige o texto exato. `test/educational_notice_test.dart`
/// lê o arquivo do escopo e reprova qualquer diferença, inclusive de pontuação.
/// O app do paciente tem uma cópia idêntica (não há pacote compartilhado entre os
/// apps), guardada pelo mesmo teste do lado de lá.
const educationalNoticeLong =
    'O SinalACS é uma ferramenta de educação em saúde, de código aberto, '
    'desenvolvida pelo Grupo de Pesquisa PRISM da Universidade Federal de '
    'Roraima (UFRR), em cooperação com o PET-Saúde: Inovação e Saúde Digital. '
    'O conteúdo e as orientações exibidos têm caráter educativo e não '
    'substituem consulta, diagnóstico ou tratamento por profissionais de '
    'saúde. O SinalACS não é um serviço de emergência: em caso de risco de '
    'vida, ligue 192 (SAMU).';

/// Versão curta do aviso, para telas.
const educationalNoticeShort =
    'Conteúdo educativo. Não substitui atendimento profissional. '
    'Emergência: ligue 192.';

/// Versão do aviso que a confirmação da primeira abertura registra.
///
/// Trocar o texto canônico exige trocar esta versão: quem confirmou o texto
/// antigo vê o novo na próxima abertura, em vez de seguir com uma confirmação
/// de um texto que nunca leu.
const educationalNoticeVersion = '2026-11-01';

/// Guarda se este aparelho já confirmou o aviso da primeira abertura.
abstract interface class EducationalNoticeStore {
  /// O valor já conhecido sem E/S, ou `null` quando é preciso ler.
  bool? get knownAcknowledged;

  /// `true` quando a versão atual do aviso já foi confirmada.
  Future<bool> isAcknowledged();

  /// Registra a confirmação da versão atual.
  Future<void> acknowledge();
}

/// Confirmação em `shared_preferences`: é um dado de interface, não sensível
/// (mesma escolha da preferência de tema e do diário da limpeza remota), e
/// fica fora do banco cifrado e do Keystore: a limpeza remota (#81) não precisa
/// apagá-la, porque ela não diz nada sobre a pessoa nem sobre a microárea.
///
/// Falhar ao ler conta como **não confirmado**: na dúvida, o aviso aparece de
/// novo. Falhar ao gravar não prende a pessoa na tela; o aviso só volta na
/// próxima abertura.
class SharedPreferencesEducationalNoticeStore implements EducationalNoticeStore {
  SharedPreferencesEducationalNoticeStore();

  static const prefsKey = 'aviso_educativo_confirmado';

  bool? _known;

  @override
  bool? get knownAcknowledged => _known;

  @override
  Future<bool> isAcknowledged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _known = prefs.getString(prefsKey) == educationalNoticeVersion;
    } catch (error, stackTrace) {
      developer.log(
        'não foi possível ler a confirmação do aviso educativo',
        name: 'sinalacs.acs.educational_notice',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> acknowledge() async {
    _known = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, educationalNoticeVersion);
    } catch (error, stackTrace) {
      developer.log(
        'não foi possível gravar a confirmação do aviso educativo',
        name: 'sinalacs.acs.educational_notice',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Confirmação só em memória, para testes.
class MemoryEducationalNoticeStore implements EducationalNoticeStore {
  MemoryEducationalNoticeStore({this.acknowledged = false});

  bool acknowledged;
  int acknowledgeCalls = 0;

  @override
  bool? get knownAcknowledged => acknowledged;

  @override
  Future<bool> isAcknowledged() async => acknowledged;

  @override
  Future<void> acknowledge() async {
    acknowledgeCalls++;
    acknowledged = true;
  }
}

/// Loja usada por `SinalAcsApp` quando nenhuma é injetada.
///
/// Em produção é sempre [SharedPreferencesEducationalNoticeStore]. Os testes
/// trocam este padrão em `test/flutter_test_config.dart` e
/// `integration_test/flutter_test_config.dart` por uma loja já confirmada, para
/// que os testes que não tratam do aviso continuem abrindo direto no login; os
/// testes do aviso injetam a loja explicitamente. Código de produção não
/// atribui a esta variável.
EducationalNoticeStore Function() educationalNoticeStoreFactory =
    SharedPreferencesEducationalNoticeStore.new;
