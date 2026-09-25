# Briefing — Slides de showcase do SinalACS

Tarefa atribuída a **@Rosialdo**. Este documento descreve o que o deck precisa
cobrir, com quais ferramentas e seguindo qual linguagem visual. O deck e seus
arquivos-fonte devem ser versionados nesta mesma pasta (`docs/showcase/`).

## Objetivo e público

Um deck de apresentação (showcase) que mostre **as telas dos três aplicativos
— Paciente, ACS e Admin — e o que cada uma faz**, contando a história do produto
do problema à solução.

- **Público:** banca/avaliadores, sponsor e parceiros da Atenção Primária à Saúde.
- **Formato:** 16:9, cerca de 15 a 18 slides, para uma fala de 10 a 12 minutos.
- **Tom:** o mesmo do [roteiro do vídeo ao sponsor](../roteiro-video-sponsor.md) —
  direto, honesto sobre o estágio de protótipo.

## Material que já existe (reaproveitar, não recriar)

| Material | Onde |
|---|---|
| Descrição de cada tela | [telas-paciente.md](../telas-paciente.md), [telas-acs.md](../telas-acs.md), [telas-admin.md](../telas-admin.md) |
| Capturas com dados sintéticos | [screenshots/](../screenshots/) (`acs/`, `admin/`, `patient/`) |
| Narrativa em blocos e guardrails | [roteiro-video-sponsor.md](../roteiro-video-sponsor.md) |
| Protótipos visuais em HTML | [spec/ui_acs/](../../spec/ui_acs/), [spec/ui_paciente/](../../spec/ui_paciente/) |
| Requisitos, JTBD e métricas | [spec/PRD_system.md](../../spec/PRD_system.md) |
| Arquitetura | [spec/stack.md](../../spec/stack.md) |
| Linguagem visual | [spec/ui_design.md](../../spec/ui_design.md) |
| Tokens de cor | `apps/patient/lib/app/patient_theme.dart`, `apps/acs/lib/app/acs_theme.dart`, `apps/admin/lib/app/admin_theme.dart` |

## Ferramentas de referência

**Recomendada — [Marp](https://marp.app/)** (Markdown → PDF/HTML/PPTX).
O deck vira texto versionável no git, com diff revisável na PR, e o tema é um
CSS com os tokens do projeto.

```bash
# preview com recarga automática
npx @marp-team/marp-cli -s docs/showcase/
# exportar
npx @marp-team/marp-cli docs/showcase/slides.md --theme docs/showcase/theme/sinalacs.css --allow-local-files --pdf
npx @marp-team/marp-cli docs/showcase/slides.md --theme docs/showcase/theme/sinalacs.css --allow-local-files --pptx
```

A extensão "Marp for VS Code" dá preview lado a lado.

**Alternativas aceitas:** Google Slides ou Canva, desde que o PDF exportado e o
link de edição fiquem registrados nesta pasta. Figma serve para compor mockups
antes de levá-los ao deck.

**Apoio:**
- Moldura de dispositivo: kit "Android device frames" do Figma Community ou
  [mockuphone.com](https://mockuphone.com/).
- Novas capturas: emulador conforme [android-avd.md](../android-avd.md), com
  `adb exec-out screencap -p > tela.png` ou `scrcpy`.
- Contraste: [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/).
- Ícones: Material Symbols ou Lucide (traço simples, sem emojis).

## Estrutura sugerida

| # | Slide | Conteúdo |
|---|---|---|
| 1 | Capa | SinalACS, tagline, equipe |
| 2 | O problema | Visitas do ACS sem priorização por risco na APS |
| 3 | A solução | Sinais clínicos estruturados → fila ranqueada por risco (modelo do Protocolo de Manchester, determinístico) |
| 4 | Arquitetura em um slide | 3 apps Flutter · backend Dart/Serverpod · Postgres · MQTT sobre TLS · Traefik |
| 5 | Paciente — Autenticação inclusiva | |
| 6 | Paciente — Alerta de urgência | Botão de emergência domina a hierarquia |
| 7 | Paciente — Triagem rápida | Perguntas estruturadas, classificação determinística |
| 8 | Paciente — Acompanhamento, lembretes e meus dados | |
| 9 | ACS — Login institucional | Indicador de operação offline |
| 10 | ACS — Territorialização | Microárea: o ACS só vê o próprio território |
| 11 | ACS — Fila de priorização | Vermelho/amarelo/verde; avisos técnicos em azul |
| 12 | ACS — Registro de visita offline | Fila local e sincronização |
| 13 | ACS — Acionamento e escalonamento | |
| 14 | Admin — Indicadores e microáreas | Painel e vínculo ACS ↔ microárea |
| 15 | Admin — Alertas, auditoria e layout responsivo | Celular, retrato/paisagem, tablet |
| 16 | Segurança e LGPD | Colunas clínicas criptografadas, restrição por microárea, trilha de auditoria |
| 17 | Estado atual e roadmap | Protótipo validado localmente; mapa, geofencing, SAMU e push como roadmap |
| 18 | Encerramento | Contato e repositório |

**Padrão de slide de tela (5 a 15):** captura em moldura de celular à esquerda;
à direita, o título com o nome da tela e até três bullets de funcionalidade; no
rodapé, uma etiqueta do app (Paciente, ACS ou Admin) na cor de destaque dele.
Uma tela por slide é o ideal — no máximo duas lado a lado.

## Design compatível com o projeto

Os apps usam tema escuro; o deck deve seguir a mesma base.

| Papel | Cor |
|---|---|
| Fundo | `#030712` |
| Superfície / superfície elevada | `#111827` / `#1F2937` |
| Borda | `#374151` |
| Texto principal (sugerido; os apps usam o branco do tema) | `#F9FAFB` |
| Destaque Paciente (preenchimento / texto) | `#0D9488` / `#2DD4BF` |
| Destaque ACS (preenchimento / texto) | `#2563EB` / `#60A5FA` |
| Destaque Admin (preenchimento / texto) | `#4F46E5` / `#818CF8` |
| Risco vermelho / amarelo / verde | `#DC2626` / `#F59E0B` / `#10B981` |

- **Vermelho, amarelo e verde são exclusivos da classificação de risco**
  ([spec/ui_design.md](../../spec/ui_design.md)). Não usar como decoração,
  realce de título ou aviso genérico. Quando vermelho aparecer como texto, usar
  `#F87171` (a variante `*OnSurface` dos apps).
- A cor de destaque de cada app identifica a seção dele (etiqueta, divisória,
  ícone), sem competir com as cores de risco.
- Tipografia **Inter** (a mesma do vídeo, `video/remotion/src/theme.ts`):
  títulos de 36 a 44 pt, corpo com no mínimo 20 pt.
- Contraste WCAG 2.2 AA para todo texto (4,5:1; 3:1 para texto grande) —
  referência: [spec/ux_accessibility_assessment.md](../../spec/ux_accessibility_assessment.md).
- Muito espaço em branco, uma ideia por slide, sem parágrafos longos.

## Regras obrigatórias

1. **Somente dados sintéticos.** Nenhum dado real de paciente, `.env`, token,
   senha ou string de conexão em nenhum slide ou captura.
2. **Seguir os [guardrails de veracidade](../roteiro-video-sponsor.md#guardrails-de-veracidade).**
   Mapa, rota, geofencing, SAMU e push são stubs: entram como roadmap, com selo,
   nunca como capacidade atual. Não mostrar em captura os controles listados
   ali como "não filmar".
3. **Métricas são alvos.** Números como redução ≥ 40 % no tempo até a visita
   são hipóteses do MVP — o slide deve trazer a palavra "alvo".
4. **Não afirmar que o alerta do paciente chega ao aparelho do ACS**; a
   formulação correta é "o alerta é registrado e enfileirado".

## Lacunas a cobrir

Hoje só existe uma captura do app Paciente. Antes de montar o deck:

- Capturar Paciente: autenticação, triagem, acompanhamento, lembretes e meus
  dados → `docs/screenshots/patient/`.
- Capturar ACS: acionamento, geofencing e avisos → `docs/screenshots/acs/`.
- Referenciar as novas capturas nos `docs/telas-*.md` correspondentes.

## Critérios de aceite

- [ ] Fonte editável versionada (`docs/showcase/slides.md` + `theme/sinalacs.css`,
      ou link de edição registrado nesta pasta).
- [ ] PDF exportado em `docs/showcase/sinalacs-showcase.pdf`.
- [ ] As três apps cobertas, cada tela com a legenda de suas funcionalidades.
- [ ] Paleta e tipografia conforme a seção de design; contraste AA conferido.
- [ ] Guardrails de veracidade e privacidade revisados slide a slide.
- [ ] Novas capturas adicionadas a `docs/screenshots/` e aos `docs/telas-*.md`.
- [ ] Link do deck adicionado ao [docs/README.md](../README.md).
