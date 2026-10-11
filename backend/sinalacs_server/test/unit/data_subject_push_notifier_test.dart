import 'package:sinalacs_server/src/generated/protocol.dart';
import 'package:sinalacs_server/src/infrastructure/push/data_subject_push_notifier.dart';
import 'package:sinalacs_server/src/infrastructure/push/gorush_client.dart';
import 'package:test/test.dart';

/// Aviso push ao titular (#42): só com consentimento `segmentedPush` e token,
/// payload genérico, falha engolida. Dados sintéticos.
class _Alvos implements DataSubjectPushTargets {
  List<PushTarget> alvos = const [PushTarget(token: 'tok-a', platform: 'android')];
  final consultas = <String>[];

  @override
  Future<List<PushTarget>> consentedTargetsOf(String userId) async {
    consultas.add(userId);
    return alvos;
  }
}

class _Sender implements PushSender {
  final enviados = <(PushMessage, List<PushTarget>)>[];
  Object? lanca;

  @override
  Future<PushSendReport> send(PushMessage message, List<PushTarget> targets) async {
    if (lanca != null) throw lanca!;
    enviados.add((message, targets));
    return const PushSendReport(accepted: 1, invalidTokens: []);
  }
}

void main() {
  late _Alvos alvos;
  late _Sender sender;
  late GorushDataSubjectNotifier notificador;

  setUp(() {
    alvos = _Alvos();
    sender = _Sender();
    notificador = GorushDataSubjectNotifier(targets: alvos, sender: sender);
  });

  test('consentimento e token: envia uma vez, com título genérico e só a tela', () async {
    await notificador.decided('u-1', DataSubjectRequestStatus.completed);
    expect(sender.enviados, hasLength(1));
    final (msg, destinos) = sender.enviados.single;
    expect(destinos.single.token, 'tok-a');
    expect(msg.data, {'screen': 'my_data'});
    expect(msg.title, isNotEmpty);
    expect(msg.body, isNotEmpty);
  });

  test('o texto do aviso não carrega nota nem tipo do pedido', () async {
    await notificador.decided('u-1', DataSubjectRequestStatus.rejected);
    final msg = sender.enviados.single.$1;
    final texto = '${msg.title} ${msg.body} ${msg.data}'.toLowerCase();
    for (final proibido in ['exclus', 'correç', 'corrig', 'motivo', 'nota']) {
      expect(texto.contains(proibido), isFalse, reason: proibido);
    }
  });

  test('sem consentimento ou sem token (lista vazia): não envia', () async {
    alvos.alvos = const [];
    await notificador.decided('u-1', DataSubjectRequestStatus.completed);
    expect(sender.enviados, isEmpty);
  });

  test('status que não é decisão final não envia', () async {
    await notificador.decided('u-1', DataSubjectRequestStatus.inReview);
    expect(sender.enviados, isEmpty);
    expect(alvos.consultas, isEmpty);
  });

  test('falha do relé é engolida', () async {
    sender.lanca = const PushGatewayException('fora do ar');
    await notificador.decided('u-1', DataSubjectRequestStatus.completed);
    alvos.consultas.clear();
    sender.lanca = StateError('qualquer');
    await notificador.decided('u-1', DataSubjectRequestStatus.completed);
  });

  test('sem remetente configurado: no-op', () async {
    final sem = GorushDataSubjectNotifier(targets: alvos, sender: null);
    await sem.decided('u-1', DataSubjectRequestStatus.completed);
    expect(alvos.consultas, isEmpty);
  });
}
