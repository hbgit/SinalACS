# Política de Segurança

## Reportar uma vulnerabilidade

Relate vulnerabilidades de forma privada pelo recurso **Private Vulnerability
Reporting** deste repositório no GitHub. Não abra issues, pull requests ou
discussões públicas antes da coordenação com os mantenedores.

Inclua, quando disponível:

- Descrição clara da vulnerabilidade e do impacto potencial.
- Branch, commit, versão ou componente afetado.
- Passos de reprodução e uma prova de conceito não destrutiva.
- Condições necessárias para exploração e uma mitigação sugerida.

Não inclua dados reais de pacientes, credenciais, tokens, chaves, endereços,
identificadores ou outros dados pessoais. Caso o relato contenha informação
sensível por necessidade excepcional, reduza-a ao mínimo indispensável e
explique como os mantenedores podem reproduzir o problema sem retê-la.

## Escopo

Esta política abrange vulnerabilidades nos componentes versionados do SinalACS:

- Aplicativos em `apps/acs` e `apps/patient`.
- Backend em `backend` e seus clientes gerados.
- Infraestrutura, arquivos Docker Compose e configurações sob `infra`.
- Workflows de CI e dependências declaradas no repositório.

Relatos são bem-vindos inclusive para limitações já documentadas quando
apresentarem impacto novo, caminho de exploração ou bypass não conhecido.

Não estão no escopo desta política:

- Engenharia social, ataques de negação de serviço por volume ou testes que
  degradem a disponibilidade.
- Atividades contra serviços ou contas de terceiros fora do controle do projeto.
- Problemas restritos a ambientes locais de desenvolvimento ou ao piloto de
  demonstração, sem impacto adicional além das limitações já documentadas.
- Relatos sem impacto de segurança demonstrável.

## Suporte

O SinalACS está em fase de protótipo. Correções de segurança são consideradas
para a linha ativa do branch padrão e para a revisão mais recente dos branches
mantidos pelos responsáveis do projeto.

Releases históricas, builds locais e o caminho de deploy free-tier não possuem
garantia de correção. O ambiente de piloto não deve receber dados reais de
pacientes, conforme [backend/DEPLOY.md](../backend/DEPLOY.md).

## Coordenação e divulgação

Os mantenedores buscarão confirmar o recebimento de um relato em até cinco dias
úteis e manterão o pesquisador informado durante a triagem. A prioridade da
correção considera impacto, explorabilidade e exposição potencial de dados.

A divulgação é coordenada. O objetivo é disponibilizar correção ou mitigação e
um advisory em até 90 dias após o reporte; esse prazo pode ser antecipado ou
estendido por acordo, conforme o risco e a proteção de usuários. Não há prazo
fixo de correção.

Quando apropriado e com autorização do pesquisador, o reconhecimento poderá
constar no advisory ou nas notas de versão. O projeto não oferece recompensas
financeiras por relatos de vulnerabilidades.

## Pesquisa de boa-fé

O projeto considera pesquisa de boa-fé aquela feita para confirmar e comunicar
uma vulnerabilidade sem acessar ou exfiltrar dados, alterar ou destruir
informações, interromper serviços, manter persistência após a confirmação ou
testar contas e dispositivos de terceiros sem autorização.

Interrompa o teste e relate o problema se houver risco de acesso a dados de
saúde ou pessoais. Não use dados reais de pacientes para demonstrar impacto.

## Limites desta política

Esta política recebe vulnerabilidades técnicas; não substitui canais de
atendimento, urgência médica, privacidade ou resposta a incidentes. Um evento
real que envolva dados pessoais ou de saúde pode exigir medidas adicionais,
incluindo avaliação de obrigações legais e comunicação apropriada.

Os requisitos de privacidade, segurança e invariantes de domínio do projeto
estão descritos em [spec/lgpd_design.md](../spec/lgpd_design.md),
[spec/PRD_system.md](../spec/PRD_system.md) e [CLAUDE.md](../CLAUDE.md).