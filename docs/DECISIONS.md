# Registro de decisões arquiteturais (ADR)

Formato curto: contexto → decisão → consequências. Status: **Aceita** (padrão seguro e reversível, já adotado), **Proposta** (aguarda sua confirmação) ou **Substituída**.

---

### ADR-001 — Monorepo em `desck/evofit/`, separado do Flutter SDK
**Status:** Aceita · 2026-10-28
**Contexto:** `desck/` contém um clone do Flutter SDK (com `.git` próprio) que está no `PATH`.
**Decisão:** criar o projeto em `desck/evofit/` com um repositório Git próprio. O SDK não é versionado nem modificado.
**Consequências:** nenhum risco de `flutter create`, formatadores ou `git add` atingirem o SDK. Se você preferir mover o SDK para fora de `Documents` (ex.: `C:\dev\flutter`), basta atualizar o `PATH`.

### ADR-002 — Monólito modular em FastAPI
**Status:** Aceita
**Decisão:** um único serviço Python dividido em módulos de negócio com fronteiras explícitas (serviços públicos por módulo).
**Consequências:** deploy, testes e transações simples. Um módulo pode ser extraído no futuro se houver necessidade real.

### ADR-003 — Módulos verticais em vez de camadas globais
**Status:** Aceita
**Contexto:** a estrutura sugerida tinha `models/ schemas/ repositories/ services/` globais **e** `modules/`.
**Decisão:** cada módulo contém `models/schemas/repository/service/router`. Ficam globais apenas `core/`, `db/` e `integrations/`.
**Consequências:** coesão por domínio; evita o "arquivo gigante de models" e importações circulares.

### ADR-004 — SQLAlchemy 2.x síncrono + psycopg 3
**Status:** Aceita
**Alternativa:** async com asyncpg.
**Decisão:** síncrono. A carga de um TCC não justifica a complexidade adicional do async (sessões, lazy loading, fixtures). As chamadas lentas ao LLM ficam isoladas e usam `httpx` com timeout.
**Consequências:** testes mais simples. A migração para async é possível depois, módulo a módulo.

### ADR-005 — Autenticação própria com JWT curto + refresh rotativo
**Status:** Aceita
**Decisão:** senha com **Argon2id**; access token JWT (HS256, 15 min, `sub=user_id`, `jti`); refresh token opaco aleatório (256 bits) guardado como hash SHA-256 em `refresh_tokens`, válido por 30 dias, **rotacionado a cada uso**. Reutilização de um token já rotacionado revoga toda a família (indica roubo). Logout revoga a família.
**Alternativas:** Auth0/Firebase/Supabase Auth — adicionam dependência externa e custo, e escondem um ponto que vale a pena demonstrar no TCC.
**Consequências:** precisamos testar bem: expiração, rotação, reutilização e *rate limit* de login.

### ADR-006 — Riverpod 3 + go_router + dio no app
**Status:** Aceita
**Decisão:** Riverpod para estado e DI (substituição de providers em testes, `AsyncValue` para os estados carregando/erro/dados); go_router para navegação declarativa com redirects; dio pelos interceptors.
**Alternativa:** Bloc — mais verboso para o tamanho da equipe (uma pessoa).

### ADR-007 — Atividades com tabela base + detalhes por modalidade
**Status:** Aceita — detalhes em `ARCHITECTURE.md` §6 e `DATA_MODEL.md`.

### ADR-008 — OpenAPI como contrato; sem pacote de contratos separado no início
**Status:** Aceita
**Decisão:** o FastAPI gera o OpenAPI; um script exporta `openapi.json` para `docs/` e um teste do backend falha se o arquivo estiver desatualizado. O cliente Dart é escrito à mão, com modelos explícitos.
**Consequências:** sem geradores de código frágeis; o contrato continua verificável. Podemos adotar geração de código mais tarde.

### ADR-009 — Técnicas avançadas modeladas explicitamente
**Status:** Aceita
**Decisão:** dois conceitos distintos:
1. **Agrupamento entre exercícios** (`exercise_groups`, tipo `superset | biset | triset | giant_set`): exercícios alternados sem descanso.
2. **Estrutura dentro de uma série** (`set_kind`: `warmup | working | drop | rest_pause | cluster`, com `parent_set_id` encadeando os segmentos de drop/rest-pause; flag `to_failure`).
**Consequências:** o volume, os recordes e o estímulo podem tratar cada técnica com regras próprias e testáveis.

### ADR-010 — Meu Corpo: cálculo separado da representação; 2D primeiro
**Status:** Aceita (3D em avaliação)
**Decisão:** o backend devolve `{muscle_id, weighted_sets, band}` usando IDs estáveis (`chest`, `lats`, ...). O app tem uma interface `BodyMapRenderer`; a v1 implementa `SvgBodyMapRenderer` (frente/costas, toque para selecionar). Um `GlbBodyMapRenderer` (360°) poderá ser adicionado quando houver um modelo com licença adequada.
**Consequências:** o recurso visual principal fica pronto sem depender de um ativo externo incerto.

### ADR-011 — IA desacoplada do fornecedor, com ferramentas tipadas e propostas confirmadas
**Status:** Aceita (fornecedor: **Proposta** — ver ADR-012)
**Decisão:** interface `LLMProvider` com adaptadores (`fake`, `anthropic`, extensível); laço de *tool calling* no backend; ferramentas declaradas com schemas Pydantic e sempre executadas com o `user_id` da sessão; a IA **nunca** escreve no banco — ela cria `change_proposals`, que o usuário confirma por um endpoint próprio. Detalhes em `AI_DESIGN.md`.

### ADR-012 — Provedor de LLM padrão
**Status:** **Proposta — precisa da sua decisão**
**Recomendação:** Anthropic Claude (bom suporte a *tool use* e respostas em PT-BR); modelo econômico (classe Haiku/Sonnet) para o chat e um modelo maior só para a análise global, se o orçamento permitir.
**Custos:** pagamento por token. Com limites diários por usuário e contexto enxuto, o uso em demonstração de TCC tende a ser baixo, mas **exige uma conta e uma chave sua**.
**Sem decisão:** o desenvolvimento segue com o provedor `fake` (respostas roteirizadas) até a Fase 4.

### ADR-013 — Metodologia de estímulo muscular configurável e versionada
**Status:** Aceita (valores iniciais revisáveis) — ver `DATA_MODEL.md` §6.

### ADR-014 — PostgreSQL também nos testes
**Status:** Aceita
**Decisão:** sem SQLite nos testes: usaremos enums nativos, `timestamptz`, JSONB e índices parciais. O Compose sobe `db-test` (porta 5443 — ADR-018 —, `tmpfs`).
**Consequência:** os testes do backend precisam de um PostgreSQL disponível: o `db-test` do Compose ou, no modo local, o PostgreSQL da máquina (ADR-021).

### ADR-015 — Unidades em SI e datas em UTC
**Status:** Aceita — ver `ARCHITECTURE.md` §3.2.

### ADR-016 — Seed de exercícios próprio
**Status:** Aceita
**Decisão:** escrever uma biblioteca inicial (~60–80 exercícios) em PT-BR, com músculos primários e secundários definidos pelo projeto, versionada em `services/api/app/modules/exercises/seed/exercises.v1.json`. Sem imagens/vídeos de terceiros na v1.
**Consequência:** nenhum risco de licença; a curadoria precisa ser revisada (idealmente por um profissional de Educação Física).

### ADR-017 — Sem nova tentativa automática nos providers do app
**Status:** Aceita · Fase 1
**Contexto:** o Riverpod 3 refaz automaticamente providers com erro, com backoff exponencial. Nos testes, a tela de erro demorava vários segundos para aparecer; em operações de escrita, isso repetiria chamadas sem o usuário saber.
**Decisão:** `ProviderScope(retry: noAutomaticRetry)` (`lib/app/provider_config.dart`). Nova tentativa é sempre explícita (botão “Tentar novamente” / puxar para atualizar).

### ADR-018 — Portas locais 5442/5443 para o PostgreSQL do Compose
**Status:** Aceita · Fase 1
**Contexto:** a máquina de desenvolvimento já tem um PostgreSQL próprio ouvindo na 5432.
**Decisão:** o banco de desenvolvimento usa 5442 e o de testes 5443, configuráveis no `.env`. As URLs usam `127.0.0.1` (não `localhost`) para evitar uma tentativa em IPv6 que dobra o tempo de falha.

### ADR-019 — Versões efetivamente fixadas na Fase 1
**Status:** Aceita · Fase 1
- **TypeScript 5.x** (não 7.0): o template oficial do Next 16.4 fixa `typescript ^5` e `eslint ^9`; ficamos no que o framework suporta.
- **`@types/node ^24`**: igual ao Node local (24) e exigido pelo Vitest 5.
- **httpx2** nos testes da API: o Starlette 1.10 depreciou o `httpx` no `TestClient`.
- **Fontes do site** (Inter e Space Grotesk) via `next/font/google`: baixadas no build e servidas pelo próprio site; o navegador não faz requisições ao Google. No app, ficam as fontes do sistema até a Fase 2.

### ADR-020 — Timeout de conexão com o banco
**Status:** Aceita · Fase 1
**Contexto:** sem `connect_timeout`, um banco inalcançável (que não recusa ativamente a conexão) travava `/health` e qualquer requisição indefinidamente — o problema apareceu no teste manual.
**Decisão:** `connect_timeout=5` no psycopg e `pool_timeout=10` no SQLAlchemy.

### ADR-021 — PostgreSQL 18 e banco local como alternativa ao Docker
**Status:** Aceita · Fase 1
**Contexto:** nesta máquina o WSL2 não inicia (virtualização desabilitada) e o Docker Desktop cai no backend Docker VMM, que não consegue iniciar containers.
**Decisão:** variável `DB_MODE` (`docker` | `local`). No modo local, os scripts não chamam o Docker e usam o PostgreSQL da máquina (aqui, 18.6 na porta 5433, com usuário e bancos próprios do projeto). O Compose foi fixado em `postgres:18-alpine`, a mesma versão maior, para que os dois caminhos testem o mesmo banco.
**Consequências:** o desenvolvimento não depende do Docker; o caminho com Docker continua documentado como padrão reproduzível (ADR-014 continua valendo: os testes usam PostgreSQL real em ambos os modos). Substitui a versão 17 prevista na Fase 0.
