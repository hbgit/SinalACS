# Trabalhos futuros

> Conteúdo educativo. Não substitui atendimento profissional. Emergência: ligue 192.

**Nada aqui é pré-requisito do piloto.** Este documento reúne o que depende de
vínculo com instituições de saúde, de sistemas oficiais ou de serviços pagos e
por isso fica fora do escopo atual ([`escopo_projeto.md`](escopo_projeto.md)).
Cada item só volta ao escopo com decisão da equipe e, quando houver, com o
acordo institucional correspondente.

## Integrações com serviços de saúde

| Integração | O que faria | Pré-condição institucional | Requisito relacionado |
|---|---|---|---|
| e-SUS APS | Exportar ou consultar registros de visitas da Atenção Primária | Acordo com o município ou com a Secretaria de Saúde responsável | RF11, RF15 |
| CNES | Identificar unidades e equipes de saúde reais no lugar dos grupos do piloto | Uso de cadastro oficial e vínculo com a unidade | RF08, modelo `ubs` |
| CNS/CADSUS | Identificar pacientes e profissionais pelo Cartão Nacional de Saúde | Acesso autorizado ao barramento do SUS | RF01, RF07 |
| RNDS | Trocar dados clínicos com a Rede Nacional de Dados em Saúde | Credenciamento junto ao Ministério da Saúde | RF15, RF17 |
| Gov.br | Login de profissionais e cidadãos pela conta Gov.br | Adesão ao Login Único | RF01, RF07 |
| SAMU | Encaminhar casos ao serviço de urgência pelo sistema, além da discagem para 192 | Acordo com a central de regulação | RF13 |
| UBS / Secretaria de Saúde | Operar o SinalACS dentro de uma unidade, com ACS em exercício e coordenação da unidade | Termo de cooperação; definição de controlador e operador | RF03 como alerta, RF13, RF19 |

## Funções que dependem de operação em serviço

- **RF01 com CPF e SMS:** login do paciente por CPF + data de nascimento + OTP
  por SMS; exige gateway pago e justificativa de coleta do CPF.
- **RF12 (geofencing):** exige política de localização em segundo plano na
  loja de aplicativos.
- **RF13 (escalonamento para SAMU/UBS pelo sistema).**
- **Hipóteses H1 e H3 do PRD:** tempo de priorização comparado ao modelo atual
  de uma UBS e concordância com avaliação médica.
- **Métricas de visitas por ACS por dia** e de aderência à classificação.
- **Coordenação por UBS** no backoffice.
- **Validação clínica do motor de autoavaliação** por profissionais de saúde,
  condição para qualquer uso como classificação de risco.

## Distribuição e infraestrutura de produção

- Publicação na Play Store (conta de desenvolvedor paga); ver
  [`docs/publicacao-google-play.md`](../docs/publicacao-google-play.md).
- Infraestrutura como código com Pulumi e redes privadas.
- PKI de produção dos certificados por aparelho (#118).
- Chave do certificado do aparelho no TEE (#116).
- Separação de papéis do banco para a trilha de auditoria (#96).
- iOS.

## Próximos planos

Não são integrações, mas ficam registrados aqui para não se perderem:

1. **Material para o Comitê de Ética em Pesquisa:** minuta de TCLE e projeto
   para a Plataforma Brasil. É a pendência de maior prazo (P-04); o conteúdo
   institucional fica `[A DEFINIR]`.
2. **Implementação do portão de código** C-01–C-08 e C-10
   ([`docs/escopo/mudancas-de-codigo-recomendadas.md`](../docs/escopo/mudancas-de-codigo-recomendadas.md)).
