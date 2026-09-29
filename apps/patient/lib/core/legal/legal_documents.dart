/// Termo de Uso e Política de Privacidade do app do paciente (LGPD-RF18,
/// LGPD-RF19 e LGPD-RF10 de `spec/lgpd_design.md`).
///
/// Conteúdo constante, no próprio app, de propósito: o documento precisa
/// abrir antes do cadastro (a pessoa lê antes de aceitar) e sem rede. A versão
/// é a mesma que o backend grava em `consent_logs.version`
/// (`consentPolicyVersion`), e `test/legal_documents_test.dart` falha se as
/// duas divergirem.
///
/// Trocar o texto exige versão nova: acrescente uma [LegalVersion] ao
/// histórico, mude [legalDocumentsVersion] **e** `consentPolicyVersion` no
/// backend. O texto de 2026.1 ainda precisa de revisão jurídica e dos dados
/// reais do controlador antes de produção (ver PROGRESS.md).
library;

const String legalDocumentsVersion = '2026.1';

/// Um passo do resumo visual (versão resumida do documento).
class LegalSummaryStep {
  const LegalSummaryStep({required this.title, required this.text});

  final String title;
  final String text;
}

/// Uma seção da versão completa.
class LegalSection {
  const LegalSection({required this.title, required this.body});

  final String title;
  final String body;
}

/// Uma entrada do histórico de versões (controle de versões consultável,
/// LGPD-RF18).
class LegalVersion {
  const LegalVersion({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;

  /// Data de vigência, já no formato de exibição (`dd/mm/aaaa`).
  final String date;
  final String changes;
}

class LegalDocument {
  const LegalDocument({
    required this.id,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.summary,
    required this.sections,
    required this.history,
  });

  final String id;
  final String title;
  final String version;
  final String effectiveDate;
  final List<LegalSummaryStep> summary;
  final List<LegalSection> sections;
  final List<LegalVersion> history;
}

const _history2026_1 = [
  LegalVersion(
    version: '2026.1',
    date: '29/09/2026',
    changes: 'Primeira versão publicada no aplicativo.',
  ),
];

/// Política de Privacidade. O [LegalDocument.summary] é o resumo visual do
/// fluxo de dados pedido pelo LGPD-RF10: de onde o dado sai, por onde passa e
/// quem o vê, na ordem em que acontece.
const privacyPolicy = LegalDocument(
  id: 'privacy',
  title: 'Política de Privacidade',
  version: legalDocumentsVersion,
  effectiveDate: '29/09/2026',
  summary: [
    LegalSummaryStep(
      title: 'Você informa',
      text:
          'Seu cadastro vem da sua UBS. No app, você responde a triagem, '
          'pode enviar um alerta de urgência e escolhe seus consentimentos.',
    ),
    LegalSummaryStep(
      title: 'O app protege',
      text:
          'Tudo viaja criptografado. Suas condições de saúde, respostas de '
          'triagem e anotações de visita são guardadas cifradas no servidor.',
    ),
    LegalSummaryStep(
      title: 'A equipe da sua área vê',
      text:
          'Só o agente comunitário de saúde da sua microárea e a equipe da '
          'sua UBS, para organizar as visitas pela prioridade.',
    ),
    LegalSummaryStep(
      title: 'Em emergência',
      text:
          'Se o alerta for grave, o agente aciona o SAMU com o necessário '
          'para o atendimento.',
    ),
    LegalSummaryStep(
      title: 'Você decide',
      text:
          'Em "Meus dados" você vê o que está guardado, copia seus dados, '
          'muda consentimentos e pede correção ou exclusão.',
    ),
  ],
  sections: [
    LegalSection(
      title: 'Quem cuida dos seus dados',
      body:
          'O responsável pelos seus dados (controlador) é a Secretaria '
          'Municipal de Saúde do seu município, a quem pertence a UBS que '
          'acompanha você. O SinalACS é a ferramenta que a equipe de saúde usa '
          'para organizar as visitas.',
    ),
    LegalSection(
      title: 'Dados que coletamos',
      body:
          'Cadastro: nome, data de nascimento, contato de emergência e se '
          'você tem condição crônica. O CPF é guardado só de forma embaralhada '
          '(hash), usada para conferir o seu acesso.\n'
          'Saúde: condições crônicas e respostas da triagem, guardadas '
          'cifradas, e a classificação de risco que resulta delas.\n'
          'Alerta de urgência: o horário e, se você permitir o GPS, uma área '
          'aproximada de onde você está — nunca o endereço exato.\n'
          'Consentimentos: cada escolha que você faz, com data e versão deste '
          'texto.\n'
          'Lembretes: ficam só no seu aparelho e não vão para o servidor.',
    ),
    LegalSection(
      title: 'Para que usamos',
      body:
          'Para classificar o risco da sua triagem de forma igual para '
          'todos, avisar o agente de saúde quando você pede ajuda, organizar a '
          'fila de visitas da sua microárea e mostrar a você o andamento do seu '
          'pedido. Não usamos seus dados para propaganda nem os vendemos.',
    ),
    LegalSection(
      title: 'Bases legais',
      body:
          'Dados de saúde são tratados com o seu consentimento específico e '
          'para a tutela da saúde (Lei 13.709/2018, art. 11). Os registros que '
          'a lei manda guardar, como os de visita, seguem a obrigação legal '
          '(art. 7º, II). Lembretes e avisos só acontecem se você consentir, e '
          'você pode mudar de ideia quando quiser.',
    ),
    LegalSection(
      title: 'Com quem compartilhamos',
      body:
          'Com o agente comunitário de saúde da sua microárea e com a equipe '
          'da sua UBS. Em emergência, com o SAMU, só o necessário para o '
          'atendimento. Nenhum outro agente de saúde, de outra área, vê seus '
          'dados.',
    ),
    LegalSection(
      title: 'Por quanto tempo guardamos',
      body:
          'Alertas: 2 anos. Visitas: 5 anos, como pede a legislação de '
          'saúde. Registros de acesso: 1 ano. Registros de consentimento: '
          'enquanto existir o cadastro, para provar as suas escolhas. Depois '
          'disso, os dados são apagados ou anonimizados.',
    ),
    LegalSection(
      title: 'Seus direitos',
      body:
          'Você pode confirmar que tratamos seus dados, ver e copiar tudo o '
          'que está guardado, pedir correção, pedir exclusão, retirar os '
          'consentimentos que não são obrigatórios e saber com quem os dados '
          'foram compartilhados. Faça isso em "Meus dados". Os pedidos são '
          'respondidos em até 15 dias.',
    ),
    LegalSection(
      title: 'Como protegemos',
      body:
          'Conexão criptografada entre o app e o servidor, dados de saúde '
          'cifrados no banco, acesso limitado à equipe da sua microárea e '
          'registro de cada acesso aos seus dados.',
    ),
    LegalSection(
      title: 'Encarregado de dados',
      body:
          'O encarregado pelo tratamento de dados (DPO) é o da Secretaria '
          'Municipal de Saúde do seu município. Você pode chegar até ele pela '
          'sua UBS.',
    ),
    LegalSection(
      title: 'Dúvidas sobre seus dados',
      body:
          'Fale com o seu agente comunitário de saúde ou com a sua UBS: eles '
          'encaminham a sua pergunta ao encarregado. Pedidos de correção e de '
          'exclusão podem ser feitos direto em "Meus dados".',
    ),
    LegalSection(
      title: 'Mudanças nesta política',
      body:
          'Quando este texto mudar, o app mostra a nova versão com pelo '
          'menos 15 dias de antecedência e explica o que mudou. As versões '
          'anteriores ficam no histórico abaixo.',
    ),
  ],
  history: _history2026_1,
);

/// Termo de Uso, em linguagem simples (acessível para pessoas idosas e com
/// pouca leitura, LGPD-RF18).
const termsOfUse = LegalDocument(
  id: 'terms',
  title: 'Termo de Uso',
  version: legalDocumentsVersion,
  effectiveDate: '29/09/2026',
  summary: [
    LegalSummaryStep(
      title: 'Para quem é',
      text:
          'Para pacientes acompanhados por um agente comunitário de saúde, '
          'com cadastro na UBS.',
    ),
    LegalSummaryStep(
      title: 'Em risco de vida, ligue 192',
      text:
          'O botão de urgência avisa o seu agente de saúde. Se a vida estiver '
          'em risco, ligue também para o SAMU.',
    ),
    LegalSummaryStep(
      title: 'Use com verdade',
      text:
          'Responda a triagem com sinceridade e use o alerta só quando '
          'precisar de ajuda.',
    ),
    LegalSummaryStep(
      title: 'O app ajuda, não substitui',
      text:
          'A triagem organiza a prioridade das visitas. Ela não é consulta '
          'nem diagnóstico.',
    ),
  ],
  sections: [
    LegalSection(
      title: 'Regras de uso',
      body:
          'O app é para você acompanhar sua saúde com a equipe da sua UBS: '
          'responder a triagem, pedir ajuda em urgência, ver o andamento do seu '
          'pedido e cuidar dos seus dados. O acesso é pessoal: entre só com o '
          'seu CPF ou com o convite que o seu agente de saúde mostrou a você.',
    ),
    LegalSection(
      title: 'Responsabilidades',
      body:
          'A equipe de saúde organiza as visitas pela classificação de risco. '
          'Você se compromete a informar dados verdadeiros e a manter seu '
          'celular protegido. A classificação da triagem não é diagnóstico e '
          'não substitui uma consulta.',
    ),
    LegalSection(
      title: 'O que não é permitido',
      body:
          'Enviar alertas falsos, usar o acesso de outra pessoa, tentar ver '
          'dados de outras pessoas ou atrapalhar o funcionamento do app.',
    ),
    LegalSection(
      title: 'Propriedade intelectual',
      body:
          'O app, sua marca e seu código pertencem aos seus desenvolvedores e '
          'ao poder público que o adotou. O uso é gratuito e não transfere '
          'nenhum desses direitos.',
    ),
    LegalSection(
      title: 'Limites de responsabilidade',
      body:
          'O app depende de internet e do seu aparelho para funcionar. Ele '
          'não garante tempo de atendimento. Em risco de vida, ligue 192 (SAMU) '
          'sem esperar resposta pelo app.',
    ),
    LegalSection(
      title: 'Lei aplicável',
      body:
          'Vale a lei brasileira, incluindo a Lei Geral de Proteção de Dados '
          '(Lei 13.709/2018). Questões judiciais são tratadas no foro do seu '
          'município.',
    ),
    LegalSection(
      title: 'Alterações neste termo',
      body:
          'Quando este termo mudar, o app mostra a nova versão com pelo menos '
          '15 dias de antecedência e pede o seu aceite de novo. As versões '
          'anteriores ficam no histórico abaixo.',
    ),
  ],
  history: _history2026_1,
);
