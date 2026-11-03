# Arquitetura

## 1. Visão geral

```
┌────────────────────┐        HTTPS/JSON         ┌──────────────────────────────────────────┐
│ App Flutter        │ ────────────────────────▶ │ API FastAPI (monólito modular)            │
│ (Android; iOS fut.)│ ◀──────────────────────── │  /api/v1                                  │
└────────────────────┘   JWT de acesso + refresh │                                           │
                                                 │  módulos de negócio ──▶ motor de análise  │
┌────────────────────┐                           │        │                     ▲            │
│ Site Next.js       │ ── (só p/ lista de        │        ▼                     │            │
│ (institucional)    │     interesse, se houver) │  PostgreSQL ◀── ferramentas da IA          │
└────────────────────┘                           │                     │                     │
                                                 │                     ▼                     │
                                                 │  integrations/ai ──▶ provedor LLM externo │
                                                 └──────────────────────────────────────────┘
```

- **Um único backend** (monólito modular). Nada de microsserviços.
- O app e o site **nunca** falam diretamente com o provedor de IA; as chaves ficam somente no backend.
- O site é estático/SSG na maior parte e só chama a API para a lista de interesse (opcional).

## 2. Estrutura do monorepositório

Estrutura alvo. Pastas são criadas **somente quando recebem código real**.

```
evofit/
├── apps/
│   ├── mobile/                 # Flutter
│   └── web/                    # Next.js
├── services/
│   └── api/                    # FastAPI
├── packages/
│   └── design-tokens/          # tokens de marca em JSON → gerados para Dart e CSS
├── docs/
├── scripts/                    # scripts de dev/teste (PowerShell + sh)
├── docker-compose.yml
├── .env.example
└── README.md
```

Ajustes em relação à proposta inicial (justificativas em `DECISIONS.md`):

- **Sem as pastas globais `models/ schemas/ repositories/ services/`** no backend: cada módulo contém as suas. Ter os dois padrões ao mesmo tempo gera ambiguidade e dependências cruzadas (ADR-003).
- `packages/api-contracts` **não** será um pacote separado no início: a fonte da verdade é o OpenAPI gerado pelo FastAPI. O cliente Dart é escrito à mão, com modelos tipados, e os testes de contrato comparam com o OpenAPI exportado (ADR-008).
- `packages/design-assets` vira `packages/design-tokens` (tokens compartilhados entre o app e o site). Assets binários ficam em cada app.
- `infrastructure/docker/` só será criada se houver mais de um Dockerfile/configuração; no início basta `docker-compose.yml` na raiz e `services/api/Dockerfile`.

## 3. Backend (`services/api`)

### 3.1 Camadas

```
app/
├── main.py                 # cria o FastAPI, registra os routers e handlers de erro
├── core/                   # config (pydantic-settings), segurança, erros, logging, paginação, tempo
├── db/                     # Base declarativa, engine/sessão, tipos comuns (UUID, timestamps)
├── api/v1/router.py        # agrega os routers dos módulos sob /api/v1
├── integrations/
│   └── ai/                 # camada de LLM desacoplada (ver AI_DESIGN.md)
└── modules/
    ├── auth/               ├── users/        ├── goals/
    ├── exercises/          ├── training/     ├── activities/
    ├── nutrition/          ├── body_metrics/ ├── analytics/   # motor de indicadores + Meu Corpo
    ├── ai_coach/           └── privacy/      # exportação e exclusão de dados (LGPD)
```

Estrutura interna de um módulo (só os arquivos necessários):

```
modules/training/
├── models.py       # ORM SQLAlchemy
├── schemas.py      # Pydantic (entrada/saída da API)
├── repository.py   # consultas — SEMPRE recebem user_id do contexto autenticado
├── service.py      # regras de negócio, transações
├── router.py       # endpoints finos: validação → service → schema de saída
└── rules.py        # (opcional) funções puras: cálculos e validações testáveis
```

Regras de dependência:

- `router → service → repository → models`. O router não acessa o banco diretamente.
- Um módulo usa outro **pela camada de serviço** (nunca importa o repositório do outro).
- `analytics` só lê (consome dados de `training`, `activities`, `body_metrics`, `nutrition`); não escreve nesses módulos.
- `ai_coach` usa `analytics` e os serviços de leitura através das **ferramentas** declaradas; alterações passam por `change_proposals`, aplicadas pelo serviço dono da entidade.
- Cálculos (`rules.py`, `analytics/*`) são funções puras sempre que possível, para facilitar os testes.

### 3.2 Decisões transversais

| Tema | Decisão |
|---|---|
| ORM | SQLAlchemy 2.x **síncrono** + psycopg 3. Endpoints `def` rodam no threadpool do FastAPI. Simples de testar; desempenho mais que suficiente (ADR-004). |
| IDs | UUID v7 gerado na aplicação (`uuid.uuid7()` do Python 3.14) — ordenável por tempo, sem expor contagem. |
| Datas | `timestamptz` em UTC no banco; o perfil guarda o fuso IANA (ex.: `America/Sao_Paulo`) para agregações “por dia/semana”. |
| Unidades | Armazenamento em SI: kg, metros, segundos, kcal, gramas. A conversão para a unidade preferida acontece no cliente. |
| Erros | Formato único (RFC 9457 *problem+json*): `type`, `title`, `status`, `detail`, `code`, `errors[]`. |
| Paginação | Cursor (`?cursor=&limit=`) em listas cronológicas; `limit` máximo de 100. |
| Autenticação | JWT de acesso curto (15 min) + refresh token opaco com rotação e detecção de reutilização (ADR-005). |
| Autorização | O `user_id` vem **sempre** do token. Toda consulta de repositório filtra por `user_id`. Recurso de outro usuário → `404` (não revela existência). |
| Config | `pydantic-settings` lendo variáveis de ambiente / `.env`; segredos nunca têm valor padrão em produção. |
| Logs | JSON estruturado com `request_id`; lista de campos proibidos (senha, tokens, textos livres de saúde, prompts completos). |
| Migrações | Alembic, uma migração por mudança de schema, revisadas manualmente (nada de autogenerate sem revisão). |
| Testes | pytest com PostgreSQL real (serviço `db-test` no Compose); transação revertida por teste. |

## 4. App mobile (`apps/mobile`)

```
lib/
├── main.dart
├── app/            # MaterialApp, roteamento (go_router), tema, injeção de providers raiz
├── core/           # cliente HTTP (dio + interceptors), armazenamento seguro, erros, formatação de unidades
├── shared/         # design system: tokens, componentes (EvoCard, EvoButton, estados vazio/erro/carregando)
└── features/<feature>/
    ├── data/         # DTOs + repositório que chama a API
    ├── domain/       # entidades e regras puras do cliente (ex.: cálculo de pace exibido)
    └── presentation/ # telas, widgets, controllers (Riverpod Notifier/AsyncNotifier)
```

- **Riverpod 3** para estado e injeção de dependências: os providers podem ser substituídos nos testes sem mocks globais (ADR-006).
- **go_router** com *shell route* para a navegação inferior e *redirect* baseado no estado de autenticação.
- **dio** com interceptors para: adicionar o token, renovar com refresh em caso de `401` (com fila para evitar renovações concorrentes) e mapear `problem+json` para erros tipados.
- **flutter_secure_storage** só para o refresh token. O access token fica em memória.
- **Persistência local**: na v1, apenas um rascunho da sessão de treino em andamento (para sobreviver ao fechamento do app). O modo *offline-first* completo fica fora do escopo e está documentado como evolução. Implementado na 2.9 (ADR-037): a última cópia do treino vinda da API mais a fila de séries ainda não enviadas, no armazenamento seguro do aparelho.
- A lógica de negócio fica fora dos widgets: os widgets observam controllers; os controllers chamam repositórios.

## 5. Site (`apps/web`)

- Next.js (App Router), TypeScript, Tailwind CSS 4 com tokens importados de `packages/design-tokens`.
- Páginas majoritariamente estáticas (SSG); metadados, `sitemap.xml` e `robots.txt` para SEO básico.
- Motion apenas em transições pontuais (hero, revelação de seções), respeitando `prefers-reduced-motion`.
- Mockups do app renderizados como componentes com dados **marcados como exemplo**.
- Lista de interesse (opcional): um endpoint `POST /api/v1/waitlist` com consentimento e *rate limit*; caso contrário, o CTA leva ao repositório/demo.

## 6. Modelo multimodal de atividades

Uma tabela base `activities` (usuário, modalidade, início, duração, origem, esforço percebido, notas) e **uma tabela de detalhes por modalidade** em relação 1:1 (*class table inheritance*):

- `strength` → a atividade aponta para a `workout_session` (exercícios/séries ficam nas tabelas de treino).
- `run` / `walk` → `endurance_details` (distância, elevação, FC média/máx, cadência — todas opcionais).
- `cycle` → `endurance_details` + `cycling_details` (potência média, se houver).
- `swim` → `endurance_details` + `swim_details` (tamanho da piscina, voltas, estilo).

Corrida, caminhada e ciclismo compartilham `endurance_details` porque têm as mesmas métricas principais; o que é exclusivo vai para uma tabela própria. Isso evita uma tabela com dezenas de colunas opcionais.

**Como adicionar uma modalidade nova:** (1) acrescentar o valor ao enum `activity_modality` (migração); (2) se houver métricas exclusivas, criar a tabela `<modalidade>_details`; (3) criar o schema Pydantic com validação própria (discriminado por `modality`); (4) registrar o calculador de indicadores da modalidade em `analytics`; (5) adicionar o formulário no app. Os módulos existentes não mudam.

## 7. Motor de análise e Meu Corpo

- `modules/analytics` expõe funções puras: `muscle_stimulus(sets, weights, period)`, `compare_periods(a, b)`, `personal_records(...)`, `endurance_trend(...)`, `consistency(...)`.
- A metodologia de estímulo é versionada (`methodology_version`) e parametrizada por configuração (ver `DATA_MODEL.md` §6).
- O app recebe para o Meu Corpo uma lista `{muscle_id, weighted_sets, band}`, e o **renderer** (SVG 2D hoje, GLB 3D no futuro) só mapeia `muscle_id → região visual`. Trocar o renderer não altera os cálculos (ADR-010).

## 8. Integrações externas (preparação)

Módulo `modules/integrations` (criado apenas quando a primeira integração for implementada). Cada integração implementa:

```
IntegrationProvider: authorize_url() · exchange_code() · refresh() · fetch_since(cursor) · map_to_activity()
```

Contrato comum para todas as integrações:

| Aspecto | Estratégia |
|---|---|
| Autenticação | OAuth 2.0 com PKCE quando suportado; tokens do provedor **criptografados** no banco (`external_connections`). |
| Permissões | Escopo mínimo de leitura; o usuário vê e revoga a conexão no Perfil. |
| Sincronização | Incremental por cursor/data, via webhook quando disponível, com *backoff* em `429`. |
| Duplicidade | `activities.source` + `external_id` com restrição única; deduplicação heurística (início ±2 min e duração ±5%) contra registros manuais, com confirmação do usuário. |
| Erros | Falhas não bloqueiam o app; o estado da conexão fica visível (`ok/erro/revogada`). |
| Privacidade | Importar só os campos usados; ao desconectar, perguntar se os dados importados devem ser apagados. |

Candidatas e particularidades:

- **Strava:** OAuth, limites de requisição por 15 min/dia, webhooks; termos restringem o uso dos dados com IA e por terceiros — **revisar os termos antes de implementar**.
- **Health Connect (Android):** acesso local no dispositivo via plugin Flutter; não passa por OAuth no backend; o app sincroniza com a API.
- **Wearables/GPS:** dependem de Health Connect ou de SDKs proprietários; GPS próprio exige serviço em primeiro plano e cuidados com bateria.
- **Catálogos nutricionais:** importação offline (TACO/Open Food Facts) para a tabela `foods`, com a origem registrada.
- **Exportação:** `GET /api/v1/me/export` (JSON) — também atende à LGPD.

## 9. Ambientes

| Ambiente | Banco | IA | Observação |
|---|---|---|---|
| `development` | Postgres no Compose | provedor `fake` por padrão; real se houver chave | `.env` local |
| `test` | `db-test` no Compose | sempre `fake` | CI e local |
| `production` | gerenciado (a definir) | real | **não configurado; nada de deploy sem aprovação** |
