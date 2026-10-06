# Telas do Backoffice Admin

Documentação visual do protótipo Flutter do backoffice administrativo (`apps/admin`). Assim como `docs/telas-acs.md` e `docs/telas-paciente.md`, as imagens abaixo foram capturadas rodando o app com dados sintéticos: as cinco primeiras em Flutter Web (`flutter run -d web-server`), as da seção *Layout em celular* num emulador Android (`flutter run -d emulator-5554`).

## Navegação

O backoffice é desktop-first (`spec/PRD_system.md` §2.1): acima de `AdminBreakpoints.rail` (640dp) a navegação usa `NavigationRail` lateral; abaixo disso, `NavigationBar` inferior — mesmo `ThemeData`, só muda o container de navegação. Os quatro destinos são **Indicadores**, **Microáreas**, **Alertas** e **Auditoria**. Os pontos de quebra são constantes nomeadas em [`apps/admin/lib/app/admin_layout.dart`](../apps/admin/lib/app/admin_layout.dart).

## Login institucional

![Login do backoffice](screenshots/admin/01-login.png)

Login real do staff (coordenador e administrador): matrícula/CNS e senha vão para `auth.loginStaff`; o painel só abre com a sessão que o servidor devolve, não há atalho de desenvolvimento. A imagem acima é da versão anterior (formulário local) e não foi recapturada. Como a verificação em duas etapas é obrigatória para o staff, o fluxo tem três desfechos:

- **Credencial inválida:** a mensagem genérica "Matrícula ou senha inválidos." (a mesma para matrícula inexistente e senha errada) ou o aviso de bloqueio por tentativas.
- **Conta sem MFA (primeiro acesso):** o app abre a tela *Verificação em duas etapas* (`MfaEnrollmentScreen`), com o QR e a chave em texto (`mfa_secret`) para o aplicativo autenticador e o campo do código de 6 dígitos; nada é gravado no aparelho. Ao confirmar, volta ao login com o aviso "Verificação ativada. Entre com o código do aplicativo.".
- **Conta com MFA:** o campo "Código do autenticador (6 dígitos)" aparece depois de matrícula e senha; trocar matrícula ou senha o descarta. Código errado: "Código de verificação inválido.". A sessão dura 15 min e não há refresh token para o staff; ao vencer, volta ao login com "Sessão encerrada. Entre novamente.".

O roteiro desse fluxo está escrito em `apps/admin/integration_test/admin_login_e2e.dart`, executado por `scripts/qa/admin_login_e2e.sh`; a execução no emulador ainda está pendente (ver `PROGRESS.md`).

## Painel de indicadores

![Painel de indicadores da UBS](screenshots/admin/02-indicadores.png)

Contadores por `RiskLevel` (vermelho/amarelo/verde), alertas vermelhos abertos vs. reconhecidos e o TMRAV (Tempo Médio de Resposta a Alerta Vermelho, a métrica North Star do PRD). Dados mockados atrás de `AdminDataSource`; cor usada exclusivamente como sinal clínico.

## Microáreas e vínculo ACS

![Listagem de microáreas e ACS vinculado](screenshots/admin/03-microareas.png)

Lista somente leitura das microáreas da UBS com o ACS vinculado e seu status. Edição de vínculo fica para uma issue futura, como definido no escopo.

## Alertas da UBS

![Consulta de alertas filtrável](screenshots/admin/04-alertas.png)

Lista de alertas filtrável por microárea e status. Não há nenhum controle de reclassificação de risco — a classificação é determinística e não alterável por intervenção humana (INV-02 do PRD).

## Logs de auditoria

![Logs de auditoria somente leitura](screenshots/admin/05-auditoria.png)

Log somente leitura. Toda visita às telas de Microáreas, Alertas e Auditoria registra uma entrada própria via `AdminDataSource.recordAccess`, simulando o requisito do PRD §4.2.2 de que o acesso do Administrador também é auditado.

## Layout em celular (Android)

O app roda em Android desde que a plataforma foi adicionada. Mobile é **complemento do desktop, não substituição**: o layout com rail continua sendo o padrão, e abaixo de `AdminBreakpoints.stacked` (480dp) o que mudaria de significado ao ser espremido passa a empilhar.

![Backoffice em celular, retrato](screenshots/admin/06-android-retrato.png)

Em retrato: `NavigationBar` inferior com os quatro destinos; o selo "Acesso auditado" do cabeçalho vira ícone (mantendo o rótulo para leitores de tela, via `Semantics`); e o `Chip` de vínculo do ACS desce para baixo da descrição em vez de disputar largura com o título — antes, como `trailing` de um `ListTile`, "Sem ACS ativo" comia ~140dp dos ~320dp úteis.

![Backoffice em celular, paisagem](screenshots/admin/07-android-paisagem.png)

Em paisagem o aparelho passa dos 640dp e o `NavigationRail` volta, junto com o chip e com os dois filtros de Alertas lado a lado. Sobram ~288dp de altura para quatro destinos rotulados: cabe por poucos pixels com fonte padrão e estoura a partir de ~150%, então o rail usa `scrollable: true`. A rotação preserva o destino e os filtros selecionados, porque o `AndroidManifest.xml` declara `configChanges` para `orientation` e `fontScale`.

![Backoffice em tablet](screenshots/admin/08-tablet-rail.png)

Em tablet (AVD `Medium_Tablet`, 2560x1600) o layout é indistinguível do web: rail lateral, chip no cabeçalho, filtros lado a lado. É essa a checagem de que o desktop-first não regrediu ao ganhar o layout compacto.

Validado no emulador em retrato, paisagem, em tablet e com a fonte do sistema a 200% (WCAG 1.4.4), sem nenhum estouro de layout. A régua automatizada correspondente está em `apps/admin/test/responsive_layout_test.dart` e `text_scale_test.dart`; `apps/admin/integration_test/` repete o percurso no runtime real do Android e é **hermético** — não precisa da stack Docker, ao contrário dos apps ACS e do paciente.

## Referências

- [Implementação Flutter](../apps/admin/lib/app/app.dart)
- [Pontos de quebra e altura do cabeçalho](../apps/admin/lib/app/admin_layout.dart)
- [Camada de dados](../apps/admin/lib/core/data/admin_data_source.dart)
- [Protótipos de referência](../spec/ui_acs) (linguagem visual — não há protótipo HTML específico do admin ainda)
- [Guia visual](../spec/ui_design.md)
