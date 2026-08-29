## 1. Stack Principal & Persistência

* **Frontend & Backend (Isomorfismo Dart):** Flutter no client e **Serverpod** no backend. O Serverpod gera o ORM e os *endpoints* do cliente Dart automaticamente, garantindo que qualquer alteração de esquema no PostgreSQL quebre a compilação do Flutter imediatamente.


* **Persistência Relacional:** PostgreSQL acoplado ao `sqflite` local. A escolha relacional reflete a necessidade estruturada da matriz de triagem fechada inspirada no Protocolo de Manchester.


* **Mensageria IoT:** Eclipse Mosquitto (MQTT) atua como *broker* de mensagens leve e de baixo consumo. Isso garante a entrega do botão de alerta de urgência do paciente para o ACS mesmo sob redes instáveis.


* **Estratégia Offline-First:** O download de cache territorial para a microárea utiliza `sqflite`. O aplicativo do ACS registra a visita offline e sincroniza em *background* assim que houver conectividade.



## 2. DX, Autenticação & Infraestrutura

* **IaC:** Pulumi (com TypeScript) para provisionar os containers em VPS robustas. Abstrai a infraestrutura como código com forte tipagem, sem o *vendor lock-in* do AWS CDK.
* **Autenticação na Borda:** Módulo de autenticação nativo do Serverpod acoplado ao **Traefik** como *Reverse Proxy/Edge Gateway*. O Traefik roteia tráfego REST/gRPC e os WebSockets do MQTT.
* **Login Fricção Zero:** A entrada *passwordless* por OTP ou QR Code no app do paciente é delegada à camada de aplicação.



## 3. Análise de Risco: O Elo Mais Fraco

A **Sincronização Bidirecional Offline-First** é o componente de maior risco arquitetônico neste MVTS.

* **Vendor Lock-in:** Soluções maduras de sincronização (como PowerSync) mitigam conflitos, mas introduzem forte dependência de fornecedor e custo atrelado à infraestrutura proprietária deles.
* **Custo de Escala:** Desenvolver um motor customizado `sqflite` <-> PostgreSQL exige manutenção constante e encarece as horas de engenharia a longo prazo.
* **Migração Técnica:** Se houver colisões frequentes de estado (ex: ACS registrando visitas offline que já foram alteradas na central), a migração futura exigirá refatoração pesada para modelos complexos de CRDTs (*Conflict-free Replicated Data Types*).

## 4. Docker-Compose MVTS

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: sinalacs_user
      POSTGRES_PASSWORD: strongpassword
      POSTGRES_DB: sinalacs_db
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sinalacs_user"]
      interval: 5s
      timeout: 5s
      retries: 5

  serverpod:
    build: ./backend
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8080:8080"

  mosquitto:
    image: eclipse-mosquitto:2
    volumes:
      - ./mosquitto.conf:/mosquitto/config/mosquitto.conf
    ports:
      - "1883:1883"

  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

volumes:
  pg_data:

```
