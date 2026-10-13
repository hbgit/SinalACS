# Tarefa 7v - relatório
Ver a seção "Tarefa 7v" em docs/superpowers/plans/2026-10-12-issue-56-evidencias.md.
Resultado: A 0/5 quedas, reconectou 5/5; C 0/3 quedas, reconectou 3/3; B 0/3 quedas, reconectou 3/3.
StartedAt constante (2026-10-13T01:09:36Z), RestartCount 0, exit 0, sem crash.log, stderr só tipo+errno (32 em A, 104 em C), sem vazamento de host/ip/porta.
Notas: a primeira tentativa de execução em lote falhou por erro meu de shell (zsh sem word splitting), sem rodar cenários; refeita. `compose up -d` do trap reexecuta os seeds (inofensivo).
