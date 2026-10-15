# Publicação na Google Play

Guia de boas práticas e passo a passo para publicar um app do SinalACS na
Google Play Store, do build assinado ao acompanhamento depois do lançamento.

O SinalACS tem três apps Flutter com plataforma Android configurada:

| App      | Caminho        | applicationId                        |
|----------|----------------|--------------------------------------|
| Paciente | `apps/patient` | `br.com.prismrr.sinalacs.patient`    |
| ACS      | `apps/acs`     | `br.com.prismrr.sinalacs.acs`        |
| Admin    | `apps/admin`   | `br.com.prismrr.sinalacs.admin`      |

Todos usam `minSdk = 24` e `targetSdk = 36`. Nenhum foi publicado ainda.

> **Estado atual:** o projeto é um protótipo e não está pronto para produção.
> Este guia descreve o caminho de publicação; as lacunas que hoje o impedem
> estão na seção [Pós-análise](#pós-análise).

## 1. Pré-requisitos

### 1.1 Conta de desenvolvedor Google Play

| Ponto | Organização | Pessoal |
|-------|-------------|---------|
| Indicada para | Apps institucionais | Desenvolvedor individual |
| Verificação | Identidade e, em geral, verificação da organização (D-U-N-S) — conferir no Play Console Help | Verificação de identidade |
| Teste fechado obrigatório | Não se aplica | Sim, se a conta foi criada depois de 13/11/2023 |

- **Taxa:** o registro tem uma taxa única. Conferir o valor atual no
  Play Console antes de abrir a conta.
- **Conta pessoal nova:** antes de pedir acesso à produção, é preciso rodar um
  teste fechado com no mínimo 12 testers com adesão contínua de 14 dias. O
  teste interno não conta para essa regra. Depois dos 14 dias, o Google avalia
  um formulário de acesso à produção, então reserve cerca de três semanas.
- **Conta pessoal × organização:** a escolha decide se essa exigência se
  aplica. A regra vale por conta e pode mudar; confirmar no
  [Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465).
- **Quem é o titular:** o titular da conta aparece na ficha pública da loja.
  Definir com os mantenedores quem será, antes de abrir a conta.

### 1.2 Acesso ao Play Console

- Quem publica precisa de uma conta Google com permissão de envio de versões
  no Play Console (papéis e permissões em *Usuários e permissões*).
- Não compartilhar a conta do titular; conceder acesso por usuário.

### 1.3 Ferramentas

Usar as mesmas versões do CI (`.github/workflows/ci.yml`):

| Ferramenta | Versão | Observação |
|------------|--------|------------|
| Flutter    | 3.44.8 | fixada no CI |
| JDK        | 17 (Temurin) | também é o alvo de `sourceCompatibility` e `jvmTarget` |
| Android SDK | plataforma 36 | `compileSdk = 36` |
| `keytool`  | vem com o JDK | usado na seção de assinatura |

O build de release do `apps/admin` foi testado localmente com Flutter 3.47.2
e JDK 25 e compilou com avisos. Como isso foi um teste único, o recomendado
continua sendo o JDK 17 e o Flutter do CI.

## 2. Preparação do app

### 2.1 applicationId definitivo

Cada app tem o seu `applicationId` definido em
`apps/<app>/android/app/build.gradle.kts` (mesmo valor do `namespace`):

| App      | applicationId                      |
|----------|------------------------------------|
| Paciente | `br.com.prismrr.sinalacs.patient`  |
| ACS      | `br.com.prismrr.sinalacs.acs`      |
| Admin    | `br.com.prismrr.sinalacs.admin`    |

**Depois que o app é publicado, o `applicationId` não pode mais mudar.** Ele
identifica o app na loja. Antes do primeiro envio, confirmar com os
mantenedores que os três valores são os definitivos.

### 2.2 Versão (versionCode e versionName)

Os três `build.gradle.kts` leem `versionCode` e `versionName` do Flutter
(`flutter.versionCode`, `flutter.versionName`), que vêm do `pubspec.yaml`:

```yaml
version: 1.0.1+2   # versionName = 1.0.1, versionCode = 2
```

- A parte antes do `+` é o `versionName` (o que o usuário vê).
- A parte depois do `+` é o `versionCode`. **O Play exige um `versionCode`
  maior a cada arquivo enviado**, mesmo para os testes internos.

Hoje os três apps estão com `version: 1.0.0`, sem o `+n`. Antes do primeiro
envio, passar para `1.0.0+1` e incrementar o número a cada novo AAB.

### 2.3 Nome, ícone adaptativo e splash

- **Nome exibido:** vem do `android:label` do `AndroidManifest.xml` (no Admin é
  `SinalACS Admin`). Conferir os rótulos do Paciente e do ACS e usar nomes
  curtos e distintos entre si.
- **Ícone:** o Admin e o Paciente usam só os PNGs de `mipmap-*`, sem a pasta
  `mipmap-anydpi-v26`, ou seja, **sem ícone adaptativo**. Conferir o ACS.
  Antes de publicar, gerar o ícone adaptativo (primeiro plano e fundo) e
  verificar como ele aparece nos formatos de máscara de cada fabricante.
- **Splash:** conferir `res/drawable/launch_background.xml` e
  `res/values/styles.xml` de cada app; o tema `LaunchTheme` é o que aparece
  enquanto o Flutter inicia.

### 2.4 Revisão do AndroidManifest.xml e das permissões

Permissões declaradas hoje no manifest principal (`src/main`):

| App      | Permissões declaradas |
|----------|------------------------|
| Paciente | `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, `RECEIVE_BOOT_COMPLETED` |
| ACS      | nenhuma |
| Admin    | nenhuma |

Pontos a revisar antes de publicar:

- **`INTERNET`:** nos três apps ela não aparece no `main` (conferido no manifest `main` de cada um) e aparece só nos manifests de debug e profile(conferido no Admin e no ACS).  
  Um release
  que precise acessar o backend precisa dela no manifest principal. Confirmar
  olhando o manifest mesclado do release (ver 2.6).
- **`POST_NOTIFICATIONS`:** o Paciente depende de `flutter_local_notifications`
  e chama `requestNotificationsPermission()` em `lib/main.dart`, mas o
  manifest principal não a declara. Conferir no manifest mesclado.
- **`RECEIVE_BOOT_COMPLETED`:** não é habitual num app de paciente. Descobrir
  de onde vem (possivelmente de um plugin) e remover se não for necessária.
- **Localização:** o Paciente usa `geolocator` com leitura pontual em primeiro
  plano (`getCurrentPosition`); não foi encontrado uso em segundo plano.
- **Câmera:** nenhum dos três apps depende de plugin de câmera.
- **Toda permissão declarada precisa de justificativa** no Play Console (ver
  a seção de Conformidade). Remover o que não for usado.

### 2.5 Remover o que é de desenvolvimento

- **`ENABLE_DEV_LOGIN`:** habilita `auth.developmentLogin` no backend. Não pode
  estar ligado em produção.
- **CA de desenvolvimento:** `scripts/dev/sync_dev_ca.sh` copia duas CAs de
  desenvolvimento para `apps/*/assets/certs/` (`dev_ca.crt` e
  `dev_rpc_ca.crt`). Confirmar se um release apontando para um servidor com
  certificado público precisa delas e retirá-las do pacote se não precisar.
- **Host padrão:** no Paciente, `lib/core/network/backend_config.dart`
  define `defaultValue: 'https://10.0.2.2/'`, o endereço da máquina vista do
  emulador. Em um celular real ele não funciona. O host de produção deve ser
  informado no build:

```bash
  flutter build appbundle --release \
    --dart-define=SINALACS_HOST=https://<HOST_DE_PRODUCAO>/
```

  Conferir o mesmo arquivo em `apps/acs/lib/core/network/`. O Admin ainda não
  faz requisições (roda sobre `MockAdminDataSource`), então não tem host
  configurável.
- **ACS, segredos em `--dart-define`:** `SINALACS_MQTT_PASSWORD` não tem valor
  padrão e `GOOGLE_MAPS_API_KEY` vira texto vazio se faltar, sem erro de
  build. Nenhum valor real deve aparecer no repositório nem neste documento.
- **Admin, login:** o login é real (`auth.loginStaff`, matrícula + senha + TOTP) e
  não há atalho de desenvolvimento; o painel só abre com a sessão devolvida pelo
  servidor. O host do RPC tem de ser HTTPS (`SINALACS_HOST`).

### 2.6 Conferir o manifest mesclado

Depois de um build de release, confirmar as permissões finais, já com as que
os plugins adicionam:

```bash
cd apps/<app>
find build -name AndroidManifest.xml -path "*release*"
grep -n "uses-permission" <caminho-encontrado>
```

## 3. Assinatura

O Google Play só aceita pacotes assinados. Hoje os três apps assinam o release
com a chave de debug (`signingConfig = signingConfigs.getByName("debug")` no
bloco `release` de cada `build.gradle.kts`). **Um pacote assinado com a chave de
debug não deve ser enviado ao Play.**

### 3.1 Gerar a upload key

A *upload key* é a chave com a qual você assina o pacote que envia ao Play. Com
o Play App Signing (seção 3.4), a chave que assina o app para os usuários fica
com o Google.

Gere a chave **fora do repositório** (por exemplo, no seu diretório pessoal):

```bash
keytool -genkeypair -v \
  -keystore "$HOME/sinalacs-<app>-upload.jks" \
  -alias upload \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

- `<app>` é `patient`, `acs` ou `admin`. Usar uma chave por app evita que o
  comprometimento de uma afete as outras (recomendação deste guia).
- `-validity 10000` são cerca de 27 anos.
- O `keytool` pergunta a senha do keystore e os dados do certificado. Use uma
  senha forte e guarde-a conforme a seção 3.5.
- O formato padrão do `keytool` do JDK 17 e do 25 é PKCS12.

Para conferir o conteúdo (alias, validade e impressões digitais SHA-1 e
SHA-256):

```bash
keytool -list -v -keystore "$HOME/sinalacs-<app>-upload.jks"
```

### 3.2 key.properties fora do versionamento

Crie `apps/<app>/android/key.properties` com os dados da chave. Use valores
seus; **nunca** escreva senhas reais neste documento nem no repositório:

```properties
storePassword=<SENHA_DO_KEYSTORE>
keyPassword=<SENHA_DA_CHAVE>
keyAlias=upload
storeFile=<CAMINHO_ABSOLUTO_DO_JKS>
```

O `apps/admin/android/.gitignore` já ignora `key.properties`, `*.keystore` e
`*.jks`. Antes de qualquer commit, confirme o mesmo nos outros apps:

```bash
git check-ignore -v apps/patient/android/key.properties apps/acs/android/key.properties
git status
```

O `git status` não pode listar `key.properties` nem arquivos `.jks`.

### 3.3 signingConfigs de release no build.gradle.kts

Em `apps/<app>/android/app/build.gradle.kts`, o bloco abaixo lê o
`key.properties` e assina o release com a upload key, no lugar da chave de
debug. O trecho segue o padrão da documentação do Flutter e **não foi aplicado
neste repositório**; adapte-o ao arquivo de cada app (o do ACS tem lógica
própria para as `--dart-define`):

```kotlin
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

Com isso, um `flutter build appbundle --release` sem `key.properties` falha, o
que é desejável: evita gerar por engano um release assinado com a chave errada.
O job `admin-android-build` do CI compila só `--debug`, então não é afetado.

### 3.4 Play App Signing

Com o Play App Signing, o Google guarda a chave que assina o app entregue aos
usuários e você assina cada envio com a upload key. Para apps novos, é o modelo
exigido junto com o formato AAB (conferir no Play Console Help). Na primeira
publicação, o Play Console oferece a adesão ao criar a versão.

Consequência para este projeto: o SHA-1 que vale para restringir a
`GOOGLE_MAPS_API_KEY` dos apps instalados pela loja é o do **certificado de
assinatura do app** (Play Console, em *Integridade do app*), e não o da upload
key. Ver a seção de Conformidade.

### 3.5 Onde guardar a chave e o que fazer se ela for perdida

- Guarde o `.jks` e as senhas em um cofre de senhas da instituição, com uma
  cópia de segurança em um segundo local.
- Senha e arquivo ficam em lugares separados.
- Nunca envie a chave ou as senhas por chat, e-mail ou issue, e não as coloque
  em repositório, nem mesmo privado.
- Defina duas pessoas com acesso, para que a saída de uma não deixe o projeto
  sem a chave.

**Se a upload key for perdida ou exposta:** com o Play App Signing ativo, o
titular pode pedir ao Google o reset da upload key pelo Play Console (*Integridade
do app*). Gera-se uma nova chave, envia-se o certificado público e, depois da
análise do Google, ela passa a valer. Sem o Play App Signing, perder a chave
impede novas atualizações do app. Confirmar o procedimento atual no Play
Console Help.

## 4. Build de release

### 4.1 AAB, não APK

O Play recebe o pacote no formato **Android App Bundle (AAB)**, e não APK. A
loja gera a partir dele os APKs otimizados para cada aparelho. Conferir no
Play Console Help se o AAB continua sendo exigido para apps novos.

```bash
cd apps/<app>
flutter pub get
flutter build appbundle --release
```

O arquivo sai em `build/app/outputs/bundle/release/app-release.aab`.

**Teste local (`apps/admin`, Flutter 3.47.2, JDK 25):** o comando acima
concluiu em cerca de 56 segundos e gerou um AAB de 47,6 MB. Esse pacote foi
assinado com a chave de debug (estado atual do repositório) e **não deve ser
enviado ao Play**. Só passa a valer para envio depois da seção 3.

O build modifica arquivos versionados. Depois de rodar `flutter pub get` e o
build, o Flutter alterou `apps/admin/pubspec.lock` e
`apps/admin/analysis_options.yaml`. Confira com `git status` e não inclua
essas mudanças em um commit que não seja sobre elas.

### 4.2 Parâmetros de cada app

| App      | O que passar no build |
|----------|------------------------|
| Paciente | `--dart-define=SINALACS_HOST=https://<HOST_DE_PRODUCAO>/` |
| ACS      | `SINALACS_MQTT_PASSWORD` e `GOOGLE_MAPS_API_KEY`, além do host; ver abaixo |
| Admin    | nada (não há segredos nem host configurável) |

- **ACS:** o `build.gradle.kts` faz falhar de propósito um build comum sem a
  senha do broker MQTT, e o caminho usado no desenvolvimento é
  `./scripts/dev/run_acs.sh --build`, que gera um **APK** de desenvolvimento.
  Um AAB de release do ACS exige passar as mesmas `--dart-define` no
  `flutter build appbundle`. Esse fluxo **não foi testado** neste guia.
- Os valores reais (senha do broker, chave do Maps) vêm do ambiente de quem
  compila, nunca do repositório e nunca deste documento. A
  `GOOGLE_MAPS_API_KEY` vira texto vazio se faltar e o build não falha; o mapa
  quebra só em execução.

### 4.3 Ofuscação e símbolos de depuração

A ofuscação dificulta a engenharia reversa do código Dart e reduz o tamanho.
Ela exige `--split-debug-info`, que grava os símbolos fora do pacote:

```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=<PASTA_DE_SIMBOLOS>
```

- **Guarde a pasta de símbolos, por versão.** Sem ela, os relatórios de crash
  ficam ilegíveis. Use um nome que inclua a versão (por exemplo,
  `simbolos/<app>/1.0.0+1/`).
- Não guarde os símbolos dentro do repositório. Eles não são segredo, mas são
  grandes e mudam a cada build; o lugar certo é o armazenamento de artefatos
  da instituição.
- Para ler um stack trace ofuscado, use `flutter symbolize`, apontando para o
  arquivo de símbolos da arquitetura correspondente (ver a documentação do
  Flutter sobre ofuscação).

**Teste local (`apps/admin`):** o build com `--obfuscate` e
`--split-debug-info` concluiu em cerca de 47 segundos e gerou um AAB de
45,2 MB. A pasta de símbolos recebeu três arquivos, um por arquitetura:
`app.android-arm64.symbols`, `app.android-arm.symbols` e
`app.android-x64.symbols`. O build também avisou que a biblioteca gerada
contém informação de depuração (DWARF) não ofuscada e sugeriu a opção
`--strip`; essa opção não foi testada neste guia.

### 4.4 R8 / ProGuard

Os `build.gradle.kts` dos três apps **não têm configuração explícita** de
`isMinifyEnabled` nem de `proguardFiles`. Mesmo assim, no build de release do
`apps/admin` (Flutter 3.47.2) o R8 rodou: `build/app/outputs/mapping/release/`
ficou com `mapping.txt`, `usage.txt`, `seeds.txt`, `configuration.txt`,
`resources.txt` e `mapping.prt`. Isso foi verificado só no Admin; para Paciente
e ACS, confira do mesmo modo depois do build:

```bash
ls build/app/outputs/mapping/release/
```

Guarde o `mapping.txt` junto com os símbolos da seção 4.3, por versão, e envie-o
ao Play Console ao publicar. Se o código minificado quebrar algum plugin, os
erros aparecem só no release; teste o AAB de release em um aparelho antes de
enviar.

### 4.5 Tamanho do pacote

Anote o tamanho de cada AAB a cada versão:

```bash
ls -lh build/app/outputs/bundle/release/
```

Referência: o AAB do `apps/admin` ficou com 47,6 MB. Com ofuscação, o mesmo app ficou com 45,2 MB. Esse valor é maior do
que o esperado para um app que só mostra dados mock, e ainda não foi
investigado. O AAB contém todas as arquiteturas, e o tamanho de download que o
usuário vê é menor. Conferir no Play Console o tamanho estimado de download e
os limites atuais de tamanho do pacote.

## 5. Ficha no Play Console

A ficha é o que o público vê na loja. Ela vale para os apps que forem
publicados na loja pública (ver a seção de particularidades por app). Os
limites abaixo devem ser conferidos no Play Console Help, porque mudam com o
tempo.

### 5.1 Textos

| Campo | Limite habitual | Observação |
|-------|-----------------|------------|
| Título | 30 caracteres | Nome do app na loja; pode diferir do `android:label` |
| Descrição curta | 80 caracteres | Aparece nos resultados de busca |
| Descrição longa | 4.000 caracteres | Explica o que o app faz e para quem |

Orientações para o SinalACS:

- Descreva apenas o que o app faz hoje. O SinalACS prioriza atendimentos a
  partir de sinais clínicos estruturados; ele **não faz diagnóstico** nem
  substitui atendimento de urgência. Deixe isso explícito na descrição longa.
- Não prometa resultados clínicos nem use termos como "diagnóstico" ou
  "tratamento" para descrever a triagem.
- Nenhum texto, exemplo ou captura pode conter dado real de paciente.
- O texto da ficha deve ser coerente com a política de privacidade e com a
  declaração de Data safety (seção de Conformidade).

Rascunho de ponto de partida para o app do Paciente, a alinhar com os
mantenedores antes de publicar (baseado nos fluxos descritos em `AGENTS.md`:
login por código, alerta de urgência, triagem estruturada, acompanhamento do
pedido e painel "Meus Dados"):

- *Descrição curta:* "Informe seus sinais de saúde e acompanhe o retorno da
  equipe da sua área." (conferir o limite de 80 caracteres)
- *Descrição longa:* descrever cada fluxo em uma frase, incluir o aviso de que
  o app não substitui o serviço de urgência (SAMU) e indicar o canal de
  contato para dúvidas de privacidade.

### 5.2 Imagens

- **Capturas de tela:** `docs/screenshots/acs` e `docs/screenshots/admin` têm
  cinco capturas cada, e `docs/screenshots/patient` tem apenas uma
  (`01-emergencia.png`, a tela de alerta de urgência). O `docs/README.md`
  informa que as capturas usam dados sintéticos. A Play Store exige um
  número mínimo de capturas por tipo de aparelho (conferir o número atual no
  Play Console Help), então, antes de publicar o app do Paciente, é preciso
  produzir mais capturas dos fluxos dele, sempre com dados sintéticos. Confira
  também as dimensões exigidas pela loja.
- **Ícone:** o da loja é enviado à parte do ícone do app. Ver a seção 2.3 sobre
  o ícone adaptativo.
- **Feature graphic:** imagem de destaque, habitualmente de 1024 × 500 px
  (conferir). Ainda não existe no repositório e precisa ser criada.
- Capturas de tela não podem expor dados pessoais, nomes reais, CPFs nem
  localizações reais.

### 5.3 Categoria

Duas categorias são candidatas: **Medicina** e **Saúde e fitness**. A escolha
interage com a política de apps de saúde (seção de Conformidade), então deve
ser decidida junto com a declaração de apps de saúde. Escolher a categoria que
descreve a função real do app, sem inflar o escopo clínico.

### 5.4 Classificação de conteúdo (IARC)

O Play Console pede o preenchimento de um questionário do IARC, que gera a
classificação etária de cada região. Responda de acordo com o que o app de
fato contém (por exemplo, se há conteúdo gerado por usuários ou compras).
Respostas imprecisas podem levar à rejeição ou à remoção do app.

### 5.5 Público-alvo

Declare a faixa etária do público. O app do Paciente coleta CPF, data de
nascimento e dados de saúde, então a escolha do público-alvo precisa ser
coerente com a política de privacidade e com o tratamento de dados de
menores previsto na LGPD (`spec/lgpd_design.md`). Se o público incluir
crianças, valem exigências adicionais da loja (conferir no Play Console
Help). Decidir isso com os mantenedores antes de preencher.

## 6. Conformidade

Os três apps tratam dados de saúde e, no caso do Paciente, CPF, data de
nascimento e localização. Nenhum dado real de paciente pode aparecer em
capturas, contas de teste, exemplos ou neste documento. As regras do Google
mudam com frequência: confira cada ponto abaixo no Play Console Help antes de
enviar.

### 6.1 Justificativa de permissões sensíveis

A justificativa de cada permissão deve ser coerente com o que o app faz, com a
declaração de Data safety (6.4) e com a política de privacidade (6.5).

| Permissão | App | Situação hoje | O que justificar |
|-----------|-----|---------------|------------------|
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Paciente | Declaradas no `main`; uso em primeiro plano com `getCurrentPosition` | Por que o app lê a posição do paciente |
| `POST_NOTIFICATIONS` | Paciente | Não declarada no `main`; o app pede a permissão em execução | Por que o app envia notificações |
| `RECEIVE_BOOT_COMPLETED` | Paciente | Declarada no `main`; origem não investigada | Só se ficar; remover se não for necessária |
| Câmera | nenhum | Nenhum plugin de câmera nos três apps | Não se aplica; não declare câmera |

**Localização (Paciente).** A leitura é pontual e em primeiro plano; não foi
encontrado `getPositionStream` no `lib/` do Paciente nem
`ACCESS_BACKGROUND_LOCATION` no manifest. Enquanto isso se mantiver, o
formulário específico de localização em segundo plano não deveria ser
necessário (conferir). O que o app faz com a posição está descrito em
`spec/lgpd_data_audit.md`: um digest SHA-256 sobre latitude e longitude
normalizadas em seis casas, truncado em 12 caracteres, guardado em campos como
`alerts.locationHash`. A auditoria trata isso como **pseudonimização, não
anonimização**, e registra que o digest truncado ainda pode ser correlacionado
por força bruta, principalmente em áreas rurais. Por isso, na ficha e na
política de privacidade, a localização deve ser declarada como dado coletado,
e não como "não coletada". A justificativa de uso (associar o alerta de
urgência à posição do paciente) deve ser confirmada no fluxo do app antes de
ser escrita na ficha.

**Notificações (Paciente).** O app depende de `flutter_local_notifications` e
chama `requestNotificationsPermission()`, mas o manifest principal não declara
`POST_NOTIFICATIONS`. Se o plugin não a adicionar ao manifest mesclado, em
aparelhos com Android 13 ou superior as notificações não aparecem com
`targetSdk = 36`. Conferir no manifest mesclado do release (seção 2.6) e, se
faltar, declarar a permissão e justificar o uso.

**ACS e Admin.** Nenhum dos dois declara permissão no `main`. Conferir o
manifest mesclado do release antes de preencher qualquer formulário.

### 6.2 GOOGLE_MAPS_API_KEY

Apenas o ACS usa mapa (`google_maps_flutter`). A chave entra no build por
`--dart-define=GOOGLE_MAPS_API_KEY=<SUA_CHAVE>` e é injetada no manifest como
`com.google.android.geo.API_KEY`; ela não está versionada. Se a variável
faltar, o valor vira texto vazio e o build **não falha**: o mapa só quebra em
execução. Por isso, confirme em um aparelho que o mapa carrega no release.

Restrinja a chave no Google Cloud Console por **nome do pacote**
(`br.com.prismrr.sinalacs.acs`) e por **SHA-1 do certificado de assinatura**.
Com o Play App Signing (seção 3.4), o SHA-1 que vale para o app instalado pela
loja é o do certificado de assinatura do app, que aparece no Play Console em
*Integridade do app*, e não o da upload key. Registre também o SHA-1 da upload
key e o de debug, se quiser testar AABs e builds locais com a mesma chave.
Nunca coloque o valor da chave neste documento nem no repositório.

### 6.3 Credenciais de teste para o revisor do Google

O Google precisa conseguir abrir o app para revisá-lo. Um app que pede login e
não dá acesso ao revisor costuma ser reprovado (conferir a regra atual de
*Acesso ao app* no Play Console Help). Regras deste projeto:

- Use **contas fictícias**, criadas só para o revisor, em um ambiente de teste.
  Jamais forneça dado real de paciente ou credencial institucional real.
- Não escreva usuário, senha ou código neste documento; eles vão apenas no
  formulário do Play Console.

Situação de cada app hoje:

| App | Como entra hoje | Problema para o revisor |
|-----|-----------------|--------------------------|
| Paciente | CPF, data de nascimento e código OTP | Um revisor não recebe o código; é preciso uma conta de teste com um caminho de acesso definido (decisão em aberto) |
| ACS | Matrícula e senha (login institucional) | Precisa de uma matrícula fictícia e de um backend acessível pela internet |
| Admin | Login real do staff (matrícula + senha + TOTP) contra o backend; sem atalho de desenvolvimento | O revisor precisa de uma conta de staff com MFA ativada e de um backend acessível; sem isso não passa da primeira tela |

Em todos os casos, o backend precisa estar acessível para o revisor. Hoje não
existe deploy de produção (`backend/DEPLOY.md` descreve apenas uma demo
free-tier).

### 6.4 Data safety (declaração de segurança dos dados)

O formulário de Data safety do Play Console pede, para cada tipo de dado,
se o app **coleta** e se **compartilha**, se o dado é tratado só de forma
efêmera, se é obrigatório ou opcional e para quê é usado. Ele também pergunta
se os dados trafegam criptografados e se o usuário pode pedir a exclusão.

A fonte deste mapeamento é `spec/lgpd_data_audit.md`. Regras:

- Declara-se o que o app **envia para fora do aparelho**, mesmo que o servidor
  guarde só um hash. O CPF, por exemplo, é enviado no login do Paciente
  (`auth.requestOtp`); o fato de o servidor persistir apenas o hash não tira o
  CPF da declaração.
- Dado pseudonimizado continua sendo dado pessoal (a própria auditoria trata
  o `locationHash` assim). Não declare como "não coletado".
- O formulário cobre também o que bibliotecas de terceiros coletam. O ACS usa
  `google_maps_flutter`; revise o que o SDK do mapa coleta e como o Google
  trata a transferência a prestadores de serviço (conferir no Play Console
  Help o que conta como "compartilhamento").

Mapeamento em andamento (tabelas lidas até aqui):

| Dado (tabela.coluna) | Categoria provável no formulário (conferir) | Observação da auditoria |
|----------------------|----------------------------------------------|--------------------------|
| `users.name` | Informações pessoais: nome | Texto claro; necessário para a identificação presencial pelo ACS |
| `users.birthDate` | Informações pessoais: outras (data de nascimento) | Timestamp exato; a auditoria sugere avaliar truncar para data ou idade |
| `users.cpfHash` | Identificadores de usuário ou outras informações (conferir) | Persistido como hash; o CPF em si é enviado no login |
| `users.role`, `users.microAreaId` | Identificadores de usuário | Perfil e microárea; base do controle de acesso por território |
| `user_credentials.*` (ACS) | Credenciais de login (conferir onde declarar) | A senha é enviada no login do ACS e persistida só como Argon2id com salt |
| `otp_challenges.*` (Paciente) | Dado de autenticação | O código não é persistido em claro, só o HMAC-SHA-256; validade de 5 minutos e teto de 5 tentativas |
| `enrollment_tokens.*` (Paciente, criado pelo ACS) | Dado de autenticação | O token é persistido só como hash (`tokenHash`) |
| `patients.emergencyContact` | Informações pessoais de terceiro (conferir a categoria) | Dado de outra pessoa; o conteúdo do campo (nome, telefone) precisa ser confirmado |
| `patients.isChronic`, `patients.chronicConditions`, `patients.lastTriageAt` | Saúde e fitness: informações de saúde | `chronicConditions` é persistida como texto cifrado com versão da chave |
| `triage_sessions.answers`, `resultRisk`, `resultDisplay` (Paciente) | Saúde e fitness: informações de saúde | `answers` é persistida como texto cifrado com versão da chave |
| `visits.riskLevelBefore`, `riskLevelAfter`, `notes` (ACS) | Saúde e fitness: informações de saúde | `notes` é persistida como texto cifrado com versão da chave |
| `alerts.riskLevel`, `status` e horários | Saúde e fitness: informações de saúde (nível de risco) | Alertas vermelhos não podem ser descartados em silêncio |
| `patients.lastLocationHash`, `alerts.locationHash` | Localização (conferir se aproximada ou precisa) | Digest SHA-256 truncado de latitude e longitude; pseudonimização, não anonimização |
| `triage_sessions.deviceId`, `alerts.deviceId` | Identificadores de dispositivo ou outros | Identificador do aparelho |

**Ainda a mapear:** as tabelas seguintes do inventário (`alert_deliveries`,
`audit_logs` e as demais, incluindo as do Serverpod).

**Uma declaração por app.** O formulário é preenchido para cada app. Antes
de enviar, separe esta tabela em uma versão para cada app publicado:

- **Paciente:** CPF, data de nascimento, respostas de triagem, alerta de
  urgência, dado de localização, identificador de dispositivo e contato de
  emergência.
- **ACS:** matrícula e senha, visitas e notas, lista de pacientes da
  microárea.
- **Admin:** hoje não envia nada (usa dados mock); a declaração muda quando o
  backend existir.

**Pontos a confirmar antes de preencher o formulário:**

- O que `patients.emergencyContact` guarda e se o app do Paciente o envia.
- Como o código OTP chega ao paciente. A auditoria não mostra telefone nem
  e-mail nas tabelas lidas.
- Se a coordenada de localização sai do aparelho ou só o digest. A auditoria
  recomenda impedir que a coordenada crua saia do dispositivo, mas o que o app
  envia hoje não foi verificado neste guia.

**Em trânsito:** o RPC é HTTPS (TLS terminado no Traefik) e o broker MQTT usa
TLS na porta 8883. Isso vale para o ambiente de desenvolvimento descrito no
repositório; confirmar no ambiente de produção quando ele existir.

**Exclusão de dados:** a auditoria (seção 4.1) registra a ausência de rotina
de expurgo. O formulário pergunta se o usuário pode pedir a exclusão, e a
resposta precisa refletir o que existe de fato.

**Antes de enviar o formulário**, cada ponto abaixo precisa estar resolvido,
porque o Data safety é responsabilidade do desenvolvedor e deve ser coerente
com a política de privacidade:

1. Separar o mapeamento por app (Paciente, ACS e, depois, Admin).
2. Ajustar os nomes de categoria à versão atual do formulário.
3. Fechar os três pontos em aberto: conteúdo de `patients.emergencyContact`,
   canal de entrega do código OTP e o que sai do aparelho na localização.
4. Mapear as tabelas restantes do inventário (`spec/lgpd_data_audit.md`).
5. Revisar o que o SDK do mapa (ACS) coleta.

### 6.5 Política de privacidade

Todo app publicado precisa de uma política de privacidade, e ela deve ser
informada em dois lugares: no campo próprio do Play Console e dentro do app
(link ou texto). Requisitos da política do Google (conferir a versão atual):

- URL **ativa, pública, sem restrição geográfica, não PDF e não editável**.
- Nome da entidade que aparece na ficha da loja deve constar na política, ou
  o app deve ser citado nela.
- Deve descrever acesso, coleta, uso e compartilhamento de dados pessoais e
  sensíveis de forma abrangente, **sem se limitar ao que foi declarado no Data
  safety**.
- Deve ser coerente com o Data safety (6.4) e com as permissões (6.1).

**Situação hoje:** não existe URL pública de política de privacidade, e o
repositório não a hospeda. Isso impede a publicação (ver Pós-análise).

**Conteúdo mínimo sugerido**, a alinhar com `spec/lgpd_design.md` e com um
responsável jurídico/encarregado de dados:

- quem é o controlador e como falar com o encarregado (LGPD);
- quais dados cada app coleta, para quê e com qual base legal;
- dados de saúde e de localização, tratados como sensíveis ou com risco
  aumentado, incluindo que o `locationHash` é pseudonimização e não
  anonimização (`spec/lgpd_data_audit.md`);
- com quem os dados são compartilhados (por exemplo, o prestador do serviço de
  mapa, no ACS);
- por quanto tempo são guardados. A auditoria registra a **ausência de rotina
  de expurgo**; a política não pode prometer prazos que o sistema não cumpre;
- direitos do titular e como exercê-los. O app do Paciente já tem o painel
  "Meus Dados" (LGPD) descrito no `AGENTS.md`; confirmar o que ele permite de
  fato antes de citá-lo;
- que o app **não substitui atendimento de urgência**.

### 6.6 Declaração de apps de saúde e política de conteúdo médico

O SinalACS trata dados de saúde e oferece uma triagem, então está no escopo da
política de saúde do Google. Passos no Play Console:

1. Em *Política > Conteúdo do app* (App content), preencher a **declaração de
   apps de saúde** (Health apps declaration), escolhendo as categorias que
   descrevem o app. Uma declaração por app.
2. Manter a declaração coerente com a categoria da loja (seção 5.3), com o
   Data safety e com as permissões.
3. Pedir só as permissões que a função principal exige e **remover as não
   usadas** (ver seção 2.4: `RECEIVE_BOOT_COMPLETED` e `POST_NOTIFICATIONS`).

**Conteúdo médico.** A política do Google proíbe funcionalidade de saúde
enganosa ou prejudicial e exige comprovação regulatória ou aviso para apps
com função médica. Orientações para o SinalACS:

- A classificação de risco é determinística e segue o modelo do Protocolo de
  Manchester, conforme o `CLAUDE.md`. A ficha e o app devem descrevê-la como
  **apoio à priorização**, e não como diagnóstico.
- Exibir, no app e na ficha, um aviso de que o app não substitui avaliação
  clínica nem o serviço de urgência (SAMU).
- Não foi avaliado neste guia se a triagem se enquadra como software com
  finalidade médica sujeito a regulação sanitária. Essa pergunta deve ser
  levada aos mantenedores e ao responsável regulatório antes de publicar.

## 7. Trilhas de teste

O Play Console oferece quatro trilhas. A ordem recomendada é a seguinte:

| Ordem | Trilha | Para quê | Observação |
|-------|--------|----------|------------|
| 1 | Teste interno | Equipe de desenvolvimento e QA | Liberação rápida; limite de cerca de 100 testers (conferir) |
| 2 | Teste fechado | Grupo maior e controlado | Para conta pessoal nova, é a trilha que conta para a exigência de 12 testers por 14 dias (seção 1.1) |
| 3 | Teste aberto | Qualquer pessoa pode aderir | Opcional; em conta pessoal nova, só fica disponível depois do acesso à produção |
| 4 | Produção | Lançamento público | Usar rollout gradual |

O mesmo AAB pode ser promovido de uma trilha para a seguinte. Cada envio
precisa de um `versionCode` maior que o anterior (seção 2.2).

### 7.1 Como adicionar testadores

- **Teste interno e fechado:** em *Testes*, escolha a trilha e crie uma lista
  de testadores por e-mail (contas Google), ou associe um grupo do Google.
- Cada testador recebe um **link de adesão** e precisa aceitá-lo com a conta
  cadastrada. Na conta pessoal nova, ele deve permanecer inscrito durante os
  14 dias seguidos.
- Use somente contas de testadores reais e **nunca dado real de paciente**
  durante o teste. O app deve apontar para um ambiente de teste com seed
  sintético.

Os detalhes da tela mudam; confirmar no Play Console Help.

### 7.2 Rollout gradual (staged rollout)

Na produção, libere a versão para uma parcela dos usuários e aumente aos
poucos, acompanhando o Android vitals (seção de Pós-análise). Recomendação
deste guia: começar com uma parcela pequena (por exemplo, 10 a 20%), observar
travamentos e ANRs por alguns dias e só então ampliar. O Play Console permite
pausar o rollout se aparecer um problema. Os percentuais são uma sugestão e
não uma exigência do Google.

## 8. Particularidades por app

| App | Público | Distribuição sugerida neste guia |
|-----|---------|-----------------------------------|
| Paciente | Cidadão | Loja pública, candidato natural |
| ACS | Agentes comunitários de saúde | Avaliar distribuição privada |
| Admin | Gestão institucional | Avaliar distribuição privada |

### 8.1 Paciente

É o app destinado ao cidadão, então é o candidato à loja pública. É o que
mais exige da conformidade: CPF, data de nascimento, dados de saúde e
localização (seção 6), política de privacidade em URL pública e credenciais de
teste para o revisor.

### 8.2 ACS e Admin

São de uso institucional: o ACS é usado por agentes cadastrados (login com
matrícula e senha) e o Admin é um backoffice. Nenhum dos dois faz sentido como
app aberto ao público. O caminho a avaliar é a **distribuição privada pelo
Managed Google Play**, em que o app fica disponível apenas para a organização
que o gerencia. Pontos a verificar no Play Console Help:

- se a conta de desenvolvedor precisa ser de organização para publicar um app
  privado e que identificador da organização é necessário;
- se o app privado passa pelas mesmas verificações de política e de Data
  safety (a expectativa é que sim);
- quem administra os dispositivos da instituição e como eles receberão o app.

Observações do estado atual do repositório:

- O **ACS** guarda visitas no aparelho, com banco cifrado, e depende de
  backend e de broker MQTT acessíveis; sem produção, não há o que publicar.
- O **Admin** ainda roda sobre `MockAdminDataSource`, sem backend, e o login
  fica desativado em release (seção 6.3). Ele não deve ser publicado antes de
  ter um backend real.

## 9. Checklist final antes de enviar para revisão

Marque cada item e anote o app (Paciente, ACS ou Admin) a que se aplica.

**Build e assinatura**

- [ ] `applicationId` confirmado como definitivo (2.1)
- [ ] `version` no `pubspec.yaml` com `+n` maior que o último envio (2.2)
- [ ] Release assinado com a **upload key**, e não com a chave de debug (3.3)
- [ ] `key.properties` e `.jks` fora do Git (`git status` limpo) (3.2)
- [ ] AAB gerado com `flutter build appbundle --release` (4.1)
- [ ] Host de produção informado por `--dart-define`; sem `10.0.2.2` (2.5)
- [ ] `ENABLE_DEV_LOGIN` desligado no backend de produção (2.5)
- [ ] CA de desenvolvimento retirada do pacote, se não for necessária (2.5)
- [ ] Símbolos e `mapping.txt` guardados por versão (4.3 e 4.4)

**Manifest e permissões**

- [ ] Manifest mesclado do release conferido (2.6)
- [ ] `INTERNET` presente no release, se o app usa rede (2.4)
- [ ] `POST_NOTIFICATIONS` resolvida no Paciente (6.1)
- [ ] `RECEIVE_BOOT_COMPLETED` justificada ou removida (6.1)
- [ ] Nenhuma permissão sem uso (6.6)

**Ficha e conformidade**

- [ ] Título, descrições, capturas (com dados sintéticos) e feature graphic (5)
- [ ] Categoria, classificação IARC e público-alvo (5.3 a 5.5)
- [ ] Data safety separado por app e coerente com a auditoria LGPD (6.4)
- [ ] Política de privacidade em URL pública, informada no Console e no app (6.5)
- [ ] Declaração de apps de saúde preenchida (6.6)
- [ ] Aviso de que o app não substitui a urgência, no app e na ficha (6.6)
- [ ] `GOOGLE_MAPS_API_KEY` restrita por pacote e SHA-1 (6.2), no ACS
- [ ] Credenciais de teste fictícias e backend acessível ao revisor (6.3)

**Lançamento**

- [ ] Teste interno e fechado concluídos (7)
- [ ] Rollout gradual configurado (7.2)
- [ ] Nenhum segredo nem dado real de paciente em capturas, contas de teste ou
      neste documento

## 10. Referências

- [Play Console Help](https://support.google.com/googleplay/android-developer)
- [Requisitos de teste para contas pessoais novas](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Política de conteúdo e serviços de saúde](https://support.google.com/googleplay/android-developer/answer/16555673)
- [Flutter: Build and release an Android app](https://docs.flutter.dev/deployment/android)
- Documentos do repositório: `spec/lgpd_data_audit.md`, `spec/lgpd_design.md`,
  `backend/DEPLOY.md`, `docs/README.md`

## Pós-análise

Análise feita em 30/09/2026 sobre a `develop` (commit `6a66c1b`). Cada lacuna
indica como foi verificada: **código** (lido nos arquivos do repositório) ou
**documentação** (afirmado em `CLAUDE.md`, `AGENTS.md` ou `apps/CLAUDE.md` e
não reconferido no código).

### Lacunas do repositório que hoje impedem a publicação

| # | Lacuna | Verificação |
|---|--------|-------------|
| 1 | Release assinado com a chave de debug nos três apps (`signingConfig = signingConfigs.getByName("debug")`) | código |
| 2 | `INTERNET` não declarada no manifest `main` dos três apps; falta conferir o manifest mesclado | código |
| 3 | Paciente aponta por padrão para `https://10.0.2.2/` (`backend_config.dart`, linha 24); não há host de produção | código |
| 4 | Não existe deploy de produção do backend; `backend/DEPLOY.md` descreve só uma demo free-tier | documentação |
| 5 | Não foi encontrada URL pública de política de privacidade nem link para ela nos apps; há menções só em planos e especificações em `docs/superpowers/` (busca em `README.md`, `docs/`, `backend/DEPLOY.md` e `apps/*/lib`) | código |
| 6 | Admin roda sobre `MockAdminDataSource` (só o login é real, `auth.loginStaff`); sem credencial de staff o revisor não passa do login | código |
| 7 | Paciente pede `POST_NOTIFICATIONS` em execução e não a declara no manifest `main` | código |
| 8 | `RECEIVE_BOOT_COMPLETED` declarada no Paciente sem justificativa conhecida | código |
| 9 | Os três apps estão com `version: 1.0.0`, sem `+n` | código |
| 10 | Paciente e Admin sem ícone adaptativo (sem `mipmap-anydpi-v26`); o ACS não foi verificado | código |
| 11 | O Paciente tem uma única captura de tela no repositório e não há feature graphic | código |
| 12 | O CI não cobre release: o job `admin-android-build` compila só `flutter build apk --debug`, sem AAB, assinatura nem ofuscação (os demais jobs não foram lidos a fundo) | código |
| 13 | Senha do broker MQTT do ACS é constante de compilação (`SINALACS_MQTT_PASSWORD`), ou seja, fica embutida no binário distribuído | documentação |
| 14 | MFA e refresh token adiados; sem mTLS no broker | documentação |
| 15 | Data safety com pendências: conteúdo de `patients.emergencyContact`, canal de entrega do OTP e o que sai do aparelho na localização | código e auditoria |
| 16 | A auditoria LGPD registra ausência de rotina de expurgo de dados | documentação (título da seção 4.1) |
| 17 | Não foi decidido se a conta do Play será pessoal ou de organização, nem quem é o titular | decisão em aberto |
| 18 | Não foi avaliado se a triagem se enquadra em regulação sanitária de software | decisão em aberto |

Pontos positivos verificados: os três apps ignoram `key.properties`, `*.jks` e
`*.keystore` no Git; nenhum arquivo de segredo está versionado na pasta
`apps/acs/android`; a chave do Maps entra por `--dart-define` e não está no
repositório.

### Riscos de reprovação na revisão do Google

O Google não publica uma lista de motivos por app; os riscos abaixo são os
mais prováveis para o SinalACS.

- **Dados de saúde.** O app está no escopo da política de saúde: exige
  declaração de apps de saúde e política de privacidade em URL pública. Divergência entre Data safety,
  política e o que o app faz é motivo de rejeição.
- **Localização.** O Paciente declara localização precisa. A justificativa
  precisa ser clara, e a política deve dizer que o `locationHash` é
  pseudonimização, e não anonimização.
- **Login obrigatório sem conta de teste.** Paciente (CPF, nascimento e OTP),
  ACS (matrícula e senha) e Admin (login desativado em release) não dão ao
  revisor um caminho de entrada hoje.
- **App que parece quebrado.** Um release apontando para `10.0.2.2`, sem
  `INTERNET` no manifest ou sem backend acessível não funciona para o
  revisor.
- **Permissões sem uso.** `RECEIVE_BOOT_COMPLETED` no Paciente e, se o plugin
  não a adicionar, a falta de `POST_NOTIFICATIONS`.
- **Conteúdo médico.** Descrever a triagem como diagnóstico, ou omitir o aviso
  de que o app não substitui a urgência.

### Recomendação por app

| App | Recomendação | Justificativa |
|-----|--------------|---------------|
| Paciente | Loja pública, **mas não publicar ainda** | É o destinatário natural da loja pública, porém depende das lacunas 1 a 5, 7, 11 e 15, e de um backend de produção |
| ACS | Distribuição privada (Managed Google Play), **não publicar ainda** | Uso institucional; exige backend e broker de produção e uma decisão sobre a senha do broker embutida no binário (lacuna 13) |
| Admin | **Não publicar ainda** | Roda sobre dados mock, o login fica desativado em release e não há backend (lacunas 4 e 6) |

### Monitoramento pós-lançamento

- **Android vitals:** acompanhar taxas de ANR e de travamento no Play Console e
  usar o rollout gradual (seção 7.2) para pausar se passarem dos limites.
- **Pre-launch report:** o Play executa o app em aparelhos de teste ao enviar
  para as trilhas de teste. Como o login é obrigatório, o relatório só
  exercita o app se houver conta de teste (seção 6.3).
- **Avaliações dos usuários:** acompanhar e responder, sem pedir nem aceitar
  dado de saúde nos comentários.
- **Prazo de `targetSdk`:** o Google exige atualização anual do `targetSdk`
  dos apps. Hoje é 36. Conferir o prazo vigente no Play Console Help e fixar a
  mudança por PR, já que o valor é literal nos `build.gradle.kts`.

### Próximos passos (cada um como issue separada)

1. Configurar `signingConfigs` de release com `key.properties` nos três apps.
2. Adicionar um job de release ao CI (AAB, ofuscação, assinatura por segredo
   do repositório) e automatizar o envio com fastlane.
3. Declarar `INTERNET` e `POST_NOTIFICATIONS` no manifest `main` do Paciente e
   conferir o manifest mesclado; decidir sobre `RECEIVE_BOOT_COMPLETED`.
4. Criar e hospedar a política de privacidade (URL pública) e linká-la nos apps.
5. Provisionar backend e broker de produção e remover o host de desenvolvimento
   do release.
6. Definir o caminho de acesso do revisor do Google (contas fictícias).
7. Completar o Data safety por app, fechando as pendências da seção 6.4.
8. Produzir capturas do Paciente, feature graphic e ícone adaptativo.
9. Padronizar `version` com `+n` e documentar a regra de incremento.
10. Avaliar a senha do broker MQTT embutida no ACS.
11. Decidir conta pessoal ou de organização e o titular do Play Console.
12. Investigar o tamanho do AAB do Admin (47,6 MB).
13. Levar a pergunta de enquadramento regulatório aos mantenedores.