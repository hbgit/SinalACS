# Log da aplicação da classificação das issues

Documento aprovado: `docs/escopo/classificacao-issues.md`, hash `0da96bf382263fd6b81637940a2582c47411c30d`.

As duas linhas do lote `milestones` foram normalizadas à mão depois da execução: a saída da API (JSON da milestone criada) não cabia na tabela. O estado real das milestones foi conferido por `gh api` e bate com o registrado.

| Data e hora | Lote | Comando | Resultado |
|---|---|---|---|
| 2026-11-02 11:55:33 | rotulos | `gh label create futuro --color BFD4F2 --description …` | ok |
| 2026-11-02 11:55:33 | rotulos | `gh label create a-decidir --color FBCA04 --description …` | ok |
| 2026-11-02 11:55:34 | rotulos | `gh label create acao-equipe --color C5DEF5 --description …` | ok |
| 2026-11-02 11:55:52 | milestones | `gh api -X POST repos/hbgit/SinalACS/milestones -f title=Pilot -f description=…` | milestone Pilot criada, due_on null |
| 2026-11-02 11:55:53 | milestones | `gh api -X POST repos/hbgit/SinalACS/milestones -f title=v1.0 -f description=…` | milestone v1.0 criada, due_on null |
| 2026-11-02 11:56:42 | existentes | `gh issue edit 118 --add-label futuro` | https://github.com/hbgit/SinalACS/issues/118 |
| 2026-11-02 11:56:45 | existentes | `gh issue edit 117 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/117 |
| 2026-11-02 11:56:48 | existentes | `gh issue edit 116 --add-label futuro` | https://github.com/hbgit/SinalACS/issues/116 |
| 2026-11-02 11:56:51 | existentes | `gh issue edit 114 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/114 |
| 2026-11-02 11:56:54 | existentes | `gh issue edit 111 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/111 |
| 2026-11-02 11:56:58 | existentes | `gh issue edit 103 --milestone v1.0` | https://github.com/hbgit/SinalACS/issues/103 |
| 2026-11-02 11:57:00 | existentes | `gh issue edit 102 --milestone v1.0` | https://github.com/hbgit/SinalACS/issues/102 |
| 2026-11-02 11:57:02 | existentes | `gh issue edit 101 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/101 |
| 2026-11-02 11:57:05 | existentes | `gh issue edit 100 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/100 |
| 2026-11-02 11:57:08 | existentes | `gh issue edit 99 --milestone v1.0` | https://github.com/hbgit/SinalACS/issues/99 |
| 2026-11-02 11:57:10 | existentes | `gh issue edit 96 --add-label a-decidir` | https://github.com/hbgit/SinalACS/issues/96 |
| 2026-11-02 11:57:13 | existentes | `gh issue edit 94 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/94 |
| 2026-11-02 11:57:16 | existentes | `gh issue edit 90 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/90 |
| 2026-11-02 11:57:18 | existentes | `gh issue edit 88 --milestone v1.0` | https://github.com/hbgit/SinalACS/issues/88 |
| 2026-11-02 11:57:22 | existentes | `gh issue edit 87 --milestone v1.0` | https://github.com/hbgit/SinalACS/issues/87 |
| 2026-11-02 11:57:26 | existentes | `gh issue edit 86 --milestone v1.0` | https://github.com/hbgit/SinalACS/issues/86 |
| 2026-11-02 11:57:29 | existentes | `gh issue edit 83 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/83 |
| 2026-11-02 11:57:31 | existentes | `gh issue edit 81 --milestone Pilot` | https://github.com/hbgit/SinalACS/issues/81 |
| 2026-11-02 11:57:34 | existentes | `gh issue edit 77 --add-label futuro` | https://github.com/hbgit/SinalACS/issues/77 |
| 2026-11-02 11:57:38 | existentes | `gh issue edit 15 --add-label futuro` | https://github.com/hbgit/SinalACS/issues/15 |
| 2026-11-02 11:57:56 | reescritas | `gh issue edit 118 --body-file …/corpo-118.md --title 'PKI de produção da CA de aparelhos (escopo 5 da #94)'` | https://github.com/hbgit/SinalACS/issues/118 |
| 2026-11-02 11:57:58 | reescritas | `gh issue comment 118 --body-file …/comentario-118.md` | https://github.com/hbgit/SinalACS/issues/118#issuecomment-6581704553 |
| 2026-11-02 11:58:00 | reescritas | `gh issue comment 116 --body-file …/comentario-116.md` | https://github.com/hbgit/SinalACS/issues/116#issuecomment-6581705308 |
| 2026-11-02 11:58:03 | reescritas | `gh issue edit 102 --body-file …/corpo-102.md` | https://github.com/hbgit/SinalACS/issues/102 |
| 2026-11-02 11:58:05 | reescritas | `gh issue comment 102 --body-file …/comentario-102.md` | https://github.com/hbgit/SinalACS/issues/102#issuecomment-6581707193 |
| 2026-11-02 11:58:07 | reescritas | `gh issue comment 96 --body-file …/comentario-96.md` | https://github.com/hbgit/SinalACS/issues/96#issuecomment-6581707808 |
| 2026-11-02 11:58:09 | reescritas | `gh issue edit 87 --body-file …/corpo-87.md` | https://github.com/hbgit/SinalACS/issues/87 |
| 2026-11-02 11:58:11 | reescritas | `gh issue comment 87 --body-file …/comentario-87.md` | https://github.com/hbgit/SinalACS/issues/87#issuecomment-6581709442 |
| 2026-11-02 11:58:13 | reescritas | `gh issue edit 77 --body-file …/corpo-77.md --title 'Envio do OTP por SMS real (RF01)'` | https://github.com/hbgit/SinalACS/issues/77 |
| 2026-11-02 11:58:15 | reescritas | `gh issue comment 77 --body-file …/comentario-77.md` | https://github.com/hbgit/SinalACS/issues/77#issuecomment-6581711069 |
| 2026-11-02 11:58:16 | reescritas | `gh issue comment 15 --body-file …/comentario-15.md` | https://github.com/hbgit/SinalACS/issues/15#issuecomment-6581711691 |
| 2026-11-02 11:58:43 | novas | `gh issue create --title '[C-01] Texto legal do app do paciente: controlador, encarregado e aviso educativo' --body-file …/nova-N1.md --milestone Pilot --label privacy` | https://github.com/hbgit/SinalACS/issues/124 |
| 2026-11-02 11:58:47 | novas | `gh issue create --title '[C-02] Aviso educativo na primeira abertura e em "Sobre"' --body-file …/nova-N2.md --milestone Pilot --label enhancement` | https://github.com/hbgit/SinalACS/issues/125 |
| 2026-11-02 11:58:51 | novas | `gh issue create --title '[C-03] Biblioteca de conteúdo educativo offline (pilar A)' --body-file …/nova-N3.md --milestone Pilot --label enhancement` | https://github.com/hbgit/SinalACS/issues/126 |
| 2026-11-02 11:58:56 | novas | `gh issue create --title '[C-04] Pedido de contato sem rótulo de urgência e saída "Ligar 192" sem envio' --body-file …/nova-N4.md --milestone Pilot --label enhancement` | https://github.com/hbgit/SinalACS/issues/127 |
| 2026-11-02 11:58:59 | novas | `gh issue create --title '[C-05] Acesso do participante sem CPF, SMS ou e-mail (RF24)' --body-file …/nova-N5.md --milestone Pilot --label privacy` | https://github.com/hbgit/SinalACS/issues/128 |
| 2026-11-02 11:59:09 | novas | `gh issue create --title '[C-06] Trocar "UBS" nos textos dos apps por grupo e coordenação do piloto' --body-file …/nova-N6.md --milestone Pilot --label enhancement` | https://github.com/hbgit/SinalACS/issues/129 |
| 2026-11-02 11:59:14 | novas | `gh issue create --title '[C-08] Autoavaliação com três saídas, sem classificação de risco' --body-file …/nova-N7.md --milestone Pilot --label enhancement` | https://github.com/hbgit/SinalACS/issues/130 |
| 2026-11-02 11:59:18 | novas | `gh issue create --title '[C-10] "Apagar meus dados" e retenção local de 30 dias' --body-file …/nova-N8.md --milestone Pilot --label privacy` | https://github.com/hbgit/SinalACS/issues/131 |
| 2026-11-02 11:59:21 | novas | `gh issue create --title '[C-11] Autoavaliação local no pilar A, sem sessão nem registro no servidor' --body-file …/nova-N9.md --milestone Pilot --label privacy` | https://github.com/hbgit/SinalACS/issues/132 |
| 2026-11-02 11:59:25 | novas | `gh issue create --title '[C-12] Recuperação de acesso que invalida a credencial do aparelho anterior' --body-file …/nova-N10.md --milestone Pilot --label security` | https://github.com/hbgit/SinalACS/issues/133 |
| 2026-11-02 11:59:30 | novas | `gh issue create --title '[RNF07] APK assinado publicado em GitHub Releases' --body-file …/nova-N11.md --milestone Pilot --label enhancement` | https://github.com/hbgit/SinalACS/issues/134 |
| 2026-11-02 11:59:34 | novas | `gh issue create --title '[RNF07] Compose do piloto: um host, Let'"'"'s Encrypt e documentação única' --body-file …/nova-N12.md --milestone Pilot --label documentation` | https://github.com/hbgit/SinalACS/issues/135 |
| 2026-11-02 11:59:38 | novas | `gh issue create --title '[RNF03] Cifra local dos dados do app do paciente com PIN' --body-file …/nova-N13.md --milestone Pilot --label privacy` | https://github.com/hbgit/SinalACS/issues/136 |
| 2026-11-02 11:59:42 | novas | `gh issue create --title '[RNF05] Acessibilidade WCAG AA dos fluxos do piloto no app do paciente' --body-file …/nova-N14.md --milestone Pilot --label accessibility` | https://github.com/hbgit/SinalACS/issues/137 |
| 2026-11-02 11:59:45 | novas | `gh issue create --title '[C-07] Discagem só para 192 no app do agente' --body-file …/nova-N15.md --milestone v1.0 --label enhancement` | https://github.com/hbgit/SinalACS/issues/138 |
| 2026-11-02 11:59:51 | novas | `gh issue create --title '[C-09] Remover "Manchester" do código e do roteiro de vídeo' --body-file …/nova-N16.md --milestone v1.0 --label documentation` | https://github.com/hbgit/SinalACS/issues/139 |
| 2026-11-02 11:59:54 | novas | `gh issue create --title '[C-06b] Renomear a tabela ubs para grupo do piloto (migração)' --body-file …/nova-N17.md --milestone v1.0 --label enhancement` | https://github.com/hbgit/SinalACS/issues/140 |
| 2026-11-02 11:59:58 | novas | `gh issue create --title '[Ação P-02] Contato com o encarregado de dados da UFRR' --body-file …/nova-N18.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/141 |
| 2026-11-02 12:00:02 | novas | `gh issue create --title '[Ação P-03] Confirmação com a coordenação do PET-Saúde' --body-file …/nova-N19.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/142 |
| 2026-11-02 12:00:07 | novas | `gh issue create --title '[Ação P-04] Submissão na Plataforma Brasil' --body-file …/nova-N20.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/143 |
| 2026-11-02 12:00:12 | novas | `gh issue create --title '[Ação P-05] Definição do território com o PET-Saúde' --body-file …/nova-N21.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/144 |
| 2026-11-02 12:00:16 | novas | `gh issue create --title '[Ação P-07] Lista de temas e revisores do conteúdo educativo' --body-file …/nova-N22.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/145 |
| 2026-11-02 12:00:20 | novas | `gh issue create --title '[Ação P-11] Pedido de parecer à Procuradoria Federal junto à UFRR' --body-file …/nova-N23.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/146 |
| 2026-11-02 12:00:24 | novas | `gh issue create --title '[Ação P-12] Instrumentos dos questionários e serviço de aplicação' --body-file …/nova-N24.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/147 |
| 2026-11-02 12:00:27 | novas | `gh issue create --title '[Ação P-13] Custódia do repositório e da chave de assinatura do APK' --body-file …/nova-N25.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/148 |
| 2026-11-02 12:00:32 | novas | `gh issue create --title '[Ação P-14] Decidir se o pilar B entra no piloto' --body-file …/nova-N26.md --milestone Pilot --label acao-equipe` | https://github.com/hbgit/SinalACS/issues/149 |
