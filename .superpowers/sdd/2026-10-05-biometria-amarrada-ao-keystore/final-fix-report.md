# Fix wave final (2026-10-05)
- I-1: app.dart mostra "Tentar de novo" (resume_incomplete + resume_retry) após cancelled/lockedOut/unavailable com token guardado; 3 testes novos/ajustados em session_resume_test.dart.
- M-1: write() do AuthBoundSessionTokenStore engole falha do legacy.clear() após seal; teste novo.
- M-4: trap limpar restaura o PIN se --remover-bloqueio falhar entre clear e set-pin (bash -n ok).
- Suíte ACS: 519 testes verdes, flutter analyze limpo. PROGRESS.md: 516 -> 519; (a6) fechado.
