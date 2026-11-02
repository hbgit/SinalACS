# Mudanças de código recomendadas — não implementadas neste plano

Mudanças necessárias para alinhar os apps e o backend ao escopo educativo e
aberto ([`spec/escopo_projeto.md`](../../spec/escopo_projeto.md)). Este
documento só as registra; a implementação é um plano próprio. Os IDs são
estáveis: nunca renumerar.

## Portão do piloto — segurança e legal

- C-01 — Texto legal do app do paciente: controlador, encarregado e aviso educativo
- C-02 — Aviso educativo na primeira abertura e em "Sobre"
- C-04 — Pedido de contato sem rótulo de urgência e saída "Ligar 192" sem envio
- C-05 — Acesso do participante sem CPF e sem SMS (RF24)
- C-06 — "UBS" nos textos dos apps
- C-08 — Autoavaliação com três saídas
- C-10 — "Apagar meus dados" e retenção local de 30 dias

## Portão do piloto — funcional

- C-03 — Biblioteca de conteúdo educativo offline (obrigatória se o pilar A estiver no piloto)

## Demais

- C-07 — Discagem só para 192 no app do agente
- C-09 — "Manchester" em código
