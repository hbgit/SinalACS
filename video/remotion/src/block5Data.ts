// GERADO por video/rpc_demo/captured/gen_block5_data.py — não editar à mão.
// Fonte: video/rpc_demo/captured/{cycle,mqtt}.txt, saída de uma execução
// real de bin/red_alert_cycle.dart contra a stack do docker compose.

export const cycleLines: string[] = [
  "SinalACS — ciclo do alerta vermelho",
  "servidor: http://localhost:8080/   (Serverpod RPC)",
  "",
  "[1/5] Saúde da stack",
  "    ✓ status: ok",
  "      banco: true",
  "      broker MQTT: true",
  "",
  "[2/5] Autenticação de desenvolvimento (paciente)",
  "    ✓ token: Bearer eyJhbGci…mC1k",
  "      (truncado de propósito — nunca exibir o token inteiro)",
  "",
  "[3/5] alerts.createRedAlert",
  "      idempotencyKey: video-demo-1789069185765",
  "    ✓ alertId: d532ec44-2739-43f9-9811-b95e33dfa071",
  "    ✓ status: pending",
  "    ✓ published: true",
  "      gravado em transação e publicado no tópico MQTT da microárea",
  "",
  "[4/5] Reenvio com a MESMA chave — prova de idempotência",
  "    ✓ alertId: d532ec44-2739-43f9-9811-b95e33dfa071",
  "      mesmo alertId — nenhum alerta duplicado",
  "",
  "[5/5] alerts.acknowledge (pelo ACS)",
  "    ✓ acknowledged: true",
  "    ✓ status: acknowledged",
  "",
  "  Alerta vermelho não se perde em silêncio."
];

export const mqttTopic = "sinalacs/v1/microareas/00000000-0000-4000-8000-000000000003/alerts";

export const mqttPayload = "{\n  \"version\": 1,\n  \"alert_id\": \"d532ec44-2739-43f9-9811-b95e33dfa071\",\n  \"patient_id\": \"00000000-0000-4000-8000-000000000001\",\n  \"micro_area_id\": \"00000000-0000-4000-8000-000000000003\",\n  \"risk_level\": \"red\",\n  \"location_hash\": \"hash-sintetico-microarea-12\",\n  \"triggered_at\": \"2026-09-10T19:39:45.769049Z\"\n}";
