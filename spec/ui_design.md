As telas foram desenhadas com a filosofia Mobile-First, utilizando um container responsivo que simula a tela do celular e adapta-se centralizado em computadores desktop. Os componentes incluem estados de foco suave, microinterações de clique (active:scale) e o Dark Mode Nativo focado em economia de bateria e redução de fadiga visual.

# 📱 App do Paciente (MVP)

Focado em baixíssima fricção, contraste elevado e clareza na urgência. O "Botão de Emergência" domina a hierarquia visual.

# 🩺 App do ACS (Fila Dinâmica e Offline-first)

O design restringe completamente as cores de emergência (Vermelho, Amarelo, Verde) ao ranqueamento clínico determinístico. O container é um pouco mais largo (max-w-2xl) para acomodar dados de triagem mantendo a estrutura UI de aplicativo.

## Atualizações de Design e Decisões de Produto (Pós-Auditoria de UX)

* **Containers e Largura (max-w-2xl) (§1.1 e §3.4):** Fica decidido que o uso do `ConstrainedBox` com `Center` aplica-se **exclusivamente à tela de Login**. Telas pós-login, incluindo o formulário de Visita do ACS, não possuem restrição de largura máxima, estendendo-se de borda a borda. A menção ao `max-w-2xl` neste documento é revogada para as telas pós-login mobile.
* **Dark Mode (§1.2):** Fica documentado explicitamente que a definição `brightness: Brightness.dark` nos temas é **fixa e permanente**. O app não reage às preferências de modo claro/escuro do Sistema Operacional. 
* **Microinterações (§1.4):** Registra-se a equivalência intencional: o efeito de *ripple* nativo do Material 3 é o equivalente adotado no Flutter para a microinteração descrita nos protótipos como `active:scale`.
* **Exceção de Cor (§3.1):** O uso da cor verde (`AcsColors.green`) no botão/texto de "Local alcançado" (geofencing) é uma **exceção documentada** à restrição clínica. O verde atua aqui como status operacional universal ("liberado") e não entra em conflito cognitivo com o risco clínico.
* **Fricção do Fluxo de Emergência (§2.1):** Define-se como limiar quantitativo no PRD: o fluxo de acionamento do Botão de Emergência do Paciente deve custar **no máximo 4 toques** e durar **no máximo 10 segundos** em condições normais de rede.
