import 'package:flutter/material.dart';
import 'package:sinalacs_patient/core/education/educational_library.dart';
import 'package:sinalacs_patient/core/legal/educational_notice.dart';

/// Biblioteca de saúde (RF20, RF22, C-03): lista de temas, offline e sem conta.
///
/// Abre do login (antes de qualquer sessão) e do menu "Mais". Não recebe nem
/// procura o backend: o conteúdo vem só do asset ([EducationalLibrarySource]).
/// As cores são as do tema; cor clínica não entra aqui (`spec/ui_design.md`).
class EducationalLibraryScreen extends StatefulWidget {
  const EducationalLibraryScreen({super.key, this.source});

  /// Injetável para teste; sem ela vale o asset do app
  /// ([AssetEducationalLibrarySource]).
  final EducationalLibrarySource? source;

  @override
  State<EducationalLibraryScreen> createState() => _EducationalLibraryScreenState();
}

class _EducationalLibraryScreenState extends State<EducationalLibraryScreen> {
  late Future<EducationalLibrary> _library = _load();

  /// `ignore()` só evita que a falha conte como erro não tratado no intervalo
  /// até o próximo `build`; o [FutureBuilder] continua recebendo o erro.
  Future<EducationalLibrary> _load() => (widget.source ?? const AssetEducationalLibrarySource()).load()..ignore();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('educational_library'),
      appBar: AppBar(title: const Text('Biblioteca de saúde')),
      body: SafeArea(
        child: FutureBuilder<EducationalLibrary>(
          future: _library,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _LibraryError(onRetry: () {
                setState(() {
                  _library = _load();
                });
              });
            }
            final library = snapshot.data;
            if (library == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Temas de saúde para ler quando quiser, mesmo sem internet e sem cadastro.',
                  style: TextStyle(fontSize: 16, color: scheme.onSurface),
                ),
                const SizedBox(height: 8),
                const _ShortNotice(),
                const SizedBox(height: 16),
                for (final topic in library.topics) ...[
                  _TopicCard(topic: topic),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
                const _LicenseFooter(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});
  final EducationalTopic topic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: Key('library_topic_${topic.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EducationalTopicScreen(topic: topic)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(topic.summary, style: TextStyle(color: scheme.onSurface)),
                      if (topic.isDraft) ...[
                        const SizedBox(height: 8),
                        const _DraftBadge(compact: true),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Um tema: seções, fontes citadas e a situação da revisão (P-07).
class EducationalTopicScreen extends StatelessWidget {
  const EducationalTopicScreen({super.key, required this.topic});
  final EducationalTopic topic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface);
    final body = TextStyle(fontSize: 16, height: 1.4, color: scheme.onSurface);
    return Scaffold(
      key: Key('educational_topic_${topic.id}'),
      appBar: AppBar(title: Text(topic.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (topic.isDraft) ...[
              const _DraftBadge(compact: false),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                'Revisado por ${topic.review.reviewers.join(', ')} em ${topic.review.date}.',
                key: const Key('topic_reviewed'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
            ],
            for (final section in topic.sections) ...[
              Semantics(header: true, child: Text(section.title, style: heading)),
              const SizedBox(height: 8),
              for (final paragraph in section.paragraphs) ...[
                Text(paragraph, style: body),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
            ],
            const Divider(height: 32),
            Semantics(header: true, child: Text('Fontes', style: heading)),
            const SizedBox(height: 8),
            for (final (i, source) in topic.sources.indexed) ...[
              Container(
                key: Key('topic_source_$i'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.organization, style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(source.title, style: TextStyle(color: scheme.onSurface)),
                    const SizedBox(height: 4),
                    // Sem abrir o navegador: o app não tem url_launcher, e a
                    // biblioteca é offline. O endereço pode ser copiado.
                    SelectableText(source.url.toString(), style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      'Consultado em ${_dataBr(source.consultedOn)}.',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            const _ShortNotice(),
            const SizedBox(height: 16),
            const _LicenseFooter(),
          ],
        ),
      ),
    );
  }
}

/// `2026-11-08` → `08/11/2026`; qualquer outro formato passa como veio.
String _dataBr(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  return m == null ? iso : '${m[3]}/${m[2]}/${m[1]}';
}

/// Selo de tema não revisado (P-07). Ícone + texto, nunca só cor.
class _DraftBadge extends StatelessWidget {
  const _DraftBadge({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('topic_draft_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note, size: 20, color: scheme.onSurface),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              compact
                  ? 'Rascunho — aguardando revisão'
                  : 'Rascunho — aguardando revisão dos preceptores do PET-Saúde. '
                      'O texto pode mudar.',
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortNotice extends StatelessWidget {
  const _ShortNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            educationalNoticeShort,
            key: const Key('library_short_notice'),
            style: TextStyle(color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}

class _LicenseFooter extends StatelessWidget {
  const _LicenseFooter();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Text(
      '$contentLicenseLabel $contentAttribution',
      key: const Key('library_license'),
      style: style,
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                'Não foi possível abrir a biblioteca neste aparelho.',
                key: const Key('library_error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
