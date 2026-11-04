# Issue #136: comentários a publicar depois do merge da Fase 1

Estes textos só vão ao GitHub depois de dois passos: o merge da PR da Fase 1 em `develop` e a aprovação do dono do texto final. Publicar com `gh issue comment <n> --body-file <arquivo>`, exatamente como aprovado.

---

## #128 (C-05): requisitos do PIN vindos da #136

A Fase 2 da #136 (cifra local liberada pelo PIN no pilar B) depende desta issue. A decisão D3 do plano da #136 (`docs/superpowers/plans/2026-11-03-issue-136-cifra-local-paciente.md`) traz dois requisitos para o PIN:

- **Tamanho:** 6 dígitos ou mais.
- **Lista de PINs proibidos:** um só dígito repetido (`000000`, `111111`, …), sequências crescentes e decrescentes (`123456`, `987654`, …) e alternância de dois dígitos (`121212`, …).

**Risco residual, aceito pelo dono do projeto em 2026-11-04.** Com o aparelho em mãos **e root**, o atacante lê o envelope da chave e usa a chave do Keystore, que não exige autenticação. A partir daí a força bruta do PIN roda fora do aparelho, e o bloqueio por tentativas desta issue não a impede. Ordem de grandeza: um PIN de 4 dígitos cai em minutos; um de 6, em horas. O PIN de 6 dígitos encarece o ataque, mas não o impede. Os dados do pilar B ficam no servidor, a C-12 invalida a sessão e a C-10 expira o que fica no aparelho.

**Evolução registrada:** exigir autenticação do sistema na chave (`setUserAuthenticationRequired`) quando o aparelho tiver bloqueio de tela.

O risco residual também está registrado em `spec/lgpd_design.md` §0.

---

## #125 (C-02): aviso de proteção local na tela "Sobre"

A #136 criou o widget `LocalProtectionNotice` (`apps/patient/lib/app/local_protection_notice.dart`). Ele traz o limite da cifra local do pilar A: o que o app guarda no celular fica cifrado, o que protege contra cópia dos arquivos, mas não contra quem usa o celular desbloqueado.

Hoje o aviso aparece na tela de lembretes e em "Meus Dados". Quando a tela "Sobre" desta issue existir, ela deve reaproveitar o mesmo widget, em vez de repetir o texto.

---

## #131 (C-10): "Apagar meus dados" e o banco cifrado da #136

A #136 entregou o banco local cifrado do app do paciente (`PatientLocalDatabase`, `apps/patient/lib/core/storage/patient_local_database.dart`). Para esta issue:

- **Apagar:** "Apagar meus dados" deve chamar `PatientLocalDatabase.deleteEverything()`. Esse método fecha o banco, apaga o arquivo e os laterais, apaga os arquivos antigos em claro e destrói a chave no Keystore. Hoje ele já é usado pelo "Apagar e recomeçar" da tela de lembretes. Depois de chamá-lo, cancele as notificações agendadas, como faz `_resetLocalData` em `app.dart`.
- **Aviso:** acrescente ao `LocalProtectionNotice` a frase da mitigação (expiração em 30 dias e "Apagar meus dados"). Ela ficou de fora de propósito, porque o app não pode prometer o que ainda não existe.
- **Documentação:** em `spec/lgpd_design.md` §0, a mitigação está marcada como meta que depende desta issue. Atualize o texto quando ela for entregue.
- **Corrida conhecida:** um `deleteEverything()` que entra na fila atrás de uma abertura em andamento fecha o banco que essa abertura acabou de devolver. Quem o usar recebe `database_closed`. O comportamento está documentado no método e foi aceito para o "Apagar e recomeçar"; vale revisitá-lo aqui.

---

## #136: proposta de nova redação do critério de aceite

O critério de aceite diz "Banco local com dado de saúde cifrado (AES-256)". Na Fase 1, o app ainda não gravava nenhum dado de saúde no aparelho: a autoavaliação vai ao servidor e não é guardada localmente, e a trilha local de eventos só nasce na C-04 (#127). O critério foi cumprido assim:

- pela **infraestrutura**, um único banco SQLCipher com chave raw de 256 bits guardada pelo Keystore, que passa a receber os dados de saúde quando a C-04 e a C-11 os criarem;
- pelos **lembretes**, cujo texto livre pode citar medicamento, e pelo **consentimento local**, que saíram de dois arquivos SQLite em claro e foram migrados para o banco cifrado.

**Redação proposta:**

> - [ ] Banco local cifrado (AES-256) pronto para receber dado de saúde, com chave no Keystore no pilar A e liberada pelo PIN no pilar B; lembretes e consentimento local migrados para ele.

Fica como proposta. O corpo da issue não foi editado, para preservar o critério original no histórico.
