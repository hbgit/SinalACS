import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Biblioteca de conteúdo educativo offline (RF20, RF22, C-03).
///
/// O conteúdo vem **só** de `assets/conteudo_educativo/temas.json`, empacotado
/// no APK: não há chamada de rede nem exigência de sessão, então a biblioteca
/// abre sem conta e sem internet. A licença do conteúdo (CC BY 4.0, com a
/// atribuição) está em `assets/conteudo_educativo/LICENCA.md`.
///
/// Regras da decisão P-07, que o parser aplica em vez de confiar no arquivo:
/// - todo tema cita ao menos uma fonte, e toda fonte é do Ministério da Saúde
///   ou da BVS, com endereço nesses domínios;
/// - um tema "revisado" nomeia os revisores e a data da revisão; sem isso é
///   "rascunho", e a tela mostra o selo.
///
/// Um arquivo que quebre essas regras é recusado inteiro
/// ([EducationalLibraryFormatException]): é erro de quem editou o conteúdo, e
/// `test/educational_library_test.dart` o pega antes do build.
const educationalLibraryAsset = 'assets/conteudo_educativo/temas.json';

/// Órgãos aceitos como fonte (P-07) e os hosts que cada um publica.
const educationalSourceHosts = <String, Set<String>>{
  'Ministério da Saúde': {'www.gov.br', 'gov.br', 'bvsms.saude.gov.br'},
  'Biblioteca Virtual em Saúde (BVS)': {'bvsms.saude.gov.br', 'bvs.saude.gov.br'},
};

/// Licenças mostradas em "Sobre" e na biblioteca (C-03, RNF10).
const codeLicenseLabel = 'Código: licença MIT.';
const contentLicenseLabel = 'Conteúdo educativo: licença Creative Commons Atribuição 4.0 '
    'Internacional (CC BY 4.0).';
const contentAttribution = 'Conteúdo educativo do SinalACS, Grupo de Pesquisa PRISM da '
    'Universidade Federal de Roraima (UFRR), em cooperação com o PET-Saúde: '
    'Inovação e Saúde Digital.';

class EducationalLibraryFormatException implements Exception {
  EducationalLibraryFormatException(this.message);
  final String message;
  @override
  String toString() => 'Conteúdo educativo inválido: $message';
}

enum ReviewStatus { draft, reviewed }

class EducationalSource {
  const EducationalSource({
    required this.organization,
    required this.title,
    required this.url,
    required this.consultedOn,
  });

  final String organization;
  final String title;
  final Uri url;
  final String consultedOn;
}

class EducationalSection {
  const EducationalSection({required this.title, required this.paragraphs});
  final String title;
  final List<String> paragraphs;
}

class EducationalReview {
  const EducationalReview({required this.status, required this.reviewers, this.date});
  final ReviewStatus status;
  final List<String> reviewers;
  final String? date;
}

class EducationalTopic {
  const EducationalTopic({
    required this.id,
    required this.title,
    required this.summary,
    required this.sections,
    required this.sources,
    required this.review,
  });

  final String id;
  final String title;
  final String summary;
  final List<EducationalSection> sections;
  final List<EducationalSource> sources;
  final EducationalReview review;

  bool get isDraft => review.status == ReviewStatus.draft;
}

class EducationalLibrary {
  const EducationalLibrary({required this.version, required this.topics});
  final String version;
  final List<EducationalTopic> topics;
}

/// Lê e valida o JSON da biblioteca. Lança [EducationalLibraryFormatException]
/// em qualquer quebra das regras acima.
EducationalLibrary parseEducationalLibrary(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    throw EducationalLibraryFormatException('JSON malformado (${e.message})');
  }
  final root = _map(decoded, 'raiz');
  final version = _text(root, 'versao', 'raiz');
  final rawTopics = _list(root['temas'], 'temas');
  if (rawTopics.isEmpty) {
    throw EducationalLibraryFormatException('nenhum tema');
  }
  final ids = <String>{};
  final topics = <EducationalTopic>[];
  for (final raw in rawTopics) {
    final topic = _parseTopic(_map(raw, 'tema'));
    if (!ids.add(topic.id)) {
      throw EducationalLibraryFormatException('id de tema repetido: ${topic.id}');
    }
    topics.add(topic);
  }
  return EducationalLibrary(version: version, topics: List.unmodifiable(topics));
}

EducationalTopic _parseTopic(Map<String, Object?> raw) {
  final id = _text(raw, 'id', 'tema');
  final where = 'tema "$id"';
  final sections = [
    for (final s in _list(raw['secoes'], '$where.secoes'))
      _parseSection(_map(s, '$where.secao'), where),
  ];
  if (sections.isEmpty) {
    throw EducationalLibraryFormatException('$where sem seções');
  }
  final sources = [
    for (final s in _list(raw['fontes'], '$where.fontes')) _parseSource(_map(s, '$where.fonte'), where),
  ];
  if (sources.isEmpty) {
    // P-07: "sempre citados". Tema sem fonte não entra na biblioteca.
    throw EducationalLibraryFormatException('$where não cita nenhuma fonte');
  }
  return EducationalTopic(
    id: id,
    title: _text(raw, 'titulo', where),
    summary: _text(raw, 'resumo', where),
    sections: List.unmodifiable(sections),
    sources: List.unmodifiable(sources),
    review: _parseReview(_map(raw['revisao'], '$where.revisao'), where),
  );
}

EducationalSection _parseSection(Map<String, Object?> raw, String where) {
  final title = _text(raw, 'titulo', '$where.secao');
  final paragraphs = [
    for (final p in _list(raw['paragrafos'], '$where.secao "$title"'))
      if (p is String && p.trim().isNotEmpty)
        p
      else
        throw EducationalLibraryFormatException('$where.secao "$title": parágrafo vazio ou não texto'),
  ];
  if (paragraphs.isEmpty) {
    throw EducationalLibraryFormatException('$where.secao "$title" sem parágrafos');
  }
  return EducationalSection(title: title, paragraphs: List.unmodifiable(paragraphs));
}

EducationalSource _parseSource(Map<String, Object?> raw, String where) {
  final organization = _text(raw, 'orgao', '$where.fonte');
  final allowedHosts = educationalSourceHosts[organization];
  if (allowedHosts == null) {
    throw EducationalLibraryFormatException(
      '$where: fonte de "$organization"; P-07 aceita só ${educationalSourceHosts.keys.join(' ou ')}',
    );
  }
  final url = Uri.tryParse(_text(raw, 'url', '$where.fonte'));
  if (url == null || url.scheme != 'https' || !allowedHosts.contains(url.host)) {
    throw EducationalLibraryFormatException(
      '$where: endereço da fonte fora dos domínios de "$organization": ${raw['url']}',
    );
  }
  return EducationalSource(
    organization: organization,
    title: _text(raw, 'titulo', '$where.fonte'),
    url: url,
    consultedOn: _text(raw, 'consultadoEm', '$where.fonte'),
  );
}

EducationalReview _parseReview(Map<String, Object?> raw, String where) {
  final status = switch (raw['situacao']) {
    'rascunho' => ReviewStatus.draft,
    'revisado' => ReviewStatus.reviewed,
    final other => throw EducationalLibraryFormatException(
        '$where.revisao.situacao deve ser "rascunho" ou "revisado", não "$other"',
      ),
  };
  final reviewers = [
    for (final r in _list(raw['revisores'], '$where.revisao.revisores'))
      if (r is String && r.trim().isNotEmpty)
        r
      else
        throw EducationalLibraryFormatException('$where.revisao.revisores: nome vazio'),
  ];
  final date = raw['data'];
  if (date != null && date is! String) {
    throw EducationalLibraryFormatException('$where.revisao.data deve ser texto ou null');
  }
  if (status == ReviewStatus.reviewed && (reviewers.isEmpty || date == null || (date as String).isEmpty)) {
    // P-07: "revisão pelos preceptores antes de cada versão". "Revisado" sem
    // quem e quando é afirmação sem lastro.
    throw EducationalLibraryFormatException('$where revisado sem revisores ou sem data');
  }
  return EducationalReview(status: status, reviewers: List.unmodifiable(reviewers), date: date as String?);
}

Map<String, Object?> _map(Object? value, String where) {
  if (value is Map<String, Object?>) return value;
  throw EducationalLibraryFormatException('$where deve ser um objeto');
}

List<Object?> _list(Object? value, String where) {
  if (value is List<Object?>) return value;
  throw EducationalLibraryFormatException('$where deve ser uma lista');
}

String _text(Map<String, Object?> raw, String key, String where) {
  final value = raw[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw EducationalLibraryFormatException('$where.$key ausente ou vazio');
}

/// Fonte da biblioteca, injetável para teste.
abstract interface class EducationalLibrarySource {
  Future<EducationalLibrary> load();
}

/// Lê o asset empacotado no app. Nunca toca a rede.
///
/// Sem cache próprio: o `rootBundle` já guarda o texto do asset, e o parse de
/// poucos temas é barato.
class AssetEducationalLibrarySource implements EducationalLibrarySource {
  const AssetEducationalLibrarySource({AssetBundle? bundle}) : _bundle = bundle;

  final AssetBundle? _bundle;

  @override
  Future<EducationalLibrary> load() async =>
      parseEducationalLibrary(await (_bundle ?? rootBundle).loadString(educationalLibraryAsset));
}
