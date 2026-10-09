import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sinalacs_admin/app/admin_theme.dart';
import 'package:sinalacs_admin/core/data/admin_data_source.dart';

/// Seções e diálogos da gestão de contas do backoffice (#43).
///
/// A tela Microáreas deixou de ser somente leitura: aqui ficam a seção de ACS
/// (cadastro, vínculo, senha, MFA e ativação) e a de Equipe do backoffice (só o
/// administrador), junto dos diálogos que elas abrem.
///
/// Regra de fluxo, provada por `test/acs_management_screen_test.dart`:
/// **toda** ação destrutiva — desativar, redefinir senha, redefinir MFA do ACS
/// e do staff — passa por [_ConfirmacaoDestrutiva], e nada é chamado no servidor
/// antes de o operador confirmar. Reativar e vincular não são destrutivas: o
/// vínculo escolhe a microárea num diálogo, mas não pede uma segunda
/// confirmação.
///
/// Este arquivo não importa `app.dart` de propósito (é `app.dart` quem compõe
/// estas seções): o pouco que as duas telas compartilham — o vocabulário de
/// papel — mora em [_papelDoBackoffice], com a mesma tradução de
/// `adminRoleLabel`.

/// Botão que confirma o diálogo aberto — o destrutivo, o de cadastro e o de
/// vínculo usam a mesma chave: quem opera (e o e2e da Tarefa 12) aprende uma
/// tecla só, e [chaveCancelarAcao] é sempre o caminho de volta.
const chaveConfirmarAcao = Key('confirmar_acao');
const chaveCancelarAcao = Key('cancelar_acao');

/// Rótulo do papel na tela, sem o índice do enum do servidor (`role` chega
/// pelo nome: `admin`/`coordinator`).
String _papelDoBackoffice(String role) => switch (role) {
      'admin' => 'Administrador',
      'coordinator' => 'Coordenador',
      _ => 'Equipe',
    };

/// Texto de uma falha de escrita, na régua do #41: [AdminValidationFailure] é
/// sobre a entrada do próprio operador e vai à tela com a mensagem do servidor
/// ('Já existe um ACS com esta matrícula.'); qualquer outra recusa continua com
/// texto fixo — o motivo de uma recusa de permissão nunca vira texto do
/// servidor.
String mensagemDaFalhaEscrita(Object erro) =>
    erro is AdminValidationFailure ? erro.message : 'Não foi possível concluir a ação. Tente novamente.';

/// Resultado do cadastro para o formulário: a credencial quando deu certo, ou a
/// mensagem a mostrar **dentro** do diálogo. Os dois nulos = sessão vencida (o
/// login assume e o diálogo morre com a árvore).
typedef _ResultadoDoCadastro = ({NewAcsCredential? credencial, String? erro});

/// Abre [_ConfirmacaoDestrutiva] e devolve `true` só se o operador confirmou.
Future<bool> confirmarDestrutiva(
  BuildContext context, {
  required String titulo,
  required String consequencia,
  required String rotuloConfirmar,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmacaoDestrutiva(
        titulo: titulo,
        consequencia: consequencia,
        rotuloConfirmar: rotuloConfirmar,
      ),
    ) ??
    false;

/// Ciclo de vida comum das escritas das duas seções.
///
/// Existe para que "uma escrita por vez, falha tratada num lugar só e lista
/// recarregada no sucesso" não seja reescrito — e divergindo — em cada seção.
mixin _Escritas<T extends StatefulWidget> on State<T> {
  bool ocupado = false;

  VoidCallback get aoRecarregar;
  VoidCallback? get aoVencer;

  /// Roda [acao] e devolve `true` quando ela terminou. A senha nova e o código
  /// de ativação saem por uma variável capturada pela própria [acao]: é o
  /// chamador que sabe qual valor mostrar depois.
  ///
  /// `AdminSessionExpired` entrega a tela ao login ([aoVencer]) sem mensagem: a
  /// sessão vencida não é uma falha da ação, e "tentar de novo" falharia igual.
  Future<bool> escrever(Future<void> Function() acao) async {
    if (ocupado) return false;
    setState(() => ocupado = true);
    var deuCerto = false;
    try {
      await acao();
      deuCerto = true;
    } on AdminSessionExpired {
      aoVencer?.call();
    } catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemDaFalhaEscrita(erro))));
      }
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
    if (deuCerto && mounted) aoRecarregar();
    return deuCerto;
  }
}

/// Seção de ACS da tela Microáreas: lista o estado de cada conta e oferece as
/// ações da issue #43.
class AcsManagementSection extends StatefulWidget {
  const AcsManagementSection({
    required this.dataSource,
    required this.microAreas,
    required this.acs,
    required this.onRecarregar,
    this.aoVencerSessao,
    super.key,
  });

  final AdminDataSource dataSource;

  /// Vêm da carga única da tela: o formulário e o diálogo de vínculo escolhem a
  /// microárea daqui, sem uma segunda busca.
  final List<MicroAreaSummary> microAreas;
  final List<AcsSummary> acs;

  /// Recarrega a lista depois de uma escrita — o estado que a tela mostra vem
  /// do servidor, nunca de uma cópia local atualizada à mão.
  final VoidCallback onRecarregar;
  final VoidCallback? aoVencerSessao;

  @override
  State<AcsManagementSection> createState() => _AcsManagementSectionState();
}

class _AcsManagementSectionState extends State<AcsManagementSection> with _Escritas {
  @override
  VoidCallback get aoRecarregar => widget.onRecarregar;

  @override
  VoidCallback? get aoVencer => widget.aoVencerSessao;

  Future<void> _novoAcs() async {
    final credencial = await showDialog<NewAcsCredential>(
      context: context,
      builder: (_) => _FormularioNovoAcs(
        microAreas: widget.microAreas,
        cadastrar: _cadastrar,
      ),
    );
    if (credencial == null || !mounted) return;
    await _mostrarCredencial(
      titulo: 'Senha inicial de ${credencial.acs.name}',
      explicacao: 'Entregue esta senha ao ACS. É ela que dá o primeiro acesso; a '
          'troca de senha pelo próprio ACS ainda não existe no produto.',
      valor: credencial.initialPassword,
      chaveDoValor: const Key('senha_inicial'),
    );
    if (mounted) widget.onRecarregar();
  }

  /// Cadastro pedido pelo formulário: a falha de validação é mostrada **dentro**
  /// do formulário, onde está o texto que o operador precisa corrigir — fechar o
  /// diálogo a cada recusa faria o operador digitar tudo de novo.
  Future<_ResultadoDoCadastro> _cadastrar(String nome, String matricula, String microAreaId) async {
    try {
      final credencial = await widget.dataSource.createAcs(
        name: nome,
        enrollmentId: matricula,
        microAreaId: microAreaId,
      );
      return (credencial: credencial, erro: null);
    } on AdminSessionExpired {
      widget.aoVencerSessao?.call();
      return const (credencial: null, erro: null);
    } catch (erro) {
      return (credencial: null, erro: mensagemDaFalhaEscrita(erro));
    }
  }

  Future<void> _vincular(AcsSummary acs) async {
    final escolhida = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoDeVinculo(acs: acs, microAreas: widget.microAreas),
    );
    if (escolhida == null || !mounted) return;
    await escrever(() => widget.dataSource.setAcsMicroArea(acsId: acs.id, microAreaId: escolhida));
  }

  Future<void> _alternarAcesso(AcsSummary acs) async {
    if (!acs.active) {
      // Reativar não é destrutivo: um passo só, sem diálogo.
      await escrever(() => widget.dataSource.setAcsActive(acsId: acs.id, active: true));
      return;
    }
    final confirmado = await confirmarDestrutiva(
      context,
      titulo: 'Desativar o acesso de ${acs.name}?',
      consequencia: 'O ACS perde o acesso na hora e o login passa a responder '
          '"Este acesso está inativo.": as sessões abertas e os tokens de envio '
          'diferido são revogados no servidor. O vínculo e o histórico de visitas '
          'continuam guardados, e a conta pode ser reativada depois.',
      rotuloConfirmar: 'Desativar',
    );
    if (!confirmado || !mounted) return;
    await escrever(() => widget.dataSource.setAcsActive(acsId: acs.id, active: false));
  }

  Future<void> _redefinirSenha(AcsSummary acs) async {
    final confirmado = await confirmarDestrutiva(
      context,
      titulo: 'Redefinir a senha de ${acs.name}?',
      consequencia: 'A senha atual deixa de valer imediatamente e uma senha nova '
          'é gerada pelo servidor, mostrada uma única vez. As sessões já abertas '
          'seguem ativas até vencer.',
      rotuloConfirmar: 'Redefinir senha',
    );
    if (!confirmado || !mounted) return;

    String? nova;
    final deuCerto = await escrever(() async {
      nova = await widget.dataSource.resetAcsPassword(acsId: acs.id);
    });
    if (!deuCerto || nova == null || !mounted) return;
    await _mostrarCredencial(
      titulo: 'Nova senha de ${acs.name}',
      explicacao: 'Entregue esta senha ao ACS. A anterior não vale mais.',
      valor: nova!,
      chaveDoValor: const Key('senha_inicial'),
    );
  }

  Future<void> _redefinirMfa(AcsSummary acs) async {
    final confirmado = await confirmarDestrutiva(
      context,
      titulo: 'Redefinir a MFA de ${acs.name}?',
      consequencia: 'A verificação em duas etapas atual deixa de valer e o ACS '
          'precisa ativá-la de novo na próxima entrada. A conta não é '
          'desbloqueada por esta ação.',
      rotuloConfirmar: 'Redefinir MFA',
    );
    if (!confirmado || !mounted) return;
    await escrever(() => widget.dataSource.resetAcsMfa(acsId: acs.id));
  }

  Future<void> _mostrarCredencial({
    required String titulo,
    required String explicacao,
    required String valor,
    required Key chaveDoValor,
  }) =>
      showDialog<void>(
        context: context,
        builder: (_) => _CredencialMostradaUmaVez(
          titulo: titulo,
          explicacao: explicacao,
          valor: valor,
          chaveDoValor: chaveDoValor,
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text('Agentes de saúde (ACS)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              FilledButton.icon(
                key: const Key('novo_acs'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                onPressed: ocupado ? null : _novoAcs,
                icon: const Icon(Icons.person_add_alt_outlined),
                label: const Text('Novo ACS'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Cadastro, vínculo de microárea, senha e MFA. Cada ação é auditada no backoffice.'),
          const SizedBox(height: 12),
          if (widget.acs.isEmpty)
            const Text('Nenhum ACS no seu escopo ainda.')
          else
            for (final acs in widget.acs)
              Card(
                key: Key('acs_${acs.id}'),
                margin: const EdgeInsets.only(bottom: 12),
                child: _CartaoAcs(
                  acs: acs,
                  ocupado: ocupado,
                  aoVincular: () => _vincular(acs),
                  aoAlternarAcesso: () => _alternarAcesso(acs),
                  aoRedefinirSenha: () => _redefinirSenha(acs),
                  aoRedefinirMfa: () => _redefinirMfa(acs),
                ),
              ),
        ],
      );
}

/// Seção de contas de equipe do backoffice — só o administrador a vê (o
/// servidor recusa a listagem para o coordenador, então não é só a tela que a
/// esconde).
class StaffManagementSection extends StatefulWidget {
  const StaffManagementSection({
    required this.dataSource,
    required this.staff,
    required this.onRecarregar,
    this.aoVencerSessao,
    super.key,
  });

  final AdminDataSource dataSource;
  final List<StaffSummary> staff;
  final VoidCallback onRecarregar;
  final VoidCallback? aoVencerSessao;

  @override
  State<StaffManagementSection> createState() => _StaffManagementSectionState();
}

class _StaffManagementSectionState extends State<StaffManagementSection> with _Escritas {
  @override
  VoidCallback get aoRecarregar => widget.onRecarregar;

  @override
  VoidCallback? get aoVencer => widget.aoVencerSessao;

  Future<void> _redefinirMfa(StaffSummary conta) async {
    final confirmado = await confirmarDestrutiva(
      context,
      titulo: 'Redefinir a MFA de ${conta.name}?',
      consequencia: 'A verificação em duas etapas atual deixa de valer. Um código '
          'de ativação novo é emitido aqui, vale 24 horas e é mostrado uma única '
          'vez — entregue a ${conta.name} para a próxima entrada.',
      rotuloConfirmar: 'Redefinir MFA',
    );
    if (!confirmado || !mounted) return;

    String? codigo;
    final deuCerto = await escrever(() async {
      codigo = (await widget.dataSource.resetStaffMfa(staffId: conta.id)).code;
    });
    if (!deuCerto || codigo == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _CredencialMostradaUmaVez(
        titulo: 'Código de ativação de ${conta.name}',
        explicacao: 'Entregue este código a ${conta.name}: ele ativa a MFA na '
            'próxima entrada. Vale 24 horas e a MFA antiga já não vale mais.',
        valor: codigo!,
        chaveDoValor: const Key('codigo_ativacao'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Equipe do backoffice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Contas de coordenação e administração. A redefinição de MFA é feita por outro administrador.'),
          const SizedBox(height: 12),
          if (widget.staff.isEmpty)
            const Text('Nenhuma conta de equipe no seu escopo.')
          else
            for (final conta in widget.staff)
              Card(
                key: Key('staff_${conta.id}'),
                margin: const EdgeInsets.only(bottom: 12),
                child: _CartaoStaff(
                  conta: conta,
                  ocupado: ocupado,
                  aoRedefinirMfa: () => _redefinirMfa(conta),
                ),
              ),
        ],
      );
}

class _CartaoAcs extends StatelessWidget {
  const _CartaoAcs({
    required this.acs,
    required this.ocupado,
    required this.aoVincular,
    required this.aoAlternarAcesso,
    required this.aoRedefinirSenha,
    required this.aoRedefinirMfa,
  });

  final AcsSummary acs;
  final bool ocupado;
  final VoidCallback aoVincular;
  final VoidCallback aoAlternarAcesso;
  final VoidCallback aoRedefinirSenha;
  final VoidCallback aoRedefinirMfa;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(acs.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Matrícula: ${acs.enrollmentId}'),
            Text('UBS: ${acs.ubsName}'),
            // "Território" e não "Microárea: ${nome}": o nome já começa por
            // "Microárea NN —" e o rótulo repetido leria mal. O território é o
            // vocabulário da territorialização (INV-01) no produto.
            Text('Território: ${acs.microAreaName ?? 'sem vínculo'}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(acs.active ? Icons.check_circle_outline : Icons.remove_circle_outline, size: 18),
                  label: Text(acs.active ? 'Ativo' : 'Inativo'),
                  backgroundColor: AdminColors.surface,
                ),
                Chip(
                  avatar: Icon(acs.mfaActive ? Icons.lock_outline : Icons.lock_open_outlined, size: 18),
                  label: Text(acs.mfaActive ? 'MFA ativa' : 'MFA não ativada'),
                  backgroundColor: AdminColors.surface,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: Key('vincular_acs_${acs.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                  onPressed: ocupado ? null : aoVincular,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Vincular'),
                ),
                OutlinedButton.icon(
                  key: Key('redefinir_senha_${acs.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                  onPressed: ocupado ? null : aoRedefinirSenha,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Redefinir senha'),
                ),
                OutlinedButton.icon(
                  key: Key('redefinir_mfa_${acs.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                  onPressed: ocupado ? null : aoRedefinirMfa,
                  icon: const Icon(Icons.phonelink_lock_outlined),
                  label: const Text('Redefinir MFA'),
                ),
                OutlinedButton.icon(
                  key: Key('${acs.active ? 'desativar' : 'ativar'}_acs_${acs.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
                  onPressed: ocupado ? null : aoAlternarAcesso,
                  icon: Icon(acs.active ? Icons.block_outlined : Icons.play_circle_outline),
                  label: Text(acs.active ? 'Desativar' : 'Ativar'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _CartaoStaff extends StatelessWidget {
  const _CartaoStaff({required this.conta, required this.ocupado, required this.aoRedefinirMfa});

  final StaffSummary conta;
  final bool ocupado;
  final VoidCallback aoRedefinirMfa;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(conta.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Matrícula: ${conta.enrollmentId} • ${_papelDoBackoffice(conta.role)}'),
            Text(conta.ubsName == null ? 'Acesso ao sistema inteiro' : 'UBS: ${conta.ubsName}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(conta.active ? Icons.check_circle_outline : Icons.remove_circle_outline, size: 18),
                  label: Text(conta.active ? 'Ativa' : 'Inativa'),
                  backgroundColor: AdminColors.surface,
                ),
                Chip(
                  avatar: Icon(conta.mfaActive ? Icons.lock_outline : Icons.lock_open_outlined, size: 18),
                  label: Text(conta.mfaActive ? 'MFA ativa' : 'MFA não ativada'),
                  backgroundColor: AdminColors.surface,
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: Key('redefinir_mfa_staff_${conta.id}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52)),
              onPressed: ocupado ? null : aoRedefinirMfa,
              icon: const Icon(Icons.phonelink_lock_outlined),
              label: const Text('Redefinir MFA'),
            ),
          ],
        ),
      );
}

/// Diálogo de confirmação das ações destrutivas.
///
/// O título diz o que vai acontecer, o corpo diz a consequência em texto claro
/// (o que se perde, o que continua guardado) e o rótulo que confirma usa
/// [AdminColors.redOnSurface] — o token de texto, nunca o `red` de
/// preenchimento, que como texto cai para ~3:1 sobre a superfície do diálogo.
class _ConfirmacaoDestrutiva extends StatelessWidget {
  const _ConfirmacaoDestrutiva({
    required this.titulo,
    required this.consequencia,
    required this.rotuloConfirmar,
  });

  final String titulo;
  final String consequencia;
  final String rotuloConfirmar;

  /// O tema não define mínimo global de botão, e o `AlertDialog` do Material 3
  /// nasce com alvos abaixo dos 48dp da WCAG 2.5.5 — como em `login_screen.dart`.
  static final _estilo = ButtonStyle(
    minimumSize: WidgetStateProperty.all(const Size(48, 52)),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
        // `scrollable`: a consequência de uma ação destrutiva é uma frase longa
        // e, com a fonte do sistema a 200% (WCAG 1.4.4), não caberia na altura
        // do diálogo sem cortar texto.
        scrollable: true,
        title: Text(titulo),
        content: Text(consequencia),
        actions: [
          TextButton(
            key: chaveCancelarAcao,
            style: _estilo,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: chaveConfirmarAcao,
            style: _estilo,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              rotuloConfirmar,
              style: const TextStyle(color: AdminColors.redOnSurface, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
}

/// Formulário de cadastro de ACS.
///
/// O cadastro é feito por [cadastrar] (a seção) enquanto o diálogo continua
/// aberto: assim uma recusa de validação aparece junto dos campos que o
/// operador precisa corrigir, em vez de fechar o formulário e perder o que foi
/// digitado.
class _FormularioNovoAcs extends StatefulWidget {
  const _FormularioNovoAcs({required this.microAreas, required this.cadastrar});

  final List<MicroAreaSummary> microAreas;
  final Future<_ResultadoDoCadastro> Function(String nome, String matricula, String microAreaId) cadastrar;

  @override
  State<_FormularioNovoAcs> createState() => _FormularioNovoAcsState();
}

class _FormularioNovoAcsState extends State<_FormularioNovoAcs> {
  final _nome = TextEditingController();
  final _matricula = TextEditingController();
  String? _microAreaId;
  String? _erro;
  bool _enviando = false;

  @override
  void dispose() {
    _nome.dispose();
    _matricula.dispose();
    super.dispose();
  }

  bool get _completo => _nome.text.trim().isNotEmpty && _matricula.text.trim().isNotEmpty && _microAreaId != null;

  Future<void> _enviar() async {
    if (!_completo || _enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final resultado = await widget.cadastrar(_nome.text.trim(), _matricula.text.trim(), _microAreaId!);
    if (!mounted) return;
    if (resultado.credencial != null) {
      Navigator.of(context).pop(resultado.credencial);
      return;
    }
    setState(() {
      _enviando = false;
      _erro = resultado.erro;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        // `scrollable`: a consequência de uma ação destrutiva é uma frase longa
        // e, com a fonte do sistema a 200% (WCAG 1.4.4), não caberia na altura
        // do diálogo sem cortar texto.
        scrollable: true,
        title: const Text('Novo ACS'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('acs_nome_field'),
                controller: _nome,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Nome completo'),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('acs_matricula_field'),
                controller: _matricula,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Matrícula / CNS'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('acs_microarea_field'),
                initialValue: _microAreaId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Microárea'),
                hint: const Text('Escolha a microárea'),
                items: [
                  for (final area in widget.microAreas)
                    DropdownMenuItem(value: area.id, child: Text(area.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (valor) => setState(() => _microAreaId = valor),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('A UBS do ACS vem da microárea escolhida, nunca do formulário.'),
              ),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _erro!,
                      key: const Key('cadastro_erro'),
                      style: const TextStyle(color: AdminColors.redOnSurface, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: chaveCancelarAcao,
            style: _ConfirmacaoDestrutiva._estilo,
            onPressed: _enviando ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: chaveConfirmarAcao,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: _completo && !_enviando ? _enviar : null,
            child: Text(_enviando ? 'Cadastrando…' : 'Cadastrar'),
          ),
        ],
      );
}

/// Diálogo de vínculo: escolher a microárea e confirmar. Não é destrutivo, mas
/// a escolha é explícita — o vínculo muda quem enxerga o território.
class _DialogoDeVinculo extends StatefulWidget {
  const _DialogoDeVinculo({required this.acs, required this.microAreas});

  final AcsSummary acs;
  final List<MicroAreaSummary> microAreas;

  @override
  State<_DialogoDeVinculo> createState() => _DialogoDeVinculoState();
}

class _DialogoDeVinculoState extends State<_DialogoDeVinculo> {
  String? _microAreaId;

  @override
  void initState() {
    super.initState();
    _microAreaId = widget.acs.microAreaId;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        // `scrollable`: a consequência de uma ação destrutiva é uma frase longa
        // e, com a fonte do sistema a 200% (WCAG 1.4.4), não caberia na altura
        // do diálogo sem cortar texto.
        scrollable: true,
        title: Text('Vincular ${widget.acs.name} a uma microárea'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A microárea define o território do ACS: ele passa a ver só os pacientes dela.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('vincular_microarea_field'),
                initialValue: _microAreaId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Microárea'),
                hint: const Text('Escolha a microárea'),
                items: [
                  for (final area in widget.microAreas)
                    DropdownMenuItem(value: area.id, child: Text(area.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (valor) => setState(() => _microAreaId = valor),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: chaveCancelarAcao,
            style: _ConfirmacaoDestrutiva._estilo,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: chaveConfirmarAcao,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: _microAreaId == null || _microAreaId == widget.acs.microAreaId
                ? null
                : () => Navigator.of(context).pop(_microAreaId),
            child: const Text('Vincular'),
          ),
        ],
      );
}

/// Diálogo de uma credencial que só existe nesta resposta do servidor — a senha
/// inicial do ACS e o código de ativação do staff. Depois de fechado não há
/// como vê-la de novo (o servidor guarda só o hash), então o aviso e o botão de
/// copiar estão aqui.
class _CredencialMostradaUmaVez extends StatelessWidget {
  const _CredencialMostradaUmaVez({
    required this.titulo,
    required this.explicacao,
    required this.valor,
    required this.chaveDoValor,
  });

  final String titulo;
  final String explicacao;
  final String valor;

  /// `senha_inicial` ou `codigo_ativacao`: é daqui que os testes e o e2e leem a
  /// credencial.
  final Key chaveDoValor;

  @override
  Widget build(BuildContext context) => AlertDialog(
        // `scrollable`: a consequência de uma ação destrutiva é uma frase longa
        // e, com a fonte do sistema a 200% (WCAG 1.4.4), não caberia na altura
        // do diálogo sem cortar texto.
        scrollable: true,
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explicacao),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        valor,
                        key: chaveDoValor,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                    Semantics(
                      label: 'Copiar',
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () => Clipboard.setData(ClipboardData(text: valor)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta credencial não será mostrada de novo. Copie ou entregue agora.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          FilledButton(
            key: const Key('fechar_credencial'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      );
}
