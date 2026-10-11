# Telas do Backoffice Admin

Documentação visual do protótipo Flutter do backoffice administrativo (`apps/admin`). Assim como `docs/telas-acs.md` e `docs/telas-paciente.md`, as imagens abaixo foram capturadas rodando o app com dados sintéticos: a 01 no emulador em 2026-10-06 e a 01b no Motorola edge 40 neo em 2026-10-07; as de 02 a 05 em 2026-10-07 no emulador `emulator-5554` (API 36, tema escuro, com a borda de 5 px recortada), com sessão real do administrador de teste e **dados do backend** (3 alertas semeados no banco de e2e, nenhum dado real); as de 06 a 08 em 2026-10-07 no Motorola edge 40 neo (Android 15), de uma rodada anterior, com o painel ainda sobre o mock (o layout é o mesmo, mas os números mostrados nelas não são os do backend). A gestão de contas da issue #43 **não tem capturas ainda** — o porquê está em "Capturas pendentes", na seção de Microáreas.

## Navegação

O backoffice é desktop-first (`spec/PRD_system.md` §2.1): acima de `AdminBreakpoints.rail` (640dp) a navegação usa `NavigationRail` lateral; abaixo disso, `NavigationBar` inferior — mesmo `ThemeData`, só muda o container de navegação. Os quatro destinos são **Indicadores**, **Microáreas**, **Alertas** e **Auditoria**. Os pontos de quebra são constantes nomeadas em [`apps/admin/lib/app/admin_layout.dart`](../apps/admin/lib/app/admin_layout.dart).

## Login institucional

![Login do backoffice](screenshots/admin/01-login.png)

Login real do staff (coordenador e administrador): matrícula/CNS e senha vão para `auth.loginStaff`; o painel só abre com a sessão que o servidor devolve, não há atalho de desenvolvimento. A imagem acima foi recapturada em 2026-10-06 no emulador Android (tema escuro, retrato). As capturas 02 a 08 foram refeitas em 2026-10-07 com uma sessão real (login, ativação da MFA e código), e o cabeçalho mostra o papel da sessão ("Backoffice • Administrador"). Os números do painel passaram a vir do backend na issue #40 (as capturas 02 a 05 abaixo foram refeitas então, com dados sintéticos do e2e). Como a verificação em duas etapas é obrigatória para o staff, o fluxo tem três desfechos:

- **Credencial inválida:** a mensagem genérica "Matrícula ou senha inválidos." (a mesma para matrícula inexistente e senha errada) ou o aviso de bloqueio por tentativas.
- **Conta sem MFA (primeiro acesso):** o app abre a tela *Verificação em duas etapas* (`MfaEnrollmentScreen`) em duas etapas. Primeiro pede o **código de ativação** de uso único (`activation_code_field`), que a coordenação entrega fora de banda — o operador emite com `bin/issue_staff_activation_code.dart` (issue #48) e, desde a #43, um administrador também o emite pela tela, em "Equipe do backoffice › Redefinir MFA"; sem ele, o servidor não devolve o segredo. Só então mostra o QR e a chave em texto (`mfa_secret`) para o aplicativo autenticador e o campo do código de 6 dígitos; nada é gravado no aparelho. Ao confirmar, volta ao login com o aviso "Verificação ativada. Entre com o código do aplicativo.".

  ![Etapa do código de ativação](screenshots/admin/01b-codigo-ativacao.png)

  Captura de 2026-10-07 no Motorola edge 40 neo (Android 15), tema escuro, retrato.

- **Conta com MFA:** o campo "Código do autenticador (6 dígitos)" aparece depois de matrícula e senha; trocar matrícula ou senha o descarta. Código errado: "Código de verificação inválido.". A sessão dura 15 min e não há refresh token para o staff; ao vencer, volta ao login com "Sessão encerrada. Entre novamente.".

O roteiro desse fluxo está escrito em `apps/admin/integration_test/admin_login_e2e.dart`, executado por `scripts/qa/admin_login_e2e.sh`; a prova passou em 2026-10-07 num Motorola edge 40 neo (Android 15) com `DEVICE=0087014315` e de novo no emulador `emulator-5554` em 2026-10-09 (ver `PROGRESS.md`). A gestão de contas tem o seu próprio roteiro, `apps/admin/integration_test/admin_acs_gestao_e2e.dart`, executado por `scripts/qa/admin_acs_gestao_e2e.sh` (prova de 2026-10-09 no emulador).

## Painel de indicadores

![Painel de indicadores da UBS](screenshots/admin/02-indicadores.png)

Contadores por `RiskLevel` (vermelho/amarelo/verde), alertas vermelhos abertos vs. reconhecidos e o TMRAV (Tempo Médio de Resposta a Alerta Vermelho, a métrica North Star do PRD). Desde a issue #40 os números vêm do backend (`admin.indicators`): contagens reais por risco e o TMRAV real, média de `acknowledgedAt − triggeredAt` dos alertas vermelhos dos últimos 30 dias. Sem alerta vermelho reconhecido na janela o TMRAV aparece como "—", nunca como "0s". Cor usada exclusivamente como sinal clínico.

## Microáreas, vínculo ACS e gestão de contas

![Listagem de microáreas e ACS vinculado](screenshots/admin/03-microareas.png)

Lista as microáreas da UBS com o ACS vinculado e seu status. Desde a issue #43 a tela **não é mais somente leitura**: abaixo da lista vêm as seções de gestão de contas (a captura acima é anterior à #43 e mostra só a lista). Não há nenhum controle de reclassificação de risco — a classificação é determinística e não alterável por intervenção humana (INV-02 do PRD).

### Gestão de contas de ACS (issue #43)

A seção "Agentes de saúde (ACS)" lista as contas visíveis para a sessão — o administrador vê o sistema inteiro, o coordenador só a UBS dele — com nome, matrícula, UBS, território (ou "sem vínculo") e os selos de acesso (Ativo/Inativo) e de MFA (ativa/não ativada). Cada cartão traz quatro ações:

- **Novo ACS** abre o formulário (nome, matrícula e microárea; a UBS vem da microárea escolhida, nunca do formulário). O servidor sorteia a **senha inicial** — 16 caracteres em quatro grupos — e ela aparece **uma única vez** num diálogo com botão de copiar e o aviso "Esta credencial não será mostrada de novo"; uma recusa de validação (matrícula repetida, por exemplo) aparece dentro do próprio formulário, sem fechá-lo.
- **Vincular** troca a microárea do ACS num diálogo que mostra a consequência ("A microárea define o território do ACS: ele passa a ver só os pacientes dela"). A microárea atual vem pré-selecionada e o botão só habilita com uma microárea **diferente**.
- **Redefinir senha** e **Redefinir MFA** pedem confirmação e explicam a consequência: a senha anterior deixa de valer imediatamente (a nova também é mostrada uma única vez; as sessões abertas seguem ativas até vencer) e a verificação em duas etapas atual deixa de valer — o ACS ativa de novo na próxima entrada, e a conta **não** é desbloqueada por essa ação.
- **Desativar** pede confirmação e avisa que o ACS perde o acesso na hora (o login passa a responder "Este acesso está inativo." e as sessões e os tokens de envio diferido são revogados no servidor); **Ativar** não pede confirmação, porque reativar não é destrutivo — e o acesso novo se obtém com um login novo.

### Equipe do backoffice (somente administrador)

A segunda seção lista as contas de coordenação e administração (matrícula, papel e UBS — ou "Acesso ao sistema inteiro" para o administrador), com os mesmos selos, e oferece **Redefinir MFA**: um código de ativação novo, válido por 24 horas, é emitido e mostrado **uma única vez**, para ser entregue à pessoa. O coordenador não monta esta seção (e o servidor também recusa a listagem para ele), e ninguém redefine a própria MFA — quem perdeu o autenticador pede a outro administrador.

**Capturas pendentes:** as imagens da gestão (seção de ACS com os cartões e as quatro ações, formulário de Novo ACS, diálogo de vínculo, confirmação destrutiva, credencial mostrada uma única vez e a seção Equipe) **não foram capturadas** — as capturas 03 a 08 acima são anteriores à #43. Elas exigem uma sessão real no emulador contra o banco de teste; até lá, o texto descreve o que a tela faz e nenhuma imagem foi inventada.

## Alertas da UBS

![Consulta de alertas filtrável](screenshots/admin/04-alertas.png)

Lista de alertas filtrável por microárea e status. Não há nenhum controle de reclassificação de risco — a classificação é determinística e não alterável por intervenção humana (INV-02 do PRD).

## Logs de auditoria

![Logs de auditoria somente leitura](screenshots/admin/05-auditoria.png)

Log somente leitura, por página de 50 e do mais recente para o mais antigo. Desde a #43 o **coordenador** também lê a auditoria, escopada à UBS dele: o escopo filtra o **autor** da linha, então ele vê as linhas dos profissionais e as pseudonimizadas de paciente da sua UBS, e as linhas de staff (autor sem microárea) ficam invisíveis para ele. Desde a #40 é o **servidor** que audita: cada leitura de indicadores, microáreas, alertas ou da própria auditoria grava uma linha `read` em `audit_logs` **antes** de devolver o dado (se a gravação falha, o dado não sai), atendendo ao requisito do PRD §4.2.2 de que o acesso do Administrador também é auditado; as escritas da gestão de contas (#43) entram na mesma trilha com `resourceType` `admin_acs`/`admin_staff` e o resultado específico (`created`, `micro_area_changed`, `activated`, `deactivated`, `password_reset`, `mfa_reset`), e toda recusa por papel ou escopo grava `denied` antes de a exceção subir. O autor aparece como `MATRÍCULA (Papel)`; a tela nunca recebe hash nem IP.

## Layout em celular (Android)

O app roda em Android desde que a plataforma foi adicionada. Mobile é **complemento do desktop, não substituição**: o layout com rail continua sendo o padrão, e abaixo de `AdminBreakpoints.stacked` (480dp) o que mudaria de significado ao ser espremido passa a empilhar.

![Backoffice em celular, retrato](screenshots/admin/06-android-retrato.png)

Em retrato: `NavigationBar` inferior com os quatro destinos; o selo "Acesso auditado" do cabeçalho vira ícone (mantendo o rótulo para leitores de tela, via `Semantics`); e o `Chip` de vínculo do ACS desce para baixo da descrição em vez de disputar largura com o título — antes, como `trailing` de um `ListTile`, "Sem ACS ativo" comia ~140dp dos ~320dp úteis.

![Backoffice em celular, paisagem](screenshots/admin/07-android-paisagem.png)

Em paisagem o aparelho passa dos 640dp e o `NavigationRail` volta, junto com o chip e com os dois filtros de Alertas lado a lado. Sobram ~288dp de altura para quatro destinos rotulados: cabe por poucos pixels com fonte padrão e estoura a partir de ~150%, então o rail usa `scrollable: true`. A rotação preserva o destino e os filtros selecionados, porque o `AndroidManifest.xml` declara `configChanges` para `orientation` e `fontScale`.

![Backoffice em tablet](screenshots/admin/08-tablet-rail.png)

Em tablet (simulado no Motorola com `wm size 1600x2560` e densidade 280, **não** é um tablet físico) o layout é indistinguível do web: rail lateral, chip no cabeçalho, filtros lado a lado. É essa a checagem de que o desktop-first não regrediu ao ganhar o layout compacto.

Validado no emulador em retrato, paisagem, em tablet e com a fonte do sistema a 200% (WCAG 1.4.4), sem nenhum estouro de layout. A régua automatizada correspondente está em `apps/admin/test/responsive_layout_test.dart` e `text_scale_test.dart`; `apps/admin/integration_test/` repete o percurso no runtime real do Android e é **hermético** — não precisa da stack Docker, ao contrário dos apps ACS e do paciente.

## Referências

- [Implementação Flutter](../apps/admin/lib/app/app.dart)
- [Seções e diálogos da gestão de contas](../apps/admin/lib/app/admin_accounts.dart)
- [Pontos de quebra e altura do cabeçalho](../apps/admin/lib/app/admin_layout.dart)
- [Camada de dados](../apps/admin/lib/core/data/admin_data_source.dart)
- [Protótipos de referência](../spec/ui_acs) (linguagem visual — não há protótipo HTML específico do admin ainda)
- [Guia visual](../spec/ui_design.md)
