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
**Decisão:** escrever uma biblioteca inicial (~60–80 exercícios) em PT-BR, com músculos primários e secundários definidos pelo projeto, versionada em `services/api/app/modules/exercises/seed/exercises.v1.json`. Sem imagens/vídeos de terceiros na v1. *(A parte das imagens foi revista na ADR-030.)*
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

### ADR-022 — Limite de tentativas em memória
**Status:** Aceita · Fase 2.1
**Decisão:** janela deslizante em memória (`app/modules/auth/rate_limit.py`), uma instância por processo da API.
**Consequências:** sem dependência nova (Redis) para um TCC com um único processo. Com várias instâncias ou workers, cada um teria o próprio contador: antes de escalar, mover o estado para um armazenamento compartilhado. O IP vem da conexão; atrás de um proxy reverso será preciso configurar os cabeçalhos confiáveis.

### ADR-023 — Cadastro informa e-mail já existente
**Status:** Aceita · Fase 2.1
**Contexto:** responder `409` no cadastro revela que um e-mail tem conta. A alternativa (sempre responder "verifique seu e-mail") exige envio de e-mail, que a v1 não tem.
**Decisão:** `409 email_already_registered` no cadastro, com limite de 5 cadastros/h por IP. O **login** continua sem revelar contas (mesma resposta e mesmo tempo).
**Revisão:** quando houver confirmação de e-mail, trocar pelo fluxo que não revela.

### ADR-024 — Access token não revogável antes de expirar
**Status:** Aceita · Fase 2.1
**Decisão:** o logout revoga o refresh token; um access token já emitido continua válido até expirar (no máximo 15 min). Desativar a conta, porém, bloqueia o access token na hora (o `/me` e as rotas protegidas conferem o status do usuário a cada requisição).
**Consequência:** evita uma consulta extra de lista de bloqueio a cada requisição; o risco fica limitado à validade curta.

### ADR-025 — Identidade monocromática clara
**Status:** Aceita · Fase 2 (antes da 2.2) · substitui a paleta escura com acento azul da Fase 0
**Decisão:** fundo off-white, superfícies brancas e preto como cor de ação, no app e no site (tokens compartilhados). Cores só para estados (erro, sucesso, aviso) e para as faixas do Meu Corpo, que são dados.
**Consequências:**
- O tema do app passou a ser claro (`AppTheme.light`), com a abertura nativa do Android na mesma cor de fundo (sem piscar na troca para o Flutter).
- O ícone do app virou o monograma da marca (adaptativo a partir do Android 8; PNG nos anteriores).
- Contrastes verificados (tabela em `UX_FLOWS.md` §4). O modo escuro fica para depois da v1.

### ADR-026 — Onboarding, objetivos e dados de saúde
**Status:** Aceita · Fase 2.2
**Decisões:**
- **Objetivo ≠ meta.** `primary_objective`/`secondary_objectives` no perfil registram a motivação (vocabulário fixo, escolhido em toques); metas mensuráveis com prazo ficam em `goals` (2.3).
- **Experiência única** (`experience_level`) em vez de uma por modalidade, como previa o UX_FLOWS: menos atrito no onboarding; pode virar por modalidade quando houver uso real para isso.
- **Revogar `health_data` apaga os dados de saúde** em vez de só bloquear o uso: sem o consentimento não há base legal para mantê-los (LGPD art. 11). O app avisa e pede confirmação antes.
- **Vocabulários no backend** (`GET /profile-options`), com rótulos PT-BR: o app não duplica listas e um código novo aparece sem atualizar o app.
- **Onboarding com 4 passos puláveis** (o cadastro é o passo 1); `onboarding_completed_at` decide se ele aparece e é gravado no mesmo PATCH das respostas.
- **O roteador só reage a mudanças que afetam a rota** (entrou, saiu, precisa de onboarding): salvar o perfil não reavalia a navegação.
- **Conexão com o banco em UTC** (`-c timezone=UTC`): datas saem iguais na criação e na leitura (achado pelos testes da 2.2; reforça a ADR-015).

### ADR-027 — Revisão de interface e acessibilidade antes da 2.3
**Status:** Aceita · Fase 2 (entre 2.2 e 2.3)
**Contexto:** revisão das telas de acesso, onboarding e perfil por acessibilidade, layout, texto, tipografia, cor e acabamento, mais um teste de pior caso (320 dp, fonte em 200 %, nomes e e-mails longos, vocabulário completo). Achou 5 problemas graves (foco invisível, toque escondido nas pílulas, "dias por semana" inoperável pelo TalkBack, animações ignorando a redução de movimento, erro sem caminho de saída) e estouros de layout com fonte grande.
**Decisões:**
- **Botões de avançar sempre habilitados**, explicando o que falta, em vez de desabilitados sem motivo.
- **Anel de foco próprio** (preto, 2 px) em vez do destaque translúcido do Material, que some na paleta monocromática.
- **Uma escala de toque só (0,97)**, desfeita ao arrastar.
- **Teste de pior caso permanente** (`stress_layout_test.dart`): um estouro de layout reprova o teste. A verificação por mutação confirmou que ele acusa a falha.
**Consequências:** botões de avançar não usam mais o estado desabilitado; novos componentes clicáveis devem usar `EvoFocusRing` e `EvoPressable`, e animações implícitas, `evoDuration`/`EvoAnimatedSize`. Ficou sem verificação a navegação completa com TalkBack num aparelho real.


### ADR-028 — Metas com alvo descrito por tipo
**Status:** Aceita · Fase 2.3
**Decisões:**
- **Os campos do alvo de cada tipo são dados, não código duplicado:** `app/modules/goals/kinds.py` define campos (texto, inteiro, número com passo, escolha, duração), faixas e unidades. A API valida por ali e publica em `GET /goal-options`; o app monta o formulário a partir disso. Um tipo novo aparece sem atualizar o app (mesma linha da ADR-026).
- **`kind` como texto**, não enum do PostgreSQL: um tipo novo não exige migração. O status continua enum (conjunto fechado).
- **Unidades métricas no armazenamento** (`kg`, `km`, segundos). `distance_km` em vez do `distance_m` previsto no DATA_MODEL: é o que a pessoa digita e evita conversão no formulário. A exibição em libras e milhas (`unit_system=imperial`) fica pendente.
- **Metas de peso são dado de saúde:** exigem `health_data` e são apagadas na revogação, como as limitações (ADR-026).
- **Posse pelo token:** toda consulta filtra pelo dono; a meta de outra pessoa responde 404, igual a uma inexistente. No app, a lista depende do id da conta e é descartada ao trocar de usuário.
- **Status manual por enquanto:** marcar como alcançada é uma ação do usuário. O progresso automático virá com os registros de treino (Fase 3) e de medidas (Fase 5).
- **"Hoje" é o dia no fuso do perfil**, não em UTC: perto da meia-noite os dois diferem.
- **Limite de 30 metas ativas**, por foco e contra abuso.

### ADR-029 — Biblioteca de exercícios: catálogo na migração, busca sem extensões
**Status:** Aceita · Fase 2.4 · implementa a ADR-016
**Decisões:**
- **O catálogo chega com a migração** (0004 lê `exercises.v1.json`): banco novo já tem a biblioteca, inclusive o de testes. Uma versão nova do seed vira uma migração nova. Os ids do catálogo são UUID v5 do slug, iguais em todo ambiente.
- **71 exercícios**, todos os 13 grupos musculares com exercícios como principal (teste automatizado). Conteúdo escrito pelo projeto; a revisão por profissional de Educação Física continua pendente (ADR-016).
- **Busca sem extensão `unaccent`**: uma coluna `search_name` normalizada na aplicação. Evita exigir permissão de superusuário no banco.
- **No app, a busca e os filtros rodam no aparelho**, sobre a lista inteira (catálogo + próprios, algumas centenas no máximo): resposta instantânea. A API também filtra (`q`, `muscle`, `equipment`), para outros clientes e para a IA.
- **Arquivar em vez de excluir** exercícios próprios: as sessões da 2.6 vão referenciá-los.
- **Grupos musculares em um lugar só** (`catalog.py`): a tabela, as opções da biblioteca e a meta de hipertrofia usam a mesma lista.
- **"Sem equipamento"** como rótulo do equipamento `bodyweight`, porque "Peso do corpo" é o rótulo do tipo de carga e a tela mostrava o mesmo texto duas vezes.

### ADR-030 — Fotos dos exercícios da free-exercise-db
**Status:** Aceita · Fase 2 (depois da 2.4) · revê a parte de imagens da ADR-016
**Contexto:** o detalhe do exercício só tinha texto. Comparadas as bases abertas: free-exercise-db (Unlicense, 2 fotos por exercício), wger (licença por imagem, maioria CC-BY-SA 3.0, poucas imagens) e bases pagas. A escolha foi do usuário: free-exercise-db.
**Decisões:**
- **67 dos 71 exercícios com foto**, mapeados à mão pelo equivalente mais próximo (`seed/images.v1.json`). Ficam só com texto os 4 sem variação equivalente na base: barra fixa assistida, kettlebell swing, panturrilha unilateral no degrau e remada com elástico.
- **Arquivos dentro do projeto** (8,4 MB, servidos pela API em `/api/v1/media/exercises`), não carregados do GitHub: o app não depende de um site de terceiros e o conteúdo não muda sem uma versão nova do seed.
- **Na API, não no app**: o APK não cresce; as fotos chegam pela rede, com cache.
- **O texto de "Como fazer" continua o nosso**, em PT-BR. As fotos mostram a variação da base, que às vezes difere um pouco (ex.: goblet com kettlebell); o app avisa.
- **Crédito no detalhe** ("Fotos: free-exercise-db (domínio público)"), embora a licença não exija.
**Riscos e ressalvas:**
- O repositório declara domínio público, mas **não documenta a origem das fotos originais**, que são profissionais e mostram pessoas identificáveis e marcas. Para uso além do TCC (publicação na loja, uso comercial), trocar por fotos próprias ou por uma base com origem documentada.
- Formato: 65 fotos são 3:2 e 2 estão em pé; o app mostra as duas posições empilhadas, na largura toda, sem cortar.
