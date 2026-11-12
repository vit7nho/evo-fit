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

### ADR-031 — Fichas salvas inteiras
**Status:** Aceita · Fase 2.5 · revê o desenho de rotas do API.md (`/workout-templates/{id}/items`)
**Decisões:**
- **Um pedido salva a ficha toda** (nome, itens na ordem e grupos), em vez de rotas por item. O editor monta tudo e envia de uma vez: não existe ficha pela metade, nem conflito de posições entre pedidos. Uma ficha tem no máximo 30 itens, então o corpo é pequeno.
- **Grupos referenciados por índice** no corpo (`group: 0`), com o mesmo formato na entrada e na saída: o app lê, edita e devolve sem traduzir ids.
- **Regras dos grupos nos dois lados:** a API confere sequência e tamanho; o app mantém os mesmos invariantes no rascunho (`TemplateDraft`), testados à parte. Juntar cria ou une grupos; mover um item avulso pula o grupo inteiro; na ponta do grupo, mover primeiro tira o item dele.
- **Séries por tempo ou por repetições conforme o exercício** (`load_type = time`), conferido na API.
- **Excluir é definitivo**, sem arquivar fichas; a sessão (2.6) vai copiar o que precisa da ficha.
- **`template_items.exercise_id` com CASCADE**: sem ele, excluir a conta travava quando uma ficha usava um exercício próprio (achado pelo teste).

### ADR-032 — Sessão de treino salva série a série no servidor
**Status:** Aceita · Fase 2.6
**Decisões:**
- **Cada série vai para a API na hora do ✓**: fechar e reabrir o app retoma o treino aberto (`GET /workout-sessions/current`), sem esperar a 2.9. O rascunho local da 2.9 fica para quando não houver rede.
- **Uma sessão aberta por usuário**, garantida por índice único parcial no banco (vale também para dois inícios simultâneos); o app, ao receber `409`, abre a sessão que já existe em vez de mostrar erro.
- **A sessão copia a ficha** (exercícios, grupos, plano, descansos): editar ou excluir a ficha não muda o treino em andamento nem o histórico.
- **Pré-preenchimento pela última sessão concluída** com o mesmo exercício (da mesma conta; descartadas não contam), devolvido junto com o treino. Ordem de sugestão no app: última vez → plano → série anterior de hoje.
- **Tempo calculado no servidor** (`elapsed_s` na resposta); o app soma o tempo local desde então. O descanso guarda o horário de término, não um contador.
- **Descartar apaga** (atividade, sessão, exercícios e séries); não existe estado `discarded`.
- **`activities` nasce agora** (modalidade `strength`), como base da Fase 3; drop, rest-pause e falha (2.7) já têm colunas (`parent_set_id`, `to_failure`, CHECK do segmento), mas a API ainda recusa esses tipos.
- **Achados no emulador**, corrigidos: o botão preenchido de iniciar ficava com o ícone preto sobre preto (tema dos IconButtons); a sugestão só aparecia ao tocar no campo (rótulo agora sempre no alto); a barra de descanso não ocupava a largura toda. Nos testes, o tempo e a barra de descanso estouravam com fonte em 200% (corrigidos com a faixa do tempo e o `Wrap`).

### ADR-033 — Drop set e rest-pause como segmentos da série
**Status:** Aceita · Fase 2.7
**Decisões:**
- **Segmento, não série nova**: drop e rest-pause são linhas de `set_entries` com `parent_set_id` apontando para a série válida que continuam. A contagem de séries (resumo, e depois histórico e volume por músculo do DATA_MODEL §5) trata a cadeia como uma série; o volume em kg soma tudo.
- **Regras na API**: o pai é uma série `working` do mesmo exercício no mesmo treino (o que também impede usar a série de outra pessoa); sem segmento de segmento; até 5 por série; o tipo do segmento não muda; apagar a série leva os segmentos (o serviço apaga os segmentos num flush antes da série, porque sem relação declarada o ORM não conhece a ordem).
- **Falha é uma marca** (`to_failure`) em qualquer série ou segmento, incompatível com RIR acima de 0.
- **Sem toque longo**: as ações ficam visíveis sob a última série feita (“Drop”, “Rest-pause”, “Até a falha”), alcançáveis pelo TalkBack e sem gesto escondido. Drop só aparece em exercício com carga externa; drop e rest-pause não aparecem em exercício por tempo.
- **Sugestões**: o segmento da última vez, se houver; senão o drop tira 20% da carga anterior (múltiplo de 2,5 kg, ao menos 2,5 kg) e o rest-pause repete a carga. Repetições do segmento não são inventadas: sem histórico, o usuário digita.
- **Descanso**: o drop cancela o descanso (é feito em seguida); o rest-pause começa com 15 s; salvar o segmento inicia o descanso normal do exercício.
- **Plano da ficha**: série planejada como drop/rest-pause é registrada como válida, com aviso na linha, e a linha do segmento abre sozinha depois do ✓.
- **Achado no emulador**, corrigido: o título da linha do drop e o chip de falha encostavam nos rótulos dos campos logo abaixo (mais espaço vertical).

### ADR-034 — Registro de séries em tabela, com o tipo no número
**Status:** Aceita · Fase 2.7 (revisão da tela, pedida a partir de uma referência de app de treino)
**Decisões:**
- **Tabela por exercício** (`SÉRIE · ANTERIOR · KG · REPS · ✓`): a série da última vez fica na mesma linha (coluna "Anterior"), em vez de uma frase acima das séries.
- **Todas as linhas editáveis e fora de ordem**: as linhas vivem no app, na ordem da tela (`set_rows.dart`), e guardam o id da série salva; a API continua salvando série a série. Ao reabrir o app, as linhas são remontadas das séries salvas mais o que falta do plano.
- **O tipo vai no número**, num menu que explica cada opção e diz por que uma não vale (ex.: drop na primeira linha, drop em exercício sem carga, mudar o tipo de uma linha feita para segmento). Substitui a barra “Drop / Rest-pause / Até a falha” da ADR-033. Uma linha D ou RP continua a série principal mais próxima acima, que precisa estar feita; "F" é uma série válida com `to_failure`.
- **✓ preenchido desfaz** (apaga a série e a linha volta com os valores); corrigir é editar o campo e sair dele. Remover a linha fica no menu do tipo.
- **Descanso e nota no cabeçalho do exercício**, ajustáveis no treino (`PATCH …/exercises/{seid}`), sem mudar a ficha. Nos grupos, vale o descanso da rodada (o botão não aparece).
- **Resumo ao vivo no topo** (duração, volume, séries), calculado no app com a mesma regra da API.
- **Monocromático mantido**: o tipo é dito pela letra, não pela cor. Com fonte grande ou tela estreita, a coluna "Anterior" desce para baixo dos campos (que ganham rótulo) e o resumo rola junto com a lista, para caber a barra de descanso e o botão de finalizar.
- **Verificação**: testes de fluxo e de layout (320 dp, fonte 200%) reescritos; no emulador, a tela foi aberta com um treino real em andamento, mas sem registrar séries porque o aparelho estava logado na conta pessoal do usuário — o registro na tabela está coberto pelos testes de widget contra o servidor falso, e a rota nova da API por testes de integração.

### ADR-035 — Recordes calculados sob demanda, numa passada cronológica
**Status:** Aceita · Fase 2.8
**Decisões:**
- **Sem tabela de recordes**: uma consulta traz as séries dos treinos concluídos do usuário (opcionalmente só alguns exercícios e só até uma data) e uma passada em ordem cronológica guarda o melhor de cada tipo e os treinos em que ele foi superado. A mesma passada serve à lista do histórico (`record_count`), ao detalhe do treino (`records`), ao histórico do exercício e a `/analytics/records`. Excluir ou corrigir um treino recalcula tudo naturalmente.
- **Tipos por forma de medir**: carga externa tem maior carga, 1RM estimado (Epley, 1 a 12 repetições, sempre rotulado como estimativa) e maior volume num treino; peso do corpo e assistido, mais repetições; por tempo, maior duração. Melhor carga por número exato de repetições (1 a 20) fica como tabela no histórico do exercício, sem gerar "recorde batido" (seria ruído).
- **Primeira vez não é recorde batido**; aquecimentos não contam; drop e rest-pause só entram no volume.
- **Treino aberto não mostra recordes** (a comparação é feita ao concluir); fica para depois mostrar recorde ao vivo durante o treino.
- **Comparação com a vez anterior** é feita no app a partir de `previous` (volume e melhor série); a API passou a escolher como "vez anterior" a última sessão antes do treino em questão — no detalhe de um treino antigo, antes vinha a mais recente.
- **Paginação por data** (`before` = início do último item), estável mesmo com treinos novos entrando.
- **Verificação**: testes de API (inclusive teste de mutação do filtro por usuário) e de app; no emulador, o histórico vazio da conta do usuário foi aberto contra a API real (só leitura), e respostas reais da API com três treinos (conta temporária, apagada depois) foram passadas pelos modelos do app.

### ADR-036 — Site escuro e cinematográfico, com componentes do Spell UI
**Status:** Aceita · revisão do site (fora das etapas do app)
**Decisões:**
- **O site sai do monocromático do app** (ADR-025 continua valendo para o app): fundo escuro e as cores do mapa de estímulo do Meu Corpo (azul, laranja, vermelho) como paleta. As telas do app mostradas no site seguem as cores claras do app.
- **Componentes do Spell UI** (https://spell.sh, licença MIT, cópia da licença em `apps/web/src/components/spell/LICENSE`): *Animated Gradient* (fundo WebGL do hero) e *Tilt Card* (celulares que inclinam com o mouse). Copiados e adaptados, sem dependência nova: tirado o `next-themes`, `cn` local e, com "reduzir movimento", o gradiente desenha um quadro só e o cartão não inclina. Os componentes que exigiam `motion` ou `three` ficaram de fora; as entradas de texto e a faixa infinita são CSS.
- **Referência de estilo**: sites de estúdio com hero de impacto e demonstrações em código (sem copiar textos, imagens nem código de terceiros pagos).
- **O app aparece de verdade**: telas do treino (tabela de séries), do histórico e dos recordes recriadas em HTML, com descrição para leitor de tela.
- **Honestidade**: cardio, Meu Corpo, nutrição e IA aparecem como "Em breve"; o rodapé diz o que já funciona.
- **Achados ao conferir no navegador**: o nome acessível do título saía grudado por causa da animação palavra por palavra (o espaço foi para fora de cada palavra); `max-w-3xl` e afins caíam nos tamanhos de espaçamento do tema (3xl = 3rem) e espremiam o texto — trocados por larguras explícitas.
- **Uma versão editorial (inspirada em um site-demonstração de cafeteria) foi testada e descartada**; ficou esta versão escura, com as animações corrigidas:
  1. a entrada ligada à rolagem do CSS (`animation-timeline: view()`) não completava perto do fim da página (o último bloco ficava meio transparente) e ignorava o atraso em milissegundos — trocada pelo componente `Reveal` (IntersectionObserver);
  2. a faixa infinita pulava a cada volta por causa do `gap` — cada item tem o próprio espaço e a trilha anda exatamente uma cópia;
  3. desfoque animado em texto com gradiente pisca no Chrome/Safari — as entradas usam só transform e opacity, e o gradiente do título fica num elemento sem animação;
  4. com "reduzir movimento", o gradiente desenhava um quadro só e sumia quando a janela mudava de tamanho (redimensionar apaga o canvas) — agora redesenha a cada redimensionamento.

### ADR-037 — Rascunho local da sessão: cópia do servidor + fila de séries
**Status:** Aceita · Fase 2.9
**Decisões:**
- **O servidor continua sendo a verdade**; o app guarda a última cópia do treino que a API devolveu e, por cima, uma fila das alterações de séries (criar, corrigir, apagar) que ainda não chegaram lá. A tela mostra sempre a cópia com a fila aplicada. Fica no armazenamento seguro do aparelho (o mesmo do login), por conta: são dados de treino da pessoa.
- **Envio idempotente**: cada série nasce com um id gerado no app (`client_id`, UUID v4). Reenviar a mesma série devolve a já salva (índice único no banco). Resolve resposta perdida, timeout e reabertura do app sem risco de duplicar. Um drop ou rest-pause aponta para a série de cima pelo `parent_client_id`, então a fila não precisa esperar o id do servidor.
- **Identidade estável no app**: a série é identificada pelo `client_id` quando há (senão pelo id do servidor); a linha da tabela não perde o vínculo quando a série pendente é enviada.
- **Quando entra na fila**: só falta de conexão ou timeout. Erro de validação continua na linha, como antes. Com a fila não vazia, as novas alterações entram nela (para manter a ordem). A fila é enviada em ordem: ao registrar, a cada 20 s enquanto houver pendência, ao reabrir o app e pelo botão “Tentar agora”. Uma alteração recusada pelo servidor (ex.: treino finalizado em outro aparelho) é descartada com aviso, junto com os segmentos que dependiam dela.
- **Corrigir ou desfazer uma série ainda na fila** muda o próprio envio pendente, sem chamar o servidor.
- **Finalizar espera a fila esvaziar** (tenta enviar antes; sem conexão, explica). Pausar, retomar, acrescentar exercício e descartar continuam exigindo conexão.
- **Limite conhecido**: reabrir o app *sem conexão* para na tela de entrada (o login precisa do servidor para confirmar a conta); o rascunho fica guardado e é enviado assim que o app entra com rede. Abrir o treino totalmente offline exigiria guardar os dados da conta no aparelho — evolução possível.
- **Correção no aceite da Fase 2 (2026-11-04)**: no aparelho, concluir uma série às vezes a mostrava em dobro. O controlador publica o treino atualizado e só depois espera a gravação do rascunho, que no armazenamento seguro é lenta; nesse intervalo a tela era redesenhada, a conciliação das linhas via uma série que nenhuma linha reivindicava e criava uma linha nova para ela, e logo depois a linha original também a recebia. Os testes não pegavam porque o armazenamento em memória responde na hora. Agora o cartão gera o `client_id` antes de enviar (`logSet(..., clientId:)`) e a conciliação ignora as séries que ele está concluindo (`reconcileRows(..., registering:)`). Teste de regressão com um armazenamento que demora a gravar: falhava antes da correção.
- **Verificação**: testes de API (inclusive mutação: sem o índice e sem a checagem, o reenvio duplica) e de app (sem conexão, fechar e reabrir com drop dependente, resposta perdida, correção na fila, finalizar com pendência, layout com fonte grande — que pegou a faixa de aviso estourando a tela e a levou para dentro da rolagem); na API real, o reenvio com o mesmo id devolveu a mesma série. O modo sem conexão não foi exercitado no emulador para não registrar séries na conta pessoal que estava logada nele.

### ADR-038 — Testes de autorização entre usuários: matriz única ligada ao OpenAPI
**Status:** Aceita · Fase 2.10
**Decisões:**
- **Uma matriz, não testes soltos**: `tests/test_authorization.py` lista todas as operações da API como públicas ou protegidas (com um corpo válido para cada). Um teste compara essa lista com o OpenAPI, nos dois sentidos, e também confere que o OpenAPI marca como protegidas exatamente as mesmas. Endpoint novo sem classificação faz a suíte falhar. Os testes de posse que já existiam em cada módulo continuam lá.
- **Um mundo completo da Ana**: consentimento de saúde, meta, exercício próprio, ficha com bi-set, treino finalizado e treino em andamento com drop set. A Bia tenta cada operação com os ids da Ana (contra o treino em andamento e o finalizado). Depois de cada bateria, tudo o que a Ana vê (perfil, listas, treinos, histórico e recordes) tem de estar idêntico.
- **O que se exige**:
  - sem credencial válida, `401` em todas as operações protegidas: sem cabeçalho, Basic, lixo, token expirado, assinado com outra chave, `alg: none`, conta inexistente e refresh usado como access;
  - id de outra conta na URL: `404 not_found`, com a mesma resposta (fora o `request_id`) de um id inventado, para não revelar que o registro existe;
  - ids misturados (o treino da Bia com o exercício ou a série da Ana, e o contrário): `404`;
  - ids da Ana no corpo (exercício próprio na ficha ou no treino, ficha ao iniciar, série-mãe de um drop, ordem das fichas): recusados;
  - `user_id`/`owner_id` enviados pelo cliente: `422`; `id`, `email` e `status` não mudam pelo perfil;
  - listas, pré-preenchimento, histórico, recordes e consentimentos da Bia nunca trazem dados da Ana, mesmo quando as duas treinam o mesmo exercício do catálogo.
- **Cliente de testes desfaz o que a requisição não confirmou**: os testes usavam uma única sessão do banco para todas as requisições, então uma requisição que falhava depois de mexer em dados deixava as mudanças valendo para as seguintes. Em produção a sessão é por requisição e fecha sem commit. A matriz pegou isso: um `PUT` de ficha recusado com `422` aparecia como se tivesse esvaziado a ficha. Agora o override de `get_db` chama `rollback()` ao fim de cada requisição, como em produção. As 344 verificações passam com o comportamento real.
- **Verificação por mutação**: removido um filtro de dono por vez nos serviços (16 pontos: exercícios, metas, histórico, sessões, fichas, consentimentos). As 15 remoções que abrem acesso entre contas fizeram a matriz falhar. A única que passou foi o filtro `mine` da biblioteca, que só restringe a lista aos exercícios próprios; o filtro de dono continua valendo nela. A primeira rodada mostrou que a remoção do filtro dos consentimentos passava: o mundo da Ana ganhou o consentimento de saúde e o teste passou a pegá-la.

### ADR-039 — Atividades de resistência: corpo plano, detalhes 1:1 e exclusão lógica
**Status:** Aceita · Fase 3.1
**Decisões:**
- **Escopo**: registro manual de corrida, caminhada, ciclismo e natação (duração, distância, esforço, notas, o básico de cada modalidade). Pace, velocidade, FC, elevação, cadência e potência ficam para a 3.2; importação de outros apps, para depois.
- **Tabelas como no ADR-007**, criadas só com o que a 3.1 usa: `endurance_details.distance_m`, `cycling_details.indoor`, `swim_details` (piscina, voltas, estilo). Colunas novas chegam com a etapa que as usa, em migração própria.
- **Corpo plano, não discriminado**: um objeto só, com os campos de cada modalidade opcionais; o serviço recusa (`422` no campo) um campo que não se aplica, em vez de guardá-lo e ignorá-lo. Mais simples para o app e para o OpenAPI; o efeito é o mesmo de um corpo discriminado.
- **Musculação fora de `/activities`**: o treino tem rota própria e regras próprias (séries, pausas, finalizar). A atividade por trás de um treino responde 404 aqui.
- **Distância da natação**: na piscina, `voltas × tamanho` é a fonte; a distância é calculada quando falta e recusada quando não bate. Em águas abertas, só a distância. No app, com piscina escolhida o campo de distância some e a tela mostra o total.
- **Duração digitada**, não um seletor de rolagem: “45” vira minutos e “1:05:30” é aceito. Mais rápido com o teclado numérico e acessível ao leitor de tela.
- **Exclusão lógica** (`deleted_at`), como previsto no DATA_MODEL: os indicadores da 3.4 podem recalcular o histórico. A exclusão da conta continua física (cascata).
- **Datas**: com fuso obrigatório; até 5 minutos no futuro (relógio do aparelho) e no máximo 5 anos atrás.
- **Verificação**: 36 testes de API (regras por modalidade, natação, limites, lista paginada, musculação fora, exclusão lógica, posse, logs sem as notas); a matriz da 2.10 ganhou as 6 rotas novas (o teste de cobertura falhou até elas entrarem) e uma mutação no filtro de dono das atividades foi detectada. App: 9 testes de fluxo e o de layout com fonte em 200%. Emulador de aceite com a API real: corrida e natação registradas, distância da piscina calculada pela API, edição, exclusão, fechar e reabrir; banco conferido; conta de teste apagada.
- **Teste instável corrigido**: a matriz da 2.10 compara um retrato da conta antes e depois das tentativas, e o treino em andamento traz `elapsed_s`, calculado na hora. Com mais rotas, as requisições passaram a cruzar a virada de um segundo de vez em quando. O relógio do serviço de sessões fica parado nesses testes (fixture `clock`).

### ADR-040 — Pace calculado na hora; FC como dado de saúde
**Status:** Aceita · Fase 3.2
**Decisões:**
- **Pace e velocidade não são guardados** (DATA_MODEL §4): a API devolve `pace_s_per_km` e `speed_kmh` (corrida, caminhada, ciclismo) ou `pace_s_per_100m` (natação), calculados com distância e duração. Corrigir uma das duas atualiza o ritmo sem migração de dados. O app faz a mesma conta enquanto a pessoa digita, só para mostrar.
- **Cada modalidade vê o seu ritmo**: min/km na corrida e na caminhada, km/h no ciclismo, min/100 m na natação.
- **Velocidade improvável é recusada** (30/15/120/10 km/h): pega erros de digitação, como 5 km em 1 min, antes que distorçam os indicadores da 3.4. Os limites ficam acima dos recordes mundiais de cada modalidade, para não barrar ninguém de verdade.
- **FC é dado de saúde** (SECURITY_PRIVACY.md): exige `health_data` para gravar, e revogar apaga a FC de todas as atividades, como já acontecia com limitações e metas de peso. Limpar a FC não exige consentimento. Elevação não é dado de saúde.
- **Campos novos recolhidos em “Mais detalhes”**: o caminho comum (duração e distância) continua curto; quem usa relógio abre a seção. Ela já vem aberta quando a atividade tem esses dados.
- **Escopo**: cadência, tempo em movimento e potência ficam para quando houver importação de relógios; digitados à mão, raramente são conhecidos.
- **Achados no aparelho**: (1) a confirmação de revogação dizia que só as limitações seriam apagadas, mas o servidor já apagava as metas de peso desde a 2.3 e agora também a FC: o texto passou a listar tudo, e o texto do consentimento cita peso e frequência cardíaca; (2) ao revogar, as metas e as atividades em memória continuavam com os dados apagados até recarregar: agora a revogação recarrega as duas (teste falha sem a correção); (3) o rótulo flutuante do primeiro campo de “Mais detalhes” saía cortado: ganhou um respiro.
- **Verificação**: 14 testes de API novos (ritmo por modalidade, velocidade improvável no registro e na correção, elevação fora da natação, FC com e sem consentimento, revogação apaga só a FC, logs sem FC); app com 6 testes novos (contas do ritmo, pace ao vivo, mais detalhes, consentimento, natação sem elevação, recarga ao revogar) e o de layout com fonte grande cobrindo a seção nova. Emulador de aceite com a API real: corrida de 5 km em 30 min mostrando 6:00/km, FC com o pedido de autorização, revogação no perfil apagando a FC e mantendo a elevação; conta de teste apagada.

### ADR-041 — Planos por templates versionados; a sessão é feita por uma atividade
**Status:** Aceita · Fase 3.3
**Decisões:**
- **Templates no código, versionados e determinísticos** (`plans/templates.py`): hábito de caminhada (8 semanas, 20 a 50 min), primeiros 5 km (9 semanas de intervalos corrida/caminhada até 30 min seguidos e o 5 km) e 10 km (8 semanas com rodagem, treino de ritmo e longão). Três sessões por semana; toda sessão com corrida tem 5 min de caminhada antes e depois. O plano guarda a versão e **uma cópia** das prescrições: mudar um template (com versão nova) não altera um plano começado. A IA não gera planos (AI_DESIGN); na Fase 4 poderá explicá-los ou propor ajustes.
- **Poucas regras, explicáveis e mostradas à pessoa**: limitação em joelho, quadril, tornozelo ou lombar (só com `health_data` ativo) repete as semanas pares dos planos de corrida, exceto a última (mais tempo antes de cada aumento); condição cardíaca ou pressão alta acrescenta um aviso para conversar com o médico. O 10 km avisa, sem bloquear, quem não tem uma corrida de 5 km registrada nos últimos 120 dias. A experiência declarada fica registrada em `adapted_for`, sem mudar o plano por ora.
- **Dias escolhidos, datas como sugestão**: a pessoa escolhe 3 dias (na corrida, não seguidos) e o início (até 4 semanas). As datas são distribuídas nesses dias, mas a **próxima sessão é sempre a primeira não feita**: perder um dia não “atrasa” nem pune; o plano segue o ritmo da pessoa.
- **A sessão é feita por uma atividade registrada** (não por um botão “feito”): o registro é o mesmo da 3.1/3.2, os indicadores da 3.4 contam a atividade uma vez só, e o pace aparece junto. Regras: atividade da própria pessoa, não excluída, da modalidade do plano, do início em diante, uma sessão por atividade. Excluir a atividade devolve a sessão para pendente (verificado na leitura, sem acoplar o módulo de atividades ao de planos).
- **Um plano ativo por vez** (índice único parcial); encerrar guarda o histórico; concluído e encerrado são só leitura.
- **Privacidade**: o plano guarda indicadores (`joint_care`, `medical_clearance_advised`), não as limitações; saem na revogação, junto com o texto do ajuste. As semanas já geradas ficam (são a prescrição, não um dado de saúde).
- **Achados no aparelho**: (1) o texto do pré-requisito saía “Para quem consegue: conseguir caminhar…”: os pré-requisitos passaram a vir prontos da API (“Para quem já caminha 30 minutos sem desconforto.”); (2) o cartão do plano em Planos mostrava “Semana 9 de 9” no início, porque o resumo não traz as sessões: a API passou a devolver `current_week` (teste no app); (3) o aviso do 10 km sumia depois da primeira sessão do plano de 5 km (30 min com caminhada contavam como base): agora só uma corrida com 5 km registrados conta (teste na API); (4) o resumo do template dizia “9 semanas” e a linha de baixo “13 semanas” com a limitação: o resumo deixou de citar a duração, e o cartão mostra as semanas ajustadas; (5) depois de revogar a autorização, o plano aberto continuava com o ajuste até reabrir o app: a revogação recarrega os planos (teste no app falha sem a correção), e a confirmação passou a dizer o que acontece com eles.
- **Verificação**: 29 testes de API novos (templates, regras de dias e de início, um ativo por vez, cópia imune a mudança do template, ajustes e revogação, logs sem limitações, marcação com cada regra, conclusão, encerramento, 404) e a matriz de autorização ampliada com os 7 endpoints (incluindo a corrida de outra pessoa no corpo, com o teste de mutação pegando a remoção de cada filtro de dono); app com 10 testes de planos e o de layout com fonte em 200% (que achou o painel da sessão e a lista de atividades estourando em tela estreita, corrigidos com rolagem). Emulador de aceite com a API real: plano de 5 km nos dias escolhidos, sessão registrada pelo formulário e outra por atividade já registrada (conferidas no banco), encerramento, limitação no joelho gerando 13 semanas e revogação tirando o ajuste; conta de teste apagada.

### ADR-042 — Motor de análise: funções puras, base válida e semanas inteiras
**Status:** Aceita · Fase 3.4
**Decisões:**
- **Funções puras sobre registros simples** (`analytics/metrics.py`): o serviço monta uma `Entry` por treino concluído ou atividade não excluída (dia no fuso do perfil, modalidade, duração, distância, séries e volume) e as contas não tocam no banco. Testáveis sem API, reaproveitáveis pelas ferramentas da IA (Fase 4) e pelos gráficos (3.7). Nada é guardado: tudo é recalculado a cada leitura, e corrigir ou excluir um registro muda os indicadores na hora.
- **Mesmas regras de sempre**: séries e volume da musculação seguem o histórico (2.8: sem aquecimento; segmentos só no volume); pace e velocidade seguem as atividades (3.2), agora ponderados pelo total (tempo ÷ distância, não média de paces).
- **Consistência em semanas** (segunda a domingo): semanas com treino, semanas que bateram a meta de dias do perfil (`weekly_availability.days_per_week`) e a sequência atual. A semana em curso ainda vazia não quebra a sequência: ainda dá tempo.
- **Percentual só com base válida**: de 0 para 3 treinos não há percentual (só a diferença), e um valor que não dá para calcular (pace sem distância) é nulo, nunca zero. `better` diz qual período foi melhor respeitando o sentido do indicador (pace: menor é melhor). É o contrato que a ferramenta `compare_periods` da IA vai usar (AI_DESIGN).
- **Tendência só com semanas inteiras**: reta de mínimos quadrados pela distância semanal, com `flat` abaixo de 5% da média; a semana em andamento e uma ponta cortada pelo período ficam de fora, e com menos de 3 semanas inteiras não há tendência.
- **App**: tela Evolução simples (cartões e barras) para usar o motor agora; os gráficos (fl_chart) e a tela de comparativos são da 3.7, e o dashboard pelos objetivos, da 3.8.
- **Achado no aparelho**: com uma conta de teste (corridas cada vez maiores, a semana atual ainda sem corrida), a tendência saía “subindo” por pouco (+200 m/semana), porque a semana em andamento entrava com zero e puxava a reta para baixo; em outros dias da semana sairia “caindo” sem a pessoa ter treinado menos. A tendência passou a usar só semanas inteiras (+2,2 km/semana no mesmo caso); teste na API falha sem a correção.
- **Verificação**: 32 testes de API novos (semanas, consistência e sequência, tendência, pace ponderado, comparação com e sem base, visão geral com todas as modalidades, fuso do perfil, registros excluídos, treino em andamento e de outra pessoa fora, limites do período, resistência, natação, validação da comparação) e a matriz de autorização com os 3 endpoints (o teste de mutação pega a remoção dos dois filtros de dono); app com 6 testes da Evolução e o de layout com fonte em 200%. Emulador de aceite com a API real e uma conta com registros em dois períodos: 30 dias (5 contra 2, +150%; 2 h 19 min, +132%; 4 de 5 semanas; corrida 18 km a 5:30/km), 7 dias e 90 dias (sem base: só a diferença), conferidos à mão e por SQL; conta de teste apagada.

### ADR-043 — Metodologia de estímulo versionada no banco; função pura testada pela matriz
**Status:** Aceita · Fase 3.5
**Decisões:**
- **Configuração no banco, versionada** (`stimulus_methodologies`, uma ativa): mudar pesos ou faixas é criar uma versão nova e ativá-la, sem mudar código; toda resposta diz a versão usada (`methodology_version`), e a IA (Fase 4) citará a versão. A migração grava a v1 com uma cópia fixa da configuração (não importa do app), para o histórico das migrações não mudar se o código mudar.
- **Função pura** (`analytics/stimulus.py`): recebe as séries já filtradas (dono, treino concluído, não excluído, período no fuso do perfil), os músculos de cada exercício e a configuração. Regras da v1: principal 1, secundário 0,5; aquecimento 0; drop 0,5 e rest-pause/cluster 0,33 por segmento; a cadeia (principal + segmentos) até 2; série sem repetições nem tempo não conta (a por tempo conta); normalização por semana (`÷ dias/7`) e faixas absolutas `[0; 0,5)` nenhuma, `[0,5; 6)` baixa, `[6; 12)` média, `12+` alta.
- **Todos os músculos na resposta**, zerados quando não treinados: o mapa do corpo (3.6) pinta os 13, e a ausência de estímulo também é informação.
- **Volume por músculo ponderado pelo papel**: o secundário recebe metade da carga × repetições, coerente com as séries ponderadas. O volume não tem o teto da cadeia (todos os segmentos levantaram carga).
- **Aviso fixo na resposta** (`notice`): as faixas são referência geral de volume registrado, não diagnóstico nem prescrição (SECURITY_PRIVACY, AI_DESIGN).
- **Detalhe do músculo** com os exercícios (papel, séries ponderadas, séries válidas, maior carga), a maior carga por dia de cada exercício e, opcionalmente, o período anterior do mesmo tamanho (percentual só com base válida, como na 3.4).
- **Ponto em aberto (resolvido no ADR-044 com a v2)**: com a v1, um treino de peito em 30 dias dá 0,47 série/semana e cai na faixa “nenhuma” (cinza), embora a pessoa tenha treinado. É o que a v1 especifica (`none` até 0,5), mas no mapa pode parecer que o treino não contou. Alternativas: deixar `none` só para zero (uma v2 com `none: [0, 0]`, sem mexer no código) ou manter e explicar na legenda.
- **Verificação**: 26 testes novos — a matriz inteira do DATA_MODEL §6 (sem histórico, período sem sessões, série sem reps, só primários, com secundários, drop de 3 segmentos no teto, rest-pause, aquecimento, sessão excluída depois, 7 vs. 30 dias, mudança de versão) mais limites das faixas, frequência, volume, treino em andamento, sem metodologia ativa (`503`), detalhe com período anterior e `404`; matriz de autorização com os 2 endpoints (o teste de mutação pega a remoção do filtro de dono). Contra a API real: um treino com supino (aquecimento e drop de 3 segmentos), tríceps na polia e prancha deu peito 2,0, tríceps 4,0, ombros 2,0, abdômen 2,0 e oblíquos 1,0, com volume de 900 kg no peito, conferidos à mão; conta de teste apagada.

### ADR-044 — Metodologia v2: a faixa “nenhuma” vale só para zero
**Status:** Aceita · Fase 3.5 (antes da 3.6)
**Contexto:** com a v1, um treino de peito em 30 dias (2 séries = 0,47 série/semana) caía em “nenhuma”, que o mapa do corpo pinta de cinza, como se o treino não tivesse contado.
**Decisões:**
- **v2 ativa** (migração 0012), igual à v1 exceto as faixas: `none: [0, 0]`, `low: [0, 6)`, `mid: [6, 12)`, `high: 12+`. Cinza passa a significar “nenhum estímulo registrado no período”. A v1 fica na tabela, inativa; o downgrade apaga a v2 e reativa a v1. Toda resposta já diz a versão usada.
- **Intervalo pontual em `band_for`**: `[x, x]` vale só para x exato e é verificado antes dos demais. Isso também tira a dependência da ordem das chaves, que o JSONB não guarda (ele devolve `high, low, mid, none`).
- **Faixa sobre o valor sem arredondar**: as séries por semana continuam arredondadas a 2 casas na resposta, mas a faixa usa o valor exato; senão 0,17 série em 366 dias (0,003 por semana) arredondaria para 0 e cairia em “nenhuma”. Na v1 isso só muda valores a menos de 0,005 de um limite.
- **Verificação**: 8 testes novos (limites da v2 nas duas ordens de chaves, um treino no mês = baixa na v2 e nenhuma na v1, faixa sem arredondamento) e a versão ativa nos testes da API; migração aplicada, desfeita e reaplicada no banco dev; contra a API real, 2 séries de supino em 30 dias deram peito 0,47/sem “baixa” e tríceps/ombros 0,23/sem “baixa”, com os demais em “nenhuma”; conta de teste apagada.

### ADR-045 — Meu Corpo 2D desenhado com `CustomPainter`, sem pacote de SVG
**Status:** Aceita · Fase 3.6
**Contexto:** o ADR-010 previa um `SvgBodyMapRenderer`. O Flutter não desenha SVG sem um pacote externo, e a orientação do projeto é não instalar dependências sem necessidade.
**Decisões:**
- **Formas próprias em Dart** (`analytics/presentation/body_map.dart`): cada músculo é uma lista de pontos da metade esquerda numa caixa de 200 × 440, espelhada e suavizada em curvas (Catmull-Rom → Bézier). O toque usa a própria forma (`Path.contains`), e a mesma função de escala serve aos testes. Continua valendo o ADR-010: o renderer só traduz `muscle_id` em região; um 3D pode substituí-lo sem mexer em cálculo.
- **Lado de cada músculo vem do catálogo** (`view` da API: `front`, `back`, `both`); um teste garante que todo músculo tem forma em cada lado em que aparece e que as formas não se sobrepõem.
- **Silhueta desenhada parte a parte**: o espelho inverte o sentido da curva, e num caminho único as sobreposições (tronco e coxa) viravam buracos — achado no emulador.
- **Acessibilidade**: a cor nunca é a única informação. A lista dos 13 músculos repete faixa e valor em texto e abre o mesmo detalhe; o mapa é lido como um resumo (“Peito, Baixo; …”).
- **Período escolhido**: `AnalyticsPeriod.range` (datas inclusivas; anterior do mesmo tamanho pelo calendário, imune a horário de verão); o app limita a 366 dias, como a API.
- **Calendário legível**: o tema não tinha `secondaryContainer`, e o intervalo do seletor usava a cor de ação (preto) como fundo, com os dias ilegíveis; o `DatePickerThemeData` passa a usar a superfície elevada (achado no emulador).
- **Verificação**: 7 testes de widget/unidade (cores pelas faixas, legenda, toque no mapa abre o detalhe com a consulta `compare=previous`, Costas, a lista virando o mapa, vazio, menor estímulo, formas do catálogo, faixas descritas, período escolhido) e o teste de estresse (fonte 200%, valores e nomes longos). No emulador EvoFit_Aceite com a API real, uma conta com treinos de hoje, de 2, 20 e 40 dias atrás: em 7 dias quadríceps e glúteos altos (12), tríceps (7), abdômen e posteriores (6) moderados, peito e ombros baixos; em 30 dias tudo baixo (peito 1,87); o detalhe do peito com 3680 kg de volume, cargas 55 → 60 kg e +1,4 série/semana (+298%) sobre o período anterior; de 2 a 31/out, peito 0,93 e ombros/tríceps 0,47 “baixo” (seriam cinza na v1). Conferido à mão; conta de teste apagada.

### ADR-046 — Gráficos com fl_chart e a tela Comparativos
**Status:** Aceita · Fase 3.7
**Contexto:** a Evolução da 3.4 tinha barras simples das 6 últimas semanas, e o detalhe do músculo (3.6) listava as cargas em texto. O roadmap previa o fl_chart (já avaliado no ASSESSMENT) para os gráficos e uma tela para comparar períodos.
**Decisões:**
- **fl_chart (^1.3.1)**, a única dependência nova: barras e linhas com toque, eixos e dicas prontos. Diferente do mapa do corpo (ADR-045), aqui um pacote evita reescrever eixos, toques e dicas. Dois componentes do app (`analytics/presentation/charts.dart`): `EvoBarChart` e `EvoLineChart`, no tema monocromático (preto sobre a superfície; o fundo da barra marca o teto).
- **Eixos legíveis:** três marcas (zero/mínimo, meio e teto). Barras vão do zero a um teto “redondo” (1, 2, 2,5 ou 5 × 10ⁿ); contagens (treinos, séries) usam teto par, para a marca do meio ser inteira. Linhas ficam perto dos valores, com passos redondos — números (0,5; 1; 2; 2,5; 5…) ou tempo (5 s, 10 s, 15 s, 30 s, 1 min…) —, para variações pequenas como carga e pace aparecerem. Rótulos de data curtos (“12/10”), no máximo 6 no eixo; achados no emulador (as datas longas grudavam e o eixo do pace mostrava “3:08”).
- **Sem dado não vira zero:** semana sem distância fica fora da linha do pace; o ritmo só ganha gráfico com 2 semanas medidas.
- **Acessibilidade:** cada gráfico é lido como uma frase (“Treinos por semana. Semana de 12 de out.: 1 treino; …”) e o texto ao lado continua dizendo os totais; na comparação, A e B se distinguem pela letra (contorno × preenchida), não só pela cor.
- **API:** só um acréscimo compatível — `strength_sets` e `strength_volume_kg` por semana em `/analytics/overview`. Os Comparativos usam o `/analytics/compare` existente (um pedido por indicador, depois das visões gerais dos dois períodos para saber quais modalidades houve); diferença, percentual e “melhor” vêm da API, o app só formata.
- **Atalho “Este mês”:** do dia 1 até hoje contra o mesmo trecho do mês passado (mês inteiro contra mês pela metade não seria justo), cortado no último dia do mês mais curto.
- **Verificação:** 7 testes novos (gráfico semanal e troca de indicador, distância e pace da corrida, natação e caminhada sem distância, Comparativos com a ordem dos pedidos e as frases — inclusive “mais rápido” no pace —, vazio, atalhos de período com fevereiro e virada de ano, eixos e frases; 1RM no histórico do exercício) e o teste de estresse dos Comparativos (fonte 200%, valores enormes). No emulador EvoFit_Aceite com a API real, uma conta com 6 treinos de supino (50 → 62,5 kg) e 4 corridas: em 30 dias 7 registros e as barras 1, 1, 1, 1, 3; em 90 dias as 14 semanas e 17500 kg; distância 5, 6, 8 e 5 km e pace 6:24 → 5:24 /km; Comparativos de 30 dias com 6 → 29 séries, 2560 → 14940 kg, 5 → 19 km e pace 6:24 → 5:44 (−10%, “mais rápido”); Este mês e um período escolhido; cargas 50 → 62,5 kg no detalhe do peito; 1RM 63,3 → 79,2 kg no histórico. Conferido à mão; conta de teste apagada.
