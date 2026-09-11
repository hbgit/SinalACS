# Como contribuir com o SinalACS

Obrigado por contribuir com o SinalACS. Este guia descreve como preparar o
ambiente, validar mudanças e preservar os requisitos de segurança, privacidade
e confiabilidade do projeto.

O SinalACS é um protótipo funcional para priorização de atendimentos na Atenção
Primária à Saúde. Ele não está pronto para produção e não deve ser usado com
dados reais de pacientes.

## Conduta, segurança e privacidade

O [Código de Conduta](.github/CODE_OF_CONDUCT.draft.md) está em processo de
formalização. Siga suas regras de convivência em todas as interações do projeto.

Vulnerabilidades devem ser relatadas de forma privada conforme a
[Política de Segurança](.github/SECURITY.md). Não publique vulnerabilidades em
issues, pull requests ou discussões antes da coordenação com os mantenedores.

Issues, pull requests, discussões e commits não são canais de urgência médica,
atendimento a pacientes ou suporte clínico.

Nunca inclua dados reais de pacientes, CPF, endereços, localização, informações
clínicas identificáveis, credenciais, chaves, tokens ou segredos em código,
fixtures, logs, capturas de tela, issues, pull requests ou commits. Use somente
dados sintéticos e remova informações sensíveis de qualquer evidência antes de
publicá-la.

Consulte [AGENTS.md](AGENTS.md) e [spec/lgpd_design.md](spec/lgpd_design.md)
para os requisitos completos de privacidade e proteção de dados.

## Antes de começar

Leia os documentos relevantes para a alteração proposta. Quando houver conflito
com uma convenção genérica, a documentação do projeto prevalece.

- [README.md](README.md): visão geral e execução local.
- [spec/PRD_system.md](spec/PRD_system.md): requisitos e invariantes.
- [spec/stack.md](spec/stack.md): arquitetura e infraestrutura.
- [spec/ui_design.md](spec/ui_design.md): linguagem visual e acessibilidade.
- [spec/lgpd_design.md](spec/lgpd_design.md): privacidade e LGPD.
- [CLAUDE.md](CLAUDE.md): arquitetura implementada e comandos atualizados.
- [PROGRESS.md](PROGRESS.md): estado atual dos milestones.

## Pré-requisitos

- Flutter SDK compatível com Dart `>=3.3.0 <4.0.0`; a CI usa Flutter 3.24.0.
- Dart SDK 3.8.0 para o backend.
- Docker Engine com Docker Compose v2.
- Android SDK API 36 e JDK 17 para executar ou gerar os aplicativos Android.

## Ambiente local

Para iniciar PostgreSQL, Mosquitto, backend e Traefik, execute na raiz:

```bash
docker compose up --build
```

Para encerrar a stack:

```bash
docker compose down
```

Essa stack e suas credenciais são exclusivas de desenvolvimento. Não reutilize
credenciais locais nem exponha o dashboard de desenvolvimento em ambientes
públicos. Para limitações do piloto, consulte
[backend/DEPLOY.md](backend/DEPLOY.md).

## Validar alterações

Execute as validações relativas aos componentes alterados. A CI executa análise
e testes para backend e ambos os aplicativos, além do build da imagem do
servidor.

### Backend

```bash
cd backend
dart pub get
dart analyze
cd sinalacs_server
dart test
```

Os testes unitários não exigem banco:

```bash
cd backend/sinalacs_server
dart test test/unit
```

Os testes de integração usam o harness Serverpod e requerem PostgreSQL em
`localhost:9090`, banco `sinalacs_test` e credenciais locais configuradas em
`config/passwords.yaml`. O harness aplica as migrações e reverte os dados em
cada caso de teste.

Quando a alteração afetar a imagem do servidor, execute também:

```bash
docker build -f backend/sinalacs_server/Dockerfile backend
```

### Aplicativos Flutter

Execute em `apps/acs` ou `apps/patient`, conforme a área alterada:

```bash
flutter pub get
flutter analyze
flutter test
```

Para executar um aplicativo em dispositivo ou emulador:

```bash
flutter run
```

## Alterações no backend

O backend é um workspace Serverpod. Mantenha lógica de negócio em `application/`
e implementações de banco ou MQTT em `infrastructure/`. Serviços de aplicação
devem depender de interfaces, permitindo testes unitários com fakes.

Ao alterar modelos `.spy.yaml` ou adicionar endpoints, execute em
`backend/sinalacs_server`:

```bash
serverpod generate
serverpod create-migration
```

Não edite manualmente `lib/src/generated/` nem `migrations/`: esses arquivos
são produzidos pelas ferramentas Serverpod.

Mudanças em triagem, alertas, autorização, MQTT, persistência ou sincronização
precisam preservar estes invariantes:

- ACS acessa somente dados de sua microárea.
- A classificação de risco é determinística e não pode ser alterada na triagem.
- Alertas vermelhos não podem ser descartados silenciosamente.
- Dados sensíveis de saúde exigem proteção conforme LGPD.

Adicione testes unitários para regras de aplicação e testes de integração quando
a mudança tocar endpoints, ORM, esquema ou integração entre componentes.

## Alterações nos aplicativos Flutter

Siga a linguagem visual definida em [spec/ui_design.md](spec/ui_design.md): modo
escuro, alta legibilidade, baixo ruído e foco em acessibilidade. Vermelho,
amarelo e verde são sinais clínicos e não devem ser usados como decoração.

Ao alterar persistência local, MQTT ou a fila offline, cubra cenários de rede
instável, retry, conflito e falha segura conforme aplicável. Os aplicativos ainda
não possuem integração completa de ponta a ponta com os serviços de produção;
não presuma que uma mudança local esteja conectada ao backend real.

## Pull requests

Antes de abrir um pull request, mantenha o escopo pequeno e confirme que as
validações relevantes passaram. Relacione uma issue existente ou explique a
necessidade da mudança na descrição.

Inclua na descrição:

- Problema resolvido e mudança realizada.
- Componentes e fluxos afetados.
- Testes executados e resultado.
- Impacto em privacidade, segurança, dados de saúde ou operação offline.
- Atualizações de documentação, modelos ou migrações, quando aplicáveis.

Use títulos e commits claros e descritivos. O projeto não exige atualmente um
formato específico para nomes de branches ou mensagens de commit.

Os mantenedores definem prioridade, revisão e merge. Contribuições não devem
assumir autenticação institucional, infraestrutura de produção ou integrações
clínicas que ainda não estejam implementadas.