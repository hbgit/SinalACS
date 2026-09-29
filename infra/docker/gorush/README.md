# Gorush (RF14)

Relé de push open-source que mantém as conexões com o FCM (Android) e o APNs
(iOS). O backend entrega a lista de tokens e o Gorush faz o envio; a segmentação
é feita no PostgreSQL, nunca aqui.

Só sobe com o perfil `push`: `docker compose --profile push up`.

## O que a organização precisa fornecer

O Gorush é um relé, **não substitui** as credenciais dos provedores. Coloque em
`GORUSH_CREDENTIALS_DIR` (fora do repositório):

- `fcm-service-account.json` — conta de serviço do FCM (Android);
- `apns-key.p8` — chave de autenticação do APNs (iOS), com `GORUSH_IOS_KEY_ID` e
  `GORUSH_IOS_TEAM_ID` no `.env`.

Nada disso é versionado nem gerado por `bootstrap_env.sh`.

## Ligar o backend

No `.env`: `GORUSH_URL=http://gorush:8088`. Vazio desliga o envio: o backend sobe
normalmente e `notices.sendSegmented` recusa com uma mensagem clara.

O `config.yml` deste diretório usa a imagem `appleboy/gorush`; fixe a tag testada
no `docker-compose.yml` e confira os nomes das chaves no README dela.
