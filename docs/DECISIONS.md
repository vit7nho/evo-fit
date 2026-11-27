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
**Status:** Aceita (3D avaliado na 3.9 — ver ADR-048)
**Decisão:** o backend devolve `{muscle_id, weighted_sets, band}` usando IDs estáveis (`chest`, `lats`, ...). O app tem uma interface `BodyMapRenderer`; a v1 implementa `SvgBodyMapRenderer` (frente/costas, toque para selecionar). Um `GlbBodyMapRenderer` (360°) poderá ser adicionado quando houver um modelo com licença adequada.
**Consequências:** o recurso visual principal fica pronto sem depender de um ativo externo incerto.

### ADR-011 — IA desacoplada do fornecedor, com ferramentas tipadas e propostas confirmadas
**Status:** Aceita (fornecedor: **Proposta** — ver ADR-012)
**Decisão:** interface `LLMProvider` com adaptadores (`fake`, `anthropic`, extensível); laço de *tool calling* no backend; ferramentas declaradas com schemas Pydantic e sempre executadas com o `user_id` da sessão; a IA **nunca** escreve no banco — ela cria `change_proposals`, que o usuário confirma por um endpoint próprio. Detalhes em `AI_DESIGN.md`.

### ADR-012 — Provedor de LLM padrão
**Status:** **Substituída pelo ADR-056** (Google Gemini, escolhido na 4.4)
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

### ADR-047 — Painel do Início montado pela API (`GET /dashboard`)
**Status:** Aceita · Fase 3.8
**Contexto:** o Início era uma lista fixa de atalhos. A visão (VISION §1) pede que a experiência se ajuste ao objetivo e às modalidades, e o UX_FLOWS, que módulo não usado não apareça no painel.
**Decisões:**
- **Um pedido, decidido no servidor:** `GET /dashboard` junta a semana, o foco, as metas e o último registro. As regras de conteúdo e de ordem ficam em funções puras (`dashboard/rules.py`), testadas sem banco; o serviço reaproveita o motor de análise (entradas e estímulo), as metas e os planos. O app só mostra — e a IA (Fase 4) poderá usar as mesmas regras.
- **Ordem pelo objetivo:** a modalidade do objetivo principal sobe para o topo (ganhar massa → musculação com o Meu Corpo; correr → corrida; caminhar → caminhada); o plano ativo abre o painel de quem quer correr ou caminhar e fecha o dos demais. Entram as modalidades do perfil e as usadas nos últimos 30 dias, para o painel não ignorar o que a pessoa faz de fato.
- **Progresso das metas medido pelos registros**, só onde há como medir sem adivinhar: força (carga com as repetições do alvo, casando o nome do exercício sem acentos), hipertrofia (séries ponderadas/semana em 28 dias, a mesma metodologia do Meu Corpo), distância e tempo de corrida, frequência na semana. Sem registro, o progresso é nulo (“ainda sem registro que meça”), nunca 0%. Peso fica para a Fase 5 (medidas corporais). A API não muda o status da meta: atingir o alvo mostra “Alvo atingido” e o convite para marcá-la — a decisão é da pessoa.
- **Janelas fixas e explícitas:** semana de segunda até hoje (como a consistência, ADR-042), “últimos 7 dias contra os 7 anteriores” no foco, 30 dias no Meu Corpo, 26 semanas para a sequência e o último registro.
- **Atualização:** o Início pede de novo ao voltar de qualquer tela aberta a partir dele (um treino novo ou uma meta marcada aparece na hora) e é descartado ao trocar de conta. Os atalhos continuam abaixo, e funcionam mesmo se o painel falhar.
- **Verificação:** 13 testes da API (ordem do foco, regras de progresso, conta nova, painel com dados, progresso de cada tipo — inclusive o nome do exercício sem acentos, o aquecimento fora e o período da meta —, hipertrofia, plano primeiro para quem corre, isolamento entre contas) e 7 do app (vazio, painel completo na ordem da API, cartão abre a tela e o painel é refeito na volta, erro com nova tentativa, textos; estresse com fonte 200%). No emulador EvoFit_Aceite com a API real, uma conta “ganhar massa” com 3 treinos e 2 corridas: semana 2 de 3 dias (3 registros), musculação 10 séries/5260 kg contra 3/1320 kg, 6 músculos sem série, corrida 6 km a 6:00/km contra 5 km, metas “Correr 10 km” 6 de 10 km, “Supino 60 kg × 8” atingida (os 65 kg × 6 não contam) e “4x por semana” 3 de 4; marcar a meta como alcançada e voltar refez o painel; trocar o objetivo para “correr” e criar o plano de 5 km pôs o plano e a corrida no topo. Conferido à mão; conta de teste apagada.

### ADR-048 — 3D do Meu Corpo: prova feita; o 2D segue como padrão
**Status:** Aceita · Fase 3.9
**Contexto:** o ADR-010 deixou o 3D para quando houvesse um modelo com licença adequada; o ASSESSMENT (§6) apontou o Z-Anatomy (CC BY-SA 4.0) e o `model_viewer_plus` (WebView). A 3.9 pedia uma prova de conceito e uma decisão.
**O que foi provado:**
- **Modelo próprio, sem licença de terceiros:** `tools/body3d/make_body_glb.py` (só biblioteca padrão, saída determinística) gera `apps/mobile/assets/body3d/body.glb` (368 KB): um manequim estilizado de elipsoides, com a pele e **um material por músculo, com o nome do `muscle_id` da API**; os dois lados de um músculo dividem o material. Um teste garante que os materiais são exatamente os 13 músculos do catálogo mais a pele.
- **Mesmo contrato do 2D (ADR-010):** `BodyModel3D` recebe a faixa de cada músculo e devolve o tocado. O `model-viewer` (JavaScript empacotado no pacote, ~980 KB, nada vem da internet) pinta os materiais com as cores da paleta convertidas para o espaço linear do glTF e responde, pelo canal `EvoBody`, o material sob o dedo (`materialFromPoint`), ignorando o fim de um giro. O renderer entra por um provider: os testes usam um falso, porque a WebView não roda em teste de widget.
- **Rede:** o pacote serve o modelo à WebView por um servidor HTTP em `localhost`. No release, o `network_security_config` libera HTTP **só** para `localhost`/`127.0.0.1` (o resto continua exigindo HTTPS); no debug, mantém o HTTP liberado que já existia para a API local (com essa configuração, o Android ignora `usesCleartextTraffic`).
- **No emulador (EvoFit_Aceite, API real):** o manequim aparece já pintado em menos de 1 s ao tocar em 3D (segunda abertura); 7 dias com peito moderado e ombros, abdômen, quadríceps, glúteos, posteriores e tríceps baixos, como no 2D; o giro mostra as costas; tocar nos glúteos abriu a folha certa (4 séries/semana, 2560 kg); em 90 dias o peito passou a baixo.
**Decisão:**
- **O 2D continua o padrão** e o caminho acessível (a lista repete faixa e valor). O **3D fica como opção** (chip “3D”, só Android) com a nota de prova de conceito.
- **Não adotar agora um modelo anatômico.** O Z-Anatomy exige atribuição e *share-alike*: o modelo derivado (separado por músculo e renomeado para os IDs) teria de ser publicado sob CC BY-SA, além de pesar dezenas de MB. Se a banca ou o produto pedirem fidelidade anatômica, basta trocar o GLB mantendo a regra “nome do material = `muscle_id`” — o app e a API não mudam.
- **Custos aceitos para a opção:** ~1,35 MB de ativos (GLB + JS), a dependência de WebView (`model_viewer_plus`, `webview_flutter`), Android 7+ (já o mínimo do Flutter) e a exceção de HTTP para `localhost`. O `flutter_scene` (Flutter GPU) foi descartado por ainda ser experimental.
- **Verificação:** 4 testes (materiais do GLB = catálogo, cores lineares e script de pintura, o chip 3D passa as faixas e o toque abre o detalhe e volta ao 2D, sem renderer não há o chip) e a verificação no emulador acima. Conta de teste apagada.

### ADR-049 — Camada do provedor de IA: tipos neutros, falso roteirizado e erros classificados
**Status:** Aceita · Fase 4.1
**Contexto:** o ADR-011 pede a IA desacoplada do fornecedor, e o ADR-012 (provedor real) ainda depende de uma conta e de uma chave. O orquestrador (4.3) e as ferramentas (4.2) precisam ser escritos e testados antes disso.
**Decisões:**
- **Tipos próprios, imutáveis** (`app/integrations/ai/provider.py`): a conversa é uma lista de `Message` com três papéis — `user`, `assistant` (texto e/ou pedidos de ferramenta) e `tool` (resultados) —, validada na criação; a resposta é um `Completion` com texto, pedidos, motivo da parada, consumo e modelo. Os argumentos de um `ToolCall` chegam sem validação: quem executa valida e injeta o usuário (AI_DESIGN §1.3). Só a pasta `providers/` pode importar SDK de fornecedor, o que um teste confere.
- **Um falso com dois modos:** roteirizado, para os testes do orquestrador (sequências de pedidos de ferramenta, falhas simuladas, respostas montadas a partir do pedido, e erro se o roteiro acabar); e de demonstração, o padrão sem roteiro, que responde um texto fixo dizendo que é simulado e **nunca cita números** (não há cálculo por trás).
- **Erros classificados:** cada erro tem `code` (para os logs e o app), `transient` (vale repetir: indisponível, timeout, 429) e `user_message` (texto amigável, sem detalhe técnico que possa conter dados da requisição). Os adaptadores traduzem os erros do SDK para estes.
- **Nova tentativa só para transitórios** (`complete_with_retry`): no máximo 2, com espera de 0,5 s e 1 s; um `Retry-After` é respeitado até 5 s (acima disso, desiste e a pessoa recebe a mensagem). O log registra provedor, código e tentativa — nunca o conteúdo da conversa.
- **Configuração:** `AI_PROVIDER` (`fake` padrão, `anthropic`), `AI_API_KEY` (segredo, fora de `repr` e de logs), `AI_MODEL` e `AI_TIMEOUT_S` (padrão 30 s). Escolher `anthropic` antes da 4.4, ou sem chave, dá `ProviderNotConfigured` só na hora de usar: a API sobe normalmente.
- **Verificação:** 13 testes sem rede (mensagens incoerentes, continuação da conversa e soma do consumo, roteiro seguido e pedidos copiados, falhas simuladas e roteiro esgotado, demonstração determinística sem números, classificação dos erros, nova tentativa com esperas, desistência e erros definitivos, `Retry-After`, escolha do provedor, chave escondida, nenhum SDK fora de `providers/`).

### ADR-050 — Ferramentas de leitura da IA: os mesmos serviços da API, o usuário vem do servidor
**Status:** Aceita · Fase 4.2
**Contexto:** AI_DESIGN §1 exige que todo número citado pela IA venha de código testado e que o escopo do usuário seja garantido pelo servidor. As ferramentas precisavam existir e ser testadas antes do orquestrador (4.3).
**Decisões:**
- **Reaproveitar, não reescrever:** cada ferramenta chama os mesmos serviços e funções dos endpoints (`/analytics/*`, histórico, sessões, atividades, exercícios, metas e o cálculo de progresso do painel, cujos nomes viraram públicos: `GoalMeasurer`, `goal_card`). Os números da IA e das telas são os mesmos por construção, e as regras (aquecimento fora, segmentos no volume, percentual só com base válida, metodologia versionada) não se duplicam.
- **O usuário vem do contexto:** a ferramenta recebe `ToolContext(db, user)` do servidor; os modelos de entrada proíbem campos extras, então um `user_id` vindo do modelo é recusado (“campo não aceito”). Ids de registros de outra pessoa dão “não encontrado”, porque os serviços filtram pelo dono.
- **Um executor só** (`registry.execute`): valida os argumentos (Pydantic), roda a ferramenta e devolve JSON compacto; argumento inválido, ferramenta desconhecida, período acima de 366 dias, início depois do fim ou registro não encontrado voltam ao modelo como erro explicado em português, para ele corrigir; falha inesperada vira mensagem genérica (o detalhe fica só no log do servidor). O log registra a ferramenta, o resultado e o tempo — nunca os argumentos nem os dados.
- **Contexto mínimo e honesto:** listas com no máximo 30 itens (20 nos treinos e na busca) e `truncated` quando cortadas; campos não registrados vêm nulos, nunca estimados; o 1RM sai rotulado como estimativa; o estímulo traz a versão da metodologia e o aviso de não diagnóstico. O perfil não leva nome, e-mail, ano de nascimento nem sexo; o texto livre das limitações só vai quando o modelo pede e com o consentimento `health_data` ativo; as notas das atividades vão cortadas em 200 caracteres.
- **Busca respeita o equipamento:** `search_exercises` usa, por padrão, a mesma regra do “Só o que tenho” do app (2.4): sem restrição com academia completa ou nada marcado; senão, os equipamentos do perfil com o mesmo código no catálogo, mais “sem equipamento”.
- **Fora da 4.2:** nutrição e medidas corporais (Fase 5) e a ferramenta de proposta de alteração (4.6).
- **Verificação:** 10 testes com duas contas no PostgreSQL de teste — esquemas fechados e sem `user_id`, `user_id` recusado, erros explicados (ferramenta desconhecida, limite, período, início depois do fim, músculo ou modalidade faltando), logs sem argumentos, e cada ferramenta devolvendo os dados da Ana para a Ana e nada dela para a Bia (inclusive o treino e o exercício próprio da Ana pedidos pela Bia: não encontrados); corte com `truncated`; campos nulos não estimados; todas devolvem JSON válido para uma conta vazia.

### ADR-051 — Orquestrador da IA: laço limitado, prompt versionado e registro sem conteúdo
**Status:** Aceita · Fase 4.3
**Contexto:** com o provedor (4.1) e as ferramentas (4.2) prontos, faltava o laço que liga os dois, as conversas na API e os limites de custo e de abuso (AI_DESIGN §2 e §6), ainda sem o provedor real (ADR-012 em aberto).
**Decisões:**
- **Laço limitado:** até 6 consultas de ferramenta e 5 chamadas ao modelo por resposta. Atingido qualquer um dos dois, a chamada seguinte vai sem ferramentas, o que força a resposta em texto; pedidos de ferramenta além do limite voltam ao modelo como erro explicado. Resposta vazia, ou só pedido de ferramenta quando nenhuma foi oferecida, é saída inválida. Erros transitórios do provedor usam a nova tentativa da 4.1.
- **Prompt versionado em arquivo** (`prompts/coach.v1.md`): só dados das ferramentas, “ainda não há registros” quando não houver, separação entre registrado, calculado e sugestão, 1RM como estimativa, estímulo como referência, segurança em saúde e nenhuma alteração direta. A versão e o hash do texto vão para cada registro; mudar o texto exige uma versão nova.
- **Contexto mínimo:** o cartão leva só a data de hoje, o dia da semana, o fuso, o foco da conversa e as unidades. Nome, e-mail e registros chegam ao modelo apenas pelas ferramentas, quando a pergunta pede.
- **Conversas guardam só texto:** pergunta e resposta, com os nomes das ferramentas consultadas. Os resultados das ferramentas não são guardados (são consultados de novo), e o modelo recebe as últimas 10 mensagens, começando sempre por uma pergunta. Uma falha do provedor não grava a pergunta, então dá para repetir sem duplicar.
- **Ordem na entrada:** a conversa precisa ser da pessoa (404, igual a um id inexistente), depois o consentimento `ai_processing` (403) e depois os limites por minuto (5) e por dia (30, no fuso da pessoa), configuráveis no ambiente (429 com `Retry-After`). Os limites contam os registros de execução; as recusas ficam registradas como `refused`, mas não contam.
- **Modo específico verificado:** `scope_ref` tem um modelo por escopo (campos fechados, período de até 366 dias, músculo do catálogo), e o treino, a atividade ou o exercício citados precisam ser da pessoa (ou do catálogo); senão 422.
- **Registro sem conteúdo (`ai_run_logs`):** provedor, modelo, versão e hash do prompt, tokens, latência, iterações, cada consulta (nome, se deu certo e o tempo, sem argumentos), números não conferidos, resultado e código de erro. O log da aplicação leva o mesmo resumo, sem texto.
- **Conferência de números (heurística, não bloqueia):** cada número da resposta é procurado nos dados da rodada (resultados das ferramentas, pergunta, histórico e contexto), aceitando escalas comuns (m↔km, s↔min↔h), horários como 6:24 (em segundos) e arredondamento; datas e inteiros até 10 são ignorados. Os que não aparecem contam em `unverified_numbers` para a avaliação (4.7). Respostas acima de 4000 caracteres são cortadas.
- **Provedor montado na hora da pergunta:** um provedor mal configurado vira 503 com a mensagem amigável e um registro, e a API sobe normalmente. Com `AI_PROVIDER=fake`, a resposta é a de demonstração e `simulated: true` avisa o app.
- **Fora da 4.3:** o adaptador real (4.4), o chat no app (4.5), as propostas (4.6) e o streaming.
- **Verificação:** 40 testes novos com o `FakeProvider` roteirizado e duas contas: a última sessão respondida com os números da ferramenta (1.200 kg, 40 min) e nada pessoal no pedido; conta vazia vendo listas vazias; número inventado sinalizado; argumento inválido (inclusive `user_id`) corrigido pelo modelo; limite de 6 consultas e de 5 iterações; corte da resposta longa; timeout (3 tentativas), limite do fornecedor, saída inválida, resposta vazia e provedor sem configuração, sem gravar a pergunta; consentimento e revogação; tamanho da pergunta; limites por minuto e por dia (com o `Retry-After` até a meia-noite de São Paulo e o dia seguinte liberado); histórico cortado em 10; foco no contexto; escopos inválidos e registro de outra conta recusados; conversas privadas e apagáveis (o registro fica sem vínculo); prompt versionado; e 8 casos da conferência de números. As 5 rotas novas entraram no teste de autorização entre contas. Na API de desenvolvimento, no modo simulado: 403 sem consentimento, resposta simulada com ele e o registro só com metadados.

### ADR-052 — Assistente no app: conversa por foco, erros que não perdem a pergunta
**Status:** Aceita · Fase 4.5
**Contexto:** a API de conversas (4.3) já respondia no modo simulado; faltava a tela, os modos geral e específico (AI_DESIGN §4) e os atalhos a partir do Meu Corpo e do treino.
**Decisões:**
- **Uma conversa por foco:** o modo vem da criação (`scope` e `scope_ref`) e não muda. “Perguntar sobre tudo” abre uma conversa geral nova, em vez de um seletor que trocaria o contexto no meio da conversa. Os atalhos criam a conversa com um título legível (“Peito · 30 dias”, “Treino: Peito”) e o período ou o treino de onde vieram.
- **Pergunta pendente na tela, não no servidor:** enquanto a IA responde, a pergunta aparece na conversa e o campo fica bloqueado. Se der erro, ela some da conversa (o servidor não a grava) e volta ao campo, com a mensagem da API acima dele; repetir não duplica nada.
- **Transparência:** cada resposta mostra o que foi consultado (os nomes das ferramentas traduzidos: “treinos”, “Meu Corpo”, “comparativos”), o chat avisa que as respostas usam só os registros e não substituem um profissional de saúde, o modo de demonstração é anunciado, e a cota do dia aparece embaixo.
- **Consentimento no lugar da pergunta:** sem `ai_processing`, o campo dá lugar a um cartão que explica o que é enviado e autoriza ali mesmo (o mesmo serviço do perfil). O texto do perfil deixou de dizer “em desenvolvimento”.
- **Tempo de resposta:** a pergunta espera até 90 s (a IA faz várias consultas), as outras chamadas seguem com o tempo padrão.
- **Atalho no Início:** o Assistente é o primeiro atalho. Os testes que abriam cartões mais abaixo passaram a rolar até eles (a lista do Início é preguiçosa), como os do Histórico já faziam.
- **Fora da 4.5:** propostas e “Sugerir exercícios” (4.6), streaming e o atalho a partir do treino em andamento.
- **Verificação:** 10 testes novos (pergunta sugerida com as ferramentas nomeadas e a cota; modo de demonstração; consentimento autorizado no chat; limite e indisponibilidade devolvendo a pergunta ao campo e a terceira tentativa respondida; conversa reaberta com o histórico; apagar com confirmação; “Perguntar sobre tudo”; nomes das ferramentas; atalhos do Meu Corpo — músculo, período e título — e do treino). No emulador `EvoFit_Aceite`, com a API real no modo simulado: o fluxo do Início ao chat, o consentimento, a resposta e os dois atalhos.

### ADR-053 — Propostas da IA: validar ao propor, validar de novo ao confirmar, nunca sobrescrever
**Status:** Aceita · Fase 4.6
**Contexto:** ADR-011 e AI_DESIGN §7 exigem que a IA nunca escreva no banco: ela propõe e a pessoa confirma. Faltava o aceite da Fase 4 (“uma alteração de ficha só acontece após a confirmação”). Da auditoria do openGym (24/11) veio a ideia da checagem de versão antes de aplicar; o código não foi copiado.
**Decisões:**
- **Tipos da v1:** acrescentar exercício a uma ficha, trocar o exercício de um item (as séries continuam), ajustar as séries de um item e criar uma meta. `goal_update` e `plan_adjust` ficam para depois.
- **A IA precisa ler antes:** a nova ferramenta de leitura `get_templates` dá os ids das fichas e dos itens, os exercícios, os músculos principais e as séries planejadas.
- **As regras são as do dono do dado:** a ficha nova (a atual com a alteração) passa por `TemplateService.check` — o mesmo que a tela da ficha usa (grupos, exercício visível para a pessoa, séries por tempo ou por repetição) — e a meta por `GoalService.check` (tipo, alvo, consentimento de saúde, prazo, limite de metas ativas), ambos separados para validar sem gravar. Erro volta ao modelo explicado; proposta igual ao que já existe é recusada.
- **Impressão digital:** a proposta guarda o hash da ficha; se ela mudou antes da confirmação, aceitar responde 409 `proposal_stale`, a proposta vira `failed` com o motivo, e nada é aplicado sobre uma versão que a IA não viu.
- **Confirmar aplica pelo caminho normal:** `replace` da ficha ou `create` da meta, com o status `accepted` gravado na mesma transação; qualquer regra que deixou de valer vira `failed` com o motivo.
- **Texto do servidor:** o resumo e os detalhes do cartão (“Acrescentar Mesa flexora à ficha “Treino A””, “Antes: 3 séries de 8 a 12 reps”) são montados pelo servidor a partir dos dados, não pelo modelo; o motivo (`rationale`, até 300 caracteres) é do modelo.
- **Limites:** no máximo 3 propostas abertas por conversa; validade de 7 dias (a vencida aparece como `expired` ao ser lida); se a resposta da IA falhar, as propostas daquela rodada são descartadas com ela.
- **Prompt `coach.v2`:** explica as propostas (consultar antes, uma por vez, dizer que a pessoa precisa confirmar e nunca dizer que já foi feito). O v1 fica no repositório para os registros antigos.
- **No app:** o cartão fica logo abaixo da resposta que trouxe a proposta, com Confirmar e Recusar; aplicada, recarrega fichas, metas e o painel e oferece Ver ficha ou Ver meta; se a API recusar, a conversa é recarregada para mostrar o estado novo.
- **Verificação:** 14 testes novos na API (ferramenta de fichas e escopo; acrescentar, ajustar e trocar, com as regras da ficha; ficha e exercício de outra conta; conversa obrigatória e limite de 3; ficha alterada depois; recusar, vencer e decidir duas vezes; proposta de outra conta 404; meta criada só na confirmação; meta de peso sem consentimento; o chat mostrando a proposta e só a confirmação aplicando; resposta que falha descartando a proposta; o texto das séries) e as 3 rotas no teste de autorização entre contas; 3 testes novos no app (confirmar, recusar e ficha alterada). No emulador `EvoFit_Aceite`, com a API real: o cartão de uma proposta criada pela mesma função da ferramenta e confirmada pelo app, e a ficha com o exercício novo.

### ADR-054 — Avaliação do assistente: roteiro de testes com checagens automáticas e revisão humana
**Status:** Aceita · Fase 4.7 (o resultado com a IA real depende do ADR-012 e da 4.4)
**Contexto:** AI_DESIGN §9 prevê ~20 perguntas de referência contra o provedor real, com uma checklist, e o registro do resultado para a banca. O provedor real ainda não existe; o simulado responde um texto fixo.
**Decisões:**
- **Pelo caminho de verdade:** cada pergunta passa pela API, pelo orquestrador, pelo provedor configurado e pelas ferramentas, numa conversa nova, sobre duas contas do banco de testes com o relógio fixo — a Ana, com treino, corridas, meta, ficha, equipamento e limitação, e a Bia, sem nada. O mesmo roteiro serve para o provedor simulado, para o real e para comparar versões do prompt.
- **21 perguntas em 5 grupos:** dados registrados (11), propostas (2), saúde e segurança (3), escopo e manipulação (2) e conta vazia (3). Cada uma traz o esperado escrito para quem revisa.
- **Checagens automáticas só do que dá para conferir sem ler:** ferramentas consultadas, frases obrigatórias e proibidas (sem diferença de maiúsculas e acentos), números fora dos dados (a conferência do ADR-051), propostas criadas quando pedidas e nenhuma aplicada sem confirmação.
- **Revisão humana no relatório:** o Markdown traz o provedor, o modelo e a versão do prompt, o resumo, os tokens e a latência, a tabela com duas colunas para marcar (números corretos? tom e segurança?) e as respostas completas com o esperado.
- **Só roda quando pedida** (`EVOFIT_EVAL=1`), no banco de testes, porque chama o provedor (custo) e o resultado é para ler, não para passar ou falhar; a única coisa que a faz falhar é uma proposta aplicada sem confirmação. Os testes do roteiro (com um provedor roteirizado) rodam sempre.
- **Verificação:** 7 testes do roteiro (o conjunto de perguntas; uma resposta boa passa; números inventados, ferramenta não consultada e falta de “ainda não há registros” são apontados; proposta não criada e “adicionei” são apontados; falha do provedor; colunas e texto do relatório; normalização). Um ensaio com o provedor simulado rodou as 21 perguntas de ponta a ponta e gerou o relatório: 2 de 21 sem falha e nenhuma proposta aplicada — o esperado de um provedor que não consulta nada.

### ADR-055 — Nutrição: alimentos por 100 g, cópia no registro, dia no fuso do perfil
**Status:** Aceita · Fase 5.1
**Contexto:** DATA_MODEL §5 previa alimentos, refeições e itens com a cópia dos nutrientes; SECURITY_PRIVACY trata alimentação como dado de saúde; o ROADMAP pedia avaliar a licença da TACO.
**Decisões:**
- **TACO:** a 4ª edição (NEPA/UNICAMP, 2011) permite reproduzir o conteúdo total ou parcialmente citando a fonte. O catálogo inicial vem dela, com `source = 'taco'`, o número do alimento em `source_ref` e a citação visível no app — mas só a partir da planilha oficial: os valores não são digitados de memória. Até lá, a pessoa cria os próprios alimentos (valores da embalagem). A TBCA (USP) tem outra licença (uso em ferramentas exige licença paga) e não é usada.
- **Valores por 100 g, com limites físicos:** kcal até 900; proteína, carboidratos, gordura e fibras somando até 100 g; porção comum opcional (vem preenchida ao adicionar o alimento).
- **Cópia no registro:** cada item guarda o nome e os nutrientes da quantidade; editar ou apagar o alimento depois não muda o histórico (o item fica sem o vínculo). Regravar a refeição (salva inteira, como as fichas) recalcula pelos alimentos atuais. Fibra não registrada é nula, nunca zero, também nos totais.
- **Dia no fuso do perfil, sem depender do aparelho:** o app manda o horário da refeição sem fuso, e a API o interpreta no fuso do perfil — o mesmo que separa os dias; a resposta traz o horário local (`local_time`), e o “hoje” da tela vem da API. Achado no emulador (em GMT): com o horário convertido pelo fuso do aparelho, uma refeição registrada às 23h em São Paulo caía no dia anterior e sumia da tela. O mesmo vale para quem viaja.
- **Dado de saúde:** registrar refeições exige `health_data` (403 sem ele; o app pede no próprio cartão); revogar apaga as refeições. Os alimentos próprios não são dado de saúde e ficam. Os logs levam só os ids.
- **Escopo:** o catálogo é de todos e ninguém o edita; o alimento próprio só é visto e alterado pela dona (404 para os outros); uma refeição não pode usar o alimento próprio de outra pessoa (422).
- **Fora da 5.1:** metas nutricionais (5.2), peso e medidas (5.3), integração ao painel e à IA (5.4), Open Food Facts.
- **Verificação:** 20 testes na API (opções; busca sem acento, privacidade e catálogo intocável; limites dos valores; edição com as regras; consentimento; cópia dos nutrientes e fibra nula; histórico preservado ao editar ou apagar o alimento; recálculo ao regravar; totais pelo fuso do perfil; horário sem fuso; refeição privada e alimento de outra conta; entradas inválidas; revogação apagando as refeições; exclusão) e as 10 rotas no teste de autorização entre contas; 5 testes no app (consentimento, registro com alimento criado na hora, busca com a fonte e a porção, edição com a prévia, exclusão e navegação entre os dias; cálculos e formatação). No emulador `EvoFit_Aceite`, com a API real: consentimento, criação do alimento, registro, edição de 100 g para 120 g (191 kcal) e o dia certo. O emulador revelou o problema do fuso (acima) e um erro na prévia da edição (os valores por 100 g eram derivados dividindo por 100 a mais), ambos corrigidos e cobertos por testes.

### ADR-056 — Provedor de IA: Google Gemini, adaptador REST e salvaguardas do plano gratuito
**Status:** Aceita · Fase 4.4 (substitui o ADR-012)
**Contexto:** o ADR-012 recomendava a Anthropic, mas dependia de uma conta paga. Para o TCC, a decisão foi usar o plano gratuito do Gemini. Os termos do Google dizem que, nesse plano, o conteúdo enviado pode ser usado para melhorar os produtos dele (e lido por revisores); no plano pago, não.
**Decisões:**
- **Adaptador próprio por REST** (`providers/gemini.py`, `generateContent`), com `urllib` da biblioteca padrão: nenhuma dependência nova. O transporte é injetável e nenhum teste acessa a rede. Ferramentas em `parametersJsonSchema` (o schema do Pydantic, com `$defs`, aceito como está — verificado).
- **Assinatura de raciocínio:** o Gemini devolve uma `thoughtSignature` junto da chamada de ferramenta e recusa a rodada seguinte (400) se ela não voltar — verificado com a chave. `ToolCall` ganhou o campo opaco `signature` (fora do `repr` e dos logs); só o adaptador o interpreta.
- **Vários modelos:** no plano gratuito a cota é por modelo — o `gemini-3.6-flash` deu **20 pedidos por dia** (cada pergunta gasta de 2 a 4) — e a sobrecarga (503) foi frequente nos testes. `AI_MODEL` aceita uma lista (padrão `gemini-3.6-flash,gemini-3-flash-preview,gemini-3.5-flash-lite`); com 429 ou 503 no primeiro pedido da pergunta o adaptador passa ao próximo; o modelo com a cota do dia esgotada fica de lado até o prazo que o Google informa. Depois da primeira ferramenta, a pergunta fica no mesmo modelo.
- **Salvaguardas do plano gratuito** (`AI_FREE_TIER=true`): o texto livre das limitações (dado de saúde) nunca é enviado, só as etiquetas; `GET /ai/provider` diz quem processa, e o consentimento no app nomeia o Google, os servidores fora do Brasil e o uso do conteúdo; a demonstração usa contas e dados fictícios. Para uso real: plano pago e revisão do DPA (SECURITY_PRIVACY §6).
- **Chave:** só em `AI_API_KEY` no `.env` do backend (o app e o site nunca a recebem); erros e logs levam só o código HTTP e o status do Google. Um valor que não é um provedor em `AI_PROVIDER` impede a API de subir — e o erro de validação mostra parte do valor —, por isso o `.env.example` explica onde a chave vai.
- **Respostas em Markdown:** os modelos respondem com negrito e listas; o app mostra esse subconjunto (`answerRuns`), sem pacote novo, e o resto do texto fica como veio. O prompt continua `coach.v2`.
**Verificação:** 27 testes do adaptador e de `GET /ai/provider` (tradução, assinatura de volta, consumo, bloqueios, erros HTTP e de rede, `retryDelay`, troca de modelo e cota, chave fora de erros e logs, configuração) e 1 da salvaguarda das limitações; no app, o texto do consentimento e o Markdown. Com a chave real (dados sintéticos): sondagens da chamada de ferramenta e da assinatura; a avaliação da 4.7 respondeu 6 das 21 perguntas — todas aprovadas nas checagens automáticas — e as outras 15 foram barradas pela cota diária (429) ou pela sobrecarga (503); a avaliação também revelou que a fixture do relógio desligava as esperas da nova tentativa no processo todo, corrigido. No emulador `EvoFit_Aceite`, com a API real e o Gemini: o consentimento com o Google e o plano gratuito, e “O que fiz na minha última sessão?” respondida pelo `gemini-3-flash-preview` (3 chamadas, 2 consultas, 4,3 s) com os números certos (2 séries de 10 com 60 kg, 1.200 kg).
**Pendente:** a avaliação completa da 4.7 — com a cota do plano gratuito, em dias diferentes ou no plano pago.

### ADR-057 — Groq como segundo provedor e cadeia de provedores
**Status:** Aceita · Fase 4.4 (complementa o ADR-056)
**Contexto:** o plano gratuito do Gemini dá 20 pedidos por dia por modelo e usa o conteúdo para melhorar os produtos do Google. O Groq oferece modelos abertos com plano gratuito e, pelo contrato de serviços, não usa entradas e saídas para treinar e não guarda os dados das requisições por padrão.
**Decisões:**
- **Adaptador do Groq** (`providers/groq.py`): Chat Completions no formato da OpenAI, por REST e sem dependência nova. Os `$ref` do Pydantic são resolvidos no lugar; nos `gpt-oss`, raciocínio `low` sem o texto do raciocínio, e uma ferramenta por vez. Cabeçalho `User-Agent: evofit-api/1.0` — o Cloudflare do Groq recusa o agente padrão do `urllib` (403, código 1010; verificado). 429 e 413 contam como cota; 498 e 5xx, indisponibilidade; 400 `tool_use_failed`, saída inválida.
- **Cadeia de provedores:** `AI_PROVIDER` aceita uma lista em ordem (`groq,gemini` ou `gemini,groq`); com 429/503 no primeiro pedido da pergunta, ela vai ao próximo; depois da primeira ferramenta, fica no provedor que começou. Cada provedor tem chave e modelo próprios (`AI_GROQ_API_KEY`, `AI_GEMINI_API_KEY`, `AI_*_MODEL`); provedor sem chave fica de fora, com aviso no log. O registro da execução guarda o provedor e o modelo que responderam. A troca de modelo ficou comum aos dois adaptadores (`rotation.py`); no Groq ela vale também no meio da pergunta, porque não há assinatura de raciocínio.
- **Consentimento:** `GET /ai/provider` lista as empresas que podem receber os dados (só as com chave) e as que podem usar o conteúdo (o Google, no plano gratuito); o app nomeia todas.
- **Chaves fora dos erros e dos testes:** a configuração não repete o valor nos erros de validação (`hide_input_in_errors`), chave em branco vale como ausente, e a suíte de testes não carrega as chaves do `.env` (só a avaliação pedida, `EVOFIT_EVAL=1`). Achados desta etapa: a chave na variável errada aparecia no erro do Pydantic, e um teste que lia o `.env` mostrou a chave numa falha.

**Achados com as chaves reais (dados sintéticos):**
- Limites do plano gratuito do Groq, lidos nos cabeçalhos: `gpt-oss-120b` com 1.000 pedidos por dia e **8.000 tokens por minuto**; o `qwen/qwen3.8-27b`, 7.000 tokens de entrada por minuto. Cada chamada nossa (prompt + 13 ferramentas) usa de 3.000 a 5.000 tokens e cada pergunta faz de 2 a 4 chamadas: o limite por minuto estoura no meio das perguntas, e o Qwen não comporta nem a segunda chamada.
- Avaliação da 4.7 com o Groq na frente e um provedor novo por pergunta (como na API): **8 de 21** sem falha automática, 4 barradas pelo limite por minuto e erros de conteúdo do `gpt-oss` — “tendinite” na pergunta da dor (diagnóstico, proibido), sem indicar profissional na dieta de 800 kcal, sem criar a proposta pedida e números fora dos dados. Na rodada em que o Gemini respondeu a maior parte, **16 de 21**. Nenhuma proposta foi aplicada sem confirmação em nenhuma rodada.
- A avaliação passou a montar um provedor por pergunta: com um só para as 21, a primeira troca para o Gemini valia para todas as seguintes.

**Consequência:** no plano gratuito, o Gemini responde melhor, mas tem pouca cota e usa o conteúdo; o Groq protege mais os dados, mas responde pior e esbarra no limite por minuto. A ordem fica na configuração (`AI_PROVIDER`), sem mudar código. Para a apresentação, o caminho mais seguro é o Gemini no plano pago (conteúdo não usado, cota alta; custo de centavos no volume do TCC), com o Groq de reserva.
**Verificação:** testes do adaptador do Groq, da cadeia e da configuração (sem rede); a sondagem com a chave real (ferramentas, resultado de ferramenta, cabeçalhos de limite); as avaliações acima. No emulador EvoFit_Aceite, com a API real e AI_PROVIDER=groq,gemini: o consentimento nomeia as duas empresas e o aviso do uso do conteúdo só para o Google; à pergunta “O que fiz na minha última sessão?” o gpt-oss-120b consultou só o treino em andamento e respondeu que não havia treino, embora houvesse uma sessão concluída no dia (o Gemini respondeu certo à mesma pergunta na 4.4).

### ADR-058 — Modo demonstração: o assistente por regras, com os dados reais
**Status:** Aceita · Fase 4 (plano B da apresentação; complementa os ADR-056/057)
**Contexto:** os planos gratuitos do Gemini e do Groq não garantem a apresentação do TCC: pouca cota por dia, limite por minuto e indisponibilidade (ADR-057). Pagar um provedor não faz sentido agora, porque o app não vai ser publicado. O `FakeProvider` de demonstração (4.1) só devolve um texto fixo, sem consultar nada: não mostra o que o assistente faz.
**Decisão:** um provedor `demo` (`providers/demo.py`) que segue o mesmo caminho de um modelo — pede as ferramentas ao orquestrador, que as roda com o usuário autenticado, e responde a partir dos resultados —, mas decide **por regras**:
- palavras-chave escolhem a intenção (última sessão, semana, comparação, corrida, músculos, 1RM, metas, treino em andamento, busca de exercícios, proposta para a ficha, proposta de meta), e a intenção escolhe as ferramentas e monta a resposta com os números que elas devolveram;
- dor, dieta, hormônio e pedidos sobre outra conta têm respostas fixas, sem consulta, com o encaminhamento a um profissional; pergunta fora do roteiro recebe a lista do que ele sabe responder;
- propostas passam pela mesma `prepare_change_proposal`: ficam pendentes até a pessoa confirmar;
- conversas com foco (atalhos do Meu Corpo, do detalhe do treino e do exercício): o foco vem do cartão de contexto — o treino (detalhe, recordes e a comparação com o anterior), o músculo (faixa, exercícios que mais o trabalharam e o período anterior) ou o exercício (1RM estimado);
- sem estado: cada chamada lê a última pergunta e o que já foi consultado depois dela, e decide o passo seguinte (a proposta para a ficha leva três passos: fichas, busca de exercícios e proposta).

**Uso:** sozinho (`AI_PROVIDER=demo`) ou como reserva no fim da cadeia (`AI_PROVIDER=gemini,groq,demo`): com a cota esgotada ou o provedor fora do ar no primeiro pedido, a pergunta cai no modo demonstração. Nada sai do servidor.
**Transparência:** `GET /ai/provider` devolve `demo` e a resposta da pergunta devolve `demo: true` quando foi ele que respondeu; o app mostra “Modo demonstração: a resposta foi montada por regras… sem IA externa” embaixo da resposta e o consentimento diz que nenhum dado vai a empresas de IA. O registro da execução guarda `provider=demo`, `model=demo-v1`. Na apresentação, dizer à banca que é o modo de regras, e não um modelo de linguagem.
**Resultado:** as 21 perguntas da avaliação da 4.7 passam nas checagens automáticas (21 de 21, nenhum número fora dos dados, nenhuma proposta aplicada sem confirmação), e isso virou um teste que roda sempre (`test_demo_mode_passes_the_whole_set`, sem rede).
**Verificação no emulador** (EvoFit_Aceite, API real com `AI_PROVIDER=demo`): o consentimento diz que nada vai a empresas de IA; “Como foi minha semana de treinos?” respondeu com os treinos e as corridas da semana; “Adicione um exercício de posterior de coxa na minha ficha Treino A” criou a proposta pendente (fichas → busca → proposta) e, ao confirmar, ela foi aplicada; no atalho do treino, “Bati algum recorde neste treino?” respondeu com o detalhe e “nenhum recorde”. Todas as respostas com o aviso do modo demonstração e registradas como `demo`/`demo-v1`.
**Limites:** não entende perguntas fora do roteiro nem variações muito diferentes das palavras-chave; não conversa (cada pergunta é independente); as respostas têm sempre o mesmo formato. Não substitui a avaliação com um modelo de verdade.
**Alternativas descartadas:** um gateway de provedores gratuitos (FreeLLMAPI): experimental pelo próprio autor, troca de empresa a cada pergunta (o consentimento da LGPD não consegue nomear quem recebe os dados) e não melhora a qualidade. Um modelo local (Ollama etc.): exige instalar um serviço novo e baixar modelos de vários GB, e os modelos pequenos que rodam num notebook costumam errar mais nas chamadas de ferramenta — fica como possibilidade futura.

### ADR-059 — Metas nutricionais: limites de segurança, histórico por dia e o resumo contra a meta
**Status:** Aceita · Fase 5.2
**Contexto:** o ROADMAP pedia metas nutricionais configuráveis “com validação de segurança”; o DATA_MODEL previa `nutrition_targets` com histórico por `valid_from`. O perfil ainda não tem o peso (chega na 5.3), então os limites não podem ser por quilo.
**Decisões:**
- **Histórico por dia:** a meta vale a partir de hoje, no fuso do perfil (o mesmo que separa as refeições); outra mudança no mesmo dia substitui a do dia; os dias anteriores continuam com a meta que valia. Tirar as metas grava uma linha vazia: “sem metas a partir de hoje”. Uma linha por pessoa e dia (restrição única).
- **Valores inteiros e opcionais:** calorias, proteína, carboidratos e gordura; o que fica vazio não é acompanhado.
- **Limites de segurança** (422, com a mensagem que manda a um profissional): calorias entre 1.200 kcal — 1.500 kcal para quem marcou o sexo masculino nos cálculos; sem o dado, vale o menor — e 5.000 kcal, os pisos usuais abaixo dos quais uma dieta pede acompanhamento; proteína de 20 a 300 g, carboidratos de 20 a 800 g, gordura de 20 a 250 g; menores de 18 anos (pelo ano de nascimento) não definem meta de calorias, só de macronutrientes; as calorias dos macronutrientes (4, 4 e 9 kcal por grama) não podem passar da meta de calorias em mais de 15 % e, com os três informados, também não podem ficar mais de 15 % abaixo.
- **Os limites vêm da API** (`limits` em `GET /nutrition/targets`), para o app explicar antes de enviar: o app confere os intervalos na hora e a API confere tudo de novo, inclusive a soma dos macronutrientes.
- **Dado de saúde:** definir metas exige `health_data` (403 sem ele); revogar apaga as metas, como as refeições; o log leva só o id da pessoa.
- **Resumo:** `GET /nutrition/summary?from&to` (até 92 dias; padrão, os últimos 7): cada dia com o número de refeições, os totais e a meta que valia; a média é só dos dias com refeição. É a base da 5.4 (painel e ferramentas da IA). O dia (`/nutrition/daily`) também traz a meta que vale nele.
- **No app:** o dia mostra “1.200 kcal de 2.000”, a barra e “Faltam 800 kcal para a meta” (ou “acima da meta”); cada macronutriente com meta ganha “de 150 g” e uma barra. **Definir metas do dia** / **Editar metas** abre a tela *Metas do dia*: os intervalos em cada campo, a soma dos macronutrientes enquanto a pessoa digita, o campo de calorias desligado (com a explicação) para menores de 18 anos, **Remover metas** com confirmação e o histórico.
- **Fora da 5.2:** limites por quilo e metas sugeridas por cálculo (gasto energético) — dependem do peso (5.3) e de revisão profissional; as metas no painel e nas ferramentas da IA (5.4).
- **Limite conhecido:** a idade sai do ano de nascimento (o perfil não guarda o dia): quem completa 18 anos ainda neste ano já é tratado como adulto.
- **Verificação:** 20 testes na API (consentimento; leitura e gravação; os 8 limites recusados, inclusive a soma dos macronutrientes acima e abaixo das calorias; macronutrientes parciais; piso pelo sexo; menores sem meta de calorias; uma meta por dia com o histórico e a remoção valendo só dali em diante; o resumo com a meta de cada dia, o fuso do perfil e a média dos dias com refeição; intervalo do resumo; privacidade; revogação) e as 3 rotas no teste de autorização entre contas; 5 testes no app (definir e ver quanto falta; limites conferidos no app e mensagem da API; menor de idade; remover com confirmação e histórico; cálculos e formatação). No emulador `EvoFit_Aceite`, com a API real: 1.000 kcal barrado no app; 2.000 kcal com macronutrientes de 2.920 kcal barrado pela API; 2.000 kcal / 150 g / 200 g / 67 g salvo, o dia mostrando “495 kcal de 2.000”, “Faltam 1.505 kcal” e as barras; o dia anterior sem meta; o histórico; e a remoção. O emulador mostrou três ajustes, já corrigidos: a mensagem da API escrevia “2920” (agora “2.920”, como o app); o leitor de tela lia o percentual da barra antes do total (a barra saiu da leitura, o texto já diz quanto falta); e o botão de metas aparecia nos dias passados, onde a meta não vale (agora só em Hoje).

### ADR-060 — Peso e medidas: registro livre, tendência por dia e metas de peso medidas
**Status:** Aceita · Fase 5.3
**Contexto:** o DATA_MODEL previa `body_measurements` com todas as medidas opcionais e ao menos uma preenchida; o ROADMAP pedia “peso e medidas + tendências”. As metas de peso existiam desde a 2.3, mas o painel não tinha como medi-las (“ainda sem registro que meça esta meta”).
**Decisões:**
- **Um registro, várias medidas:** peso, gordura corporal (rotulada como estimativa — balança de bioimpedância ou dobras), cintura, quadril, peito, braço, coxa e panturrilha, todas opcionais, ao menos uma (CHECK no banco e 422 na API, também na edição que tentar limpar a última). Limites físicos para pegar erro de digitação: peso de 20 a 350 kg, gordura de 2 a 75 %, circunferências de 10 a 250 cm; a API publica os limites em `GET /body-measurement-options` e o app confere antes de enviar.
- **Horário como nas refeições:** sem fuso, vale o do perfil (ADR-055); medida no futuro (mais de 10 min) é recusada.
- **Tendência** (`GET /body-measurements/trend?metric&from&to`, padrão 90 dias, até 730): um ponto por dia com registro — o último do dia, porque o peso varia ao longo dele —, a média dos 7 dias até cada ponto, a variação (último menos primeiro), mínimo e máximo e o **ritmo por semana** pela reta de mínimos quadrados — só com 3 pontos ou mais e 14 dias ou mais entre o primeiro e o último, para não anunciar “−2 kg por semana” por causa de duas pesagens próximas.
- **Metas de peso passam a ser medidas:** o atual é o último peso registrado (com a data na explicação); perder e ganhar medem o caminho do peso de quando a meta começou (o último até o fim do dia de início; sem ele, o primeiro depois) até o alvo — 80 → 76 com alvo 70 é 40 % —, e andar para o lado errado conta zero, não negativo; manter mede se o último peso está dentro da margem (`tolerance` vai na resposta, e o app mostra “alvo 72 ± 1,5 kg”). Sem nenhum peso, continua sem número.
- **Dado de saúde:** registrar ou alterar exige `health_data` (403); revogar apaga as medidas; os logs levam só os ids. As medidas de uma pessoa são invisíveis para outra (404 por id, listas e tendência só com as próprias).
- **No app:** atalho **Peso e medidas** no Início; período em chips (30 dias, 90 dias, 6 meses, 1 ano), uma medida por vez em chips (só as que têm registro), o último valor e a data, a variação no período, o ritmo por semana, a média dos 7 dias e o gráfico de linha; os registros abaixo, cada um abrindo a edição (com **Apagar medida**). O formulário tem data e hora, um campo por medida (em branco = não medido) e observação; sem o consentimento, o cartão de autorização da nutrição.
- **Fora da 5.3:** fotos de progresso, IMC (pede altura, que o perfil não tem) e as ferramentas da IA e o painel (5.4).
- **Verificação:** 20 testes na API (opções públicas; consentimento; registro com o fuso do perfil; 7 entradas recusadas, inclusive a medida vazia e campo desconhecido; medida no futuro; edição que mantém ao menos uma medida; tendência com dois registros no mesmo dia, a média de 7 dias, a variação e o ritmo; tendência vazia e limites do período; privacidade; revogação; as regras do ritmo e do progresso de peso — perder, ganhar, lado errado, manter dentro e fora da margem, sem peso — e o painel com a meta medida) e as 6 rotas no teste de autorização entre contas; 5 testes no app (consentimento; registro com a tendência e as medidas em chips; limites conferidos no app; edição e exclusão; formatação) e o texto das metas de peso no painel. No emulador `EvoFit_Aceite`, com a API real: a meta “Chegar a 72 kg” no Início com “77,6 kg (alvo 72 kg)” e 30 % (de 80 kg); a tela com “−2,4 kg desde 26 de out.”, o ritmo de −0,6 kg por semana e o gráfico; um registro novo pelo formulário (77,2 kg e 22 % de gordura) com a média de 7 dias, a gordura rotulada como estimativa e a meta subindo para 35 %. O emulador mostrou três ajustes, já corrigidos: o rótulo do eixo com a unidade quebrava em duas linhas e encostava no texto (agora só o número, com folga); “em 90 dias” sugeria o período inteiro quando o primeiro registro era de 30 dias antes (agora “desde 26 de out.”); e, com o aparelho em outro fuso (o emulador em GMT), o “agora” do formulário lido no fuso do perfil caía no futuro e a API recusava — um registro novo sem a hora escolhida agora vai com o instante em UTC; a hora escolhida segue no fuso do perfil, como nas refeições.

### ADR-061 — Alimentação e peso no painel e na IA
**Status:** Aceita · Fase 5.4
**Contexto:** a 5.1–5.3 trouxeram refeições, metas nutricionais e peso/medidas, mas o painel do Início e o assistente não os enxergavam. O AI_DESIGN já previa `get_nutrition_summary` e `get_body_trend`.
**Decisões:**
- **Duas ferramentas de leitura**, com o usuário do servidor como as outras (ADR-050): `get_nutrition_summary` (padrão 7 dias, até 92) — dias no período, dias com refeição, a média diária só desses dias, as metas de hoje e, por dia registrado, os totais e a meta que valia; e `get_body_trend` (uma medida por vez, padrão 90 dias, até 366) — a mesma tendência da tela (um ponto por dia, média de 7 dias, primeiro, último, variação, mínimo, máximo, ritmo), se é estimativa e quais medidas têm registro no período. **Só números:** nomes de alimentos e observações (texto livre) não vão para o modelo.
- **Prompt `coach.v3`:** a alimentação e o peso entram no escopo; os valores são “registrados”; comparar com as metas que a pessoa definiu; falar da tendência do peso, não de um dia; gordura é estimativa; nada de definir metas de calorias, cardápio ou dieta — isso é com um nutricionista. O v1 e o v2 continuam no repositório.
- **Conferência de números sem sinal:** a variação vem com sinal (−1,5) e o texto diz “1,5 kg a menos”; os números do texto não têm sinal, então a conferência compara pelo valor absoluto.
- **Modo demonstração:** duas intenções novas — alimentação (calorias, proteína, “comi”, refeições) e corpo (peso, cintura, quadril, gordura corporal, medidas; “peso levantado” não conta) — com respostas montadas pelos números das ferramentas. A resposta fixa de dieta passa a valer só para pedidos de dieta (“dieta”, “cardápio”, “jejum”, “secar”, “quantas calorias devo comer”), e não mais para qualquer menção a calorias: “quantas calorias comi?” é uma consulta.
- **Painel do Início:** dois cartões de foco novos, só para quem registra — **Peso** (o último dos 90 dias; a variação desde o peso de 30 dias atrás, ou desde o primeiro do período; o ritmo por semana) e **Alimentação · hoje** (calorias e proteína de hoje contra as metas, e em quantos dos últimos 7 dias houve refeição). Abrem o painel de quem quer emagrecer; para os demais, vêm depois das modalidades (antes do plano, quando ele fica no fim).
- **Avaliação:** três perguntas novas (24 no total): alimentação dos últimos 7 dias e tendência do peso na conta da Ana (que ganhou refeições em 30 e 31/10, metas desde 25/10 e pesos semanais de 80 a 78 kg) e o peso na conta vazia.
- **Verificação:** na API, 2 testes das ferramentas (escopo, padrão de 7 e de 90 dias, médias, metas por dia, só números, limite de 92 dias, conta vazia, medida desconhecida), a conferência com variação negativa, 7 rotas e 3 respostas novas do modo demonstração (inclusive “quantas calorias devo comer” como pedido de dieta e “peso levantado” fora do peso do corpo), a ordem dos cartões e o painel com peso e alimentação; o modo demonstração passa nas 24 perguntas. No app, os cartões Peso e Alimentação no Início (ordem, textos e o toque que abre Peso e medidas) e os textos. No emulador `EvoFit_Aceite`, com a API real em `AI_PROVIDER=demo`: o Início de quem quer emagrecer abre com “Peso · 77,6 kg · −2,4 kg desde 26/10 · ritmo −0,6 kg por semana” e “Alimentação · hoje · 495 de 1.800 kcal hoje · Proteína 53 de 120 g · refeições em 3 dos últimos 7 dias”; no assistente, “Quantas calorias comi nesta semana?” respondeu com os 3 dias, a média de 494,5 kcal e as metas (Consultou: alimentação) e “Como está a tendência do meu peso?” com 77,6 kg, 2,4 kg a menos desde 26/10 e o ritmo de 0,61 kg por semana; as duas execuções com 0 números fora dos dados. O texto de abertura do assistente passou a citar alimentação e peso.

### ADR-062 — Site institucional completo: seções, telas rotuladas, SEO e acessibilidade
**Status:** Aceita · Fase 5.5 (continua o ADR-036)
**Contexto:** o site (ADR-036) tinha só três telas do app e marcava cardio, Meu Corpo, nutrição e IA como “Em breve” — tudo isso ficou pronto nas Fases 3 a 5. Faltavam as seções que um site institucional precisa, o menu no celular (os links sumiam abaixo de 768 px), uma página de privacidade e o SEO além do básico.
**Decisões:**
- **Seções:** hero; faixa de recursos; **O app** com sete telas (treino, histórico, recordes, Meu Corpo, nutrição, peso e medidas, assistente); **Recursos** (seis, nenhum mais “Em breve”); **Como funciona** (registre, acompanhe, pergunte); **A IA** (consulta antes de responder, mostra o que consultou, pede confirmação, conhece os limites; o modo demonstração explicado); **Privacidade** (consentimentos, dados de saúde, cada um vê só o seu, a IA recebe o mínimo); **Perguntas frequentes** (`<details>`); e o fechamento com “O que já funciona” e “Próximos passos” (exportação e exclusão da conta, testes de usabilidade).
- **Telas rotuladas:** toda tela do celular leva “Dados de exemplo” visível acima da moldura e “Tela ilustrativa, com dados de exemplo.” no nome acessível; o rodapé repete. Os números são inventados para a demonstração, mas plausíveis e coerentes com as regras do app.
- **Aviso de privacidade** (`/privacidade`): o que o app guarda, os três consentimentos, a IA (provedor nomeado, nome e e-mail nunca enviados, plano gratuito, modo demonstração), segurança, retenção proposta e direitos — dizendo que é o resumo de um projeto acadêmico, sem revisão jurídica, e que a exportação e a exclusão da conta vêm na 5.6.
- **SEO:** título e descrição por página, `canonical`, Open Graph e Twitter com uma imagem gerada no build (`opengraph-image`, 1200×630, com texto alternativo), `manifest.webmanifest`, `sitemap.xml` com as duas páginas, `robots.txt`, JSON-LD (`SoftwareApplication` e `FAQPage`, gerado da mesma lista das perguntas, com `<` escapado como o guia do Next recomenda) e uma 404 própria com `noindex`. Tudo estático (SSG).
- **Acessibilidade:** um h1 por página e títulos sem pular nível (testado); link “Pular para o conteúdo”; menu do celular num `<details>` (funciona sem JavaScript; com ele, fecha ao tocar num link e com Esc); as âncoras param abaixo do cabeçalho fixo (`scroll-margin-top`); o botão de ampliar cada tela é uma camada transparente sem texto dentro, para o nome dele ser tudo o que o leitor de tela ouve; movimento só com transform e opacity, desligado com “reduzir movimento” (ADR-036).
- **Componentes compartilhados:** cabeçalho, rodapé e logo em `site-chrome.tsx`; nas outras páginas, os links do menu levam a `/#seção`.
- **Verificação:** 13 testes (seções nomeadas; ordem dos títulos; seis recursos sem “Em breve”; as oito telas rotuladas; perguntas e JSON-LD; JSON-LD que não fecha o script; aviso de TCC; menu com as seções nas duas versões; links que levam a destinos reais; ampliar e fechar a tela; privacidade; 404; sitemap, robots e manifesto), tipos, lint e o build de produção (sete rotas estáticas). No navegador, em desktop e em 375 px: nada rola para o lado, o menu abre e fecha, as perguntas abrem, a tela amplia e a 404 responde 404. **Lighthouse (celular): 100 em acessibilidade, boas práticas e SEO** na página inicial e no aviso de privacidade. O navegador mostrou quatro ajustes, já corrigidos: o rótulo “Dados de exemplo” posicionado por fora da moldura era cortado pelo cartão que inclina (foi para o fluxo, acima dela); a lista do Meu Corpo quebrava linha (“3 séries/sem.”) e depois cortava nomes (a unidade foi para um cabeçalho da lista); o menu do celular ficava aberto por cima da seção depois do toque; e o Lighthouse apontou o nome do botão de ampliar diferente do texto visível dentro dele.
- **Atualização do Next.js:** o `next build` acusou vulnerabilidades conhecidas na versão instalada (16.4.3; `npm audit`: sete avisos moderados, de vazamento entre caches a injeção de resposta, corrigidos a partir da 16.4.5). Atualizado para a **16.4.6** — versão de correção, mesma linha 16.4 — junto com o `eslint-config-next`, as duas fixadas na versão exata, com `npm install` em vez do agente do `next upgrade`, para a mudança ficar só nas duas dependências. Depois: `npm audit` sem nenhuma vulnerabilidade nas dependências de produção, o build sem o aviso (código de saída 0), os 13 testes, os tipos e o lint passando. Restam avisos moderados só no `minimatch` usado pelas ferramentas de lint (typescript-eslint), que não vai para o site publicado.

### ADR-063 — Direitos do titular: exportação completa e exclusão da conta
**Status:** Aceita · Fase 5.6
**Contexto:** o SECURITY_PRIVACY §4 previa `GET /me/export` (JSON com todos os dados) e `DELETE /me` com reautenticação e exclusão física em cascata (LGPD art. 18: acesso, portabilidade e eliminação). O site e o aviso de privacidade já anunciavam a etapa.
**Decisões:**
- **Exportação = tabela por tabela, de uma lista explícita** (`users/account.py`, `EXPORT_PLAN`): cada tabela com a regra de “é da pessoa” — a coluna que aponta para `users` ou a ligação com uma tabela já exportada (séries pelas sessões, itens pelas refeições…). Um teste confere que toda tabela do banco está na lista ou fica de fora de propósito (`NOT_EXPORTED`: `users`, que vai como `account`, os tokens de sessão e os catálogos). O formato é legível por máquina (portabilidade): `format`, `version`, `exported_at`, um aviso, `account` e `data`. Ficam de fora só credenciais — o hash da senha e os tokens; os exercícios e alimentos do catálogo aparecem pelo id. Também vão o histórico dos consentimentos (com as revogações) e o registro das execuções da IA (sem conteúdo, como está no banco).
- **Resposta como arquivo:** `Content-Disposition: attachment; filename="evofit-dados-AAAA-MM-DD.json"` e `Cache-Control: no-store`; até 10 exportações por hora por conta (429 com `Retry-After`).
- **Exclusão = física e em cascata**, depois de conferir a senha: todas as tabelas já apontam para `users` com `ON DELETE CASCADE`, então apagar o usuário apaga o resto, inclusive os tokens (a sessão em outro aparelho cai na próxima renovação). Senha errada: 422 no campo `password`; 5 erros em 15 min bloqueiam (429), até com a senha certa, como o login. O log guarda só o id (pseudônimo). Não há período de carência nem “desativar”: o pedido é a exclusão, e o app avisa que não tem volta.
- **No app (Perfil › Seus dados):** **Exportar meus dados** baixa o JSON e abre o “Salvar como” do próprio Android (Storage Access Framework, `ACTION_CREATE_DOCUMENT`) por um canal nativo pequeno (`MainActivity.kt`, `br.tcc.evofit/files`) — sem pacote novo e sem permissão de armazenamento: o sistema dá acesso só ao arquivo criado; cancelar avisa que nada foi salvo. **Excluir minha conta** abre uma tela que lista o que some, sugere exportar antes, pede a senha e uma caixa “Entendo que… para sempre”; só então o botão vermelho liga. Ao concluir, o app limpa a sessão e volta ao login.
- **Site:** “Exportação e exclusão” passou de “Próximos passos” para “O que já funciona”, e o aviso de privacidade explica onde ficam as duas opções.
- **Fora da 5.6:** pedido de exclusão sem acesso ao app (canal do titular, ⚖ pendência do SECURITY_PRIVACY §6) e exportação em outros formatos (CSV).
- **Verificação:** 7 testes na API (cobertura de todas as tabelas; a exportação com tudo da pessoa e nada da outra, sem credenciais, como arquivo e sem cache; a conta vazia; token e limite; a exclusão que zera todas as tabelas da pessoa, derruba o token e o login e deixa a outra conta inteira; o limite de senhas erradas; o corpo obrigatório e fechado) e as 2 rotas na matriz de autorização (um token falso não apaga a conta); 5 testes no app (exportar e salvar; cancelar; falha ao gravar; excluir com a confirmação, a senha errada e a certa, voltando ao login; senha vazia). No emulador `EvoFit_Aceite`, com a API real: o “Salvar como” do Android abriu em Downloads com `evofit-dados-AAAA-MM-DD.json`; o arquivo salvo tinha as 5 pesagens, as 3 refeições com 6 itens, os 2 alimentos próprios, as metas, a meta de peso e os 3 consentimentos, sem hash nem token; a senha errada apareceu no campo; com a certa, o app voltou ao login, o banco ficou sem a conta e sem nenhuma linha órfã, o login dela passou a dar 401 e o log registrou `account_exported` e `account_deleted` só com o id.

### ADR-064 — Testes de usabilidade: protocolo, piloto e resumo automático
**Status:** Aceita · Fase 5.7 (preparada; as sessões com participantes ainda não foram feitas)
**Contexto:** o ROADMAP pede testes com 3 a 5 pessoas, e o UX_FLOWS §5 trazia só a lista de tarefas e as métricas (conclusão, tempo, erros, SUS). Faltavam o roteiro da sessão, o termo, o registro anônimo e o piloto para conferir as tarefas no app atual.
**Decisões:**
- **Protocolo em `docs/USABILIDADE.md`:** sessão moderada e presencial de 30 a 40 min, pensando em voz alta, sem gravação; 7 tarefas em ordem fixa (conta e objetivo, ficha com bi-set, 3 séries com drop set, caminhada, músculo sem treino no Meu Corpo, peso, pergunta ao assistente), escritas como cenários, sem o nome dos botões, cada uma com o critério de conclusão; ajuda só depois de 3 min travado ou de dois pedidos, limite de 5 min por tarefa; SEQ (1 a 7) depois de cada tarefa e SUS no fim; termo de participação e ficha de observação no próprio documento.
- **Privacidade:** a API roda em modo demonstração (nada vai a empresas de IA); a conta usa um e-mail de teste e dados inventados; o participante vira um código (P1…) em tudo; o termo assinado não entra no repositório; no fim, o próprio participante exclui a conta pelo app (o que também testa a 5.6).
- **Registro e resumo:** duas planilhas em `docs/usabilidade/` (`tarefas.csv` e `sus.csv`, só com códigos) e `scripts/usability_report.py`, que confere as linhas (código, tarefa, intervalos, repetição) e escreve o resumo em Markdown: conclusão, mediana de tempo, erros e SEQ por tarefa, e a nota SUS por pessoa e a média contra a referência de 68. A observação livre não vai para o resumo. Os testes ficam em `services/api/tests/test_usability_report.py`, para rodar com o mesmo pytest e o mesmo ruff.
- **Piloto (desenvolvedor, emulador, API real):** as 7 tarefas foram feitas antes das sessões. Corrigido: **Salvar medida** ficava no fim de uma lista de 9 campos e passou ao rodapé fixo, como nos outros formulários; o leitor de tela lia “1 dias por semana”. Ajustado no roteiro: a tarefa “qual músculo recebeu menos estímulo” tinha várias respostas certas com um treino só e virou “um músculo sem treino em 30 dias”. Para observar nas sessões: o drop set sem repetições sugeridas e o contador de séries que não conta o drop set. Ambiente: o emulador precisa do fuso de Brasília.
- **Fora desta entrega:** as sessões com pessoas, o resumo dos resultados e as correções que vierem deles — registrados num ADR próprio quando acontecerem.

### ADR-065 — Conta de demonstração: seed pelas rotas da API, terminando hoje
**Status:** Aceita · Fase 6.1
**Contexto:** a apresentação (Demo Day) precisa de uma conta com histórico — semanas de treino, recordes, Meu Corpo colorido, plano em andamento, refeições, peso — sem usar dados de ninguém e sem preencher tudo à mão. O ROADMAP previa `scripts/seed_demo.py` com o usuário `demo@evofit.local`.
**Decisões:**
- **`python -m app.demo_seed`** (em `services/api`, módulo `app/demo_seed.py`): recria a conta `demo@evofit.local` com **8 semanas terminando no dia em que roda** (rodar na manhã da apresentação). Só essa conta é apagada e recriada (cascata); recusa `APP_ENV=production`.
- **Pelas rotas da própria API**, num cliente dentro do processo, com o relógio de cada serviço levado ao dia e à hora do registro (o mesmo recurso dos testes). Assim os dados passam pelas validações e cálculos reais: recordes, estímulo por músculo, sessões do plano, totais do dia contra a meta. Nenhum INSERT direto que pudesse divergir do app.
- **Conteúdo:** perfil (ganhar massa, intermediário, 5 dias, academia), consentimentos de saúde e de IA; fichas A, B e C (com um bi-set na A); musculação seg/qua/sex com cargas subindo a cada 2 semanas, aquecimento e drop set em semanas alternadas e dois dias pulados; corridas de 5 a 6 km com o ritmo melhorando, depois o plano “Rumo aos 10 km” há 3 semanas, com todas as sessões passadas feitas; caminhadas em domingos; 4 metas (uma alcançada); 9 alimentos “(exemplo)”, metas nutricionais e 4 refeições por dia na última semana (hoje, só o café); peso toda segunda (74 → 75,6 kg) e cintura e braço a cada 4 semanas. Panturrilhas e oblíquos ficam como os menos treinados, para o Meu Corpo ter o que apontar.
- **Identificação:** nome “Demo”, domínio `evofit.local` (não recebe e-mail), alimentos com “(exemplo)” no nome. Tudo fictício.
- **Senha:** `--password`, `DEMO_PASSWORD` ou uma frase de 4 palavras gerada e mostrada uma vez; nada no repositório.
- **Testes** (`tests/test_demo_seed.py`, no banco de testes): perfil e consentimentos, 22 treinos terminando na última semana, recordes, Meu Corpo, plano sem sessão atrasada, refeições perto da meta, 8 pesagens, metas, painel; rodar de novo troca só a conta de demonstração; produção recusada.
- **Achado na verificação:** uma sessão do plano pulada de propósito virava a “próxima” no Início (“Semana 1 de 8”); o plano ficou sem faltas e as faltas ficaram na musculação.

### ADR-066 — Testes de integração: o app no emulador com a API real
**Status:** Aceita · Fase 6.2
**Contexto:** os 282 testes do app usam um servidor falso, e os da API usam um cliente em processo. Nada conferia o caminho inteiro — o app compilado, no Android, falando com a API de verdade e o banco — que é o que a banca vai ver.
**Decisões:**
- **`integration_test` do próprio SDK do Flutter** (sem pacote de terceiros), em `apps/mobile/integration_test/critical_flows_test.dart`, rodado com `flutter test integration_test -d emulator-5554` ou `scripts/test-e2e.ps1` (que confere antes se a API e o banco respondem).
- **Jornada crítica num teste só**, na ordem em que uma pessoa usaria: cadastro com o perfil completo → ficha com bi-set → treino com duas séries e um drop set, finalizado, conferido no resumo → caminhada → peso, passando pela autorização de dados de saúde → pergunta ao assistente no modo demonstração, passando pela autorização de IA → exclusão da conta pelo Perfil, conferindo na API que o login passa a dar 401.
- **Conta descartável:** `e2e.<instante>@evofit.local`, criada e excluída pelo próprio app; se o teste parar no meio, o `tearDown` exclui a conta pela API. Antes de começar, o armazenamento seguro do aparelho é limpo (sem sessão nem rascunho de antes).
- **Conta de demonstração (6.1):** um segundo teste entra com `demo@evofit.local` e confere o Início, o plano, as metas e o Meu Corpo. Roda só com `--dart-define=DEMO_PASSWORD=…`, para a senha não ficar no repositório.
- **Sem `pumpAndSettle`:** o treino tem um cronômetro na tela, então as esperas são por elemento, com limite (20 s; 40 s para o assistente) e mensagem dizendo o que faltou.
- **Achado — erro real corrigido:** ao finalizar (e ao descartar) um treino, `session_page.dart` usava o `ref` do Riverpod depois do `await`, quando a tela já podia ter saído da árvore (“Using ref when a widget is about to or has been unmounted”). Dependendo do tempo, o resumo do treino não abria. Os notifiers agora são lidos antes do `await`.
- **Limite de cadastro:** a API aceita 5 cadastros por hora por IP (proteção da 2.1), e cada execução cria uma conta. Para rodar mais vezes na mesma hora, reinicie a API (o limite fica na memória dela); o limite não foi afrouxado para os testes.

### ADR-067 — APK de release: assinatura local e endereço da API no build
**Status:** Aceita · Fase 6.3
**Contexto:** até aqui o app só rodava em modo de depuração, e o release do modelo do Flutter saía assinado com a chave de depuração. Para instalar o EvoFit num celular (banca, testes com pessoas) é preciso um APK de release assinado, apontando para uma API que não seja o `10.0.2.2` do emulador.
**Decisões:**
- **Chave fora do repositório:** `scripts/make-keystore.ps1` gera uma keystore PKCS12 (RSA 2048, validade de 10.000 dias) com senha aleatória em `%USERPROFILE%\.evofit\evofit-release.jks` e escreve `apps/mobile/android/key.properties`, que o `.gitignore` já ignorava (assim como `*.jks`). A senha passa ao `keytool` por variável de ambiente, não pela linha de comando. O script nunca sobrescreve uma chave existente: um APK assinado com outra chave não instala por cima do anterior.
- **Release sem chave falha:** o `build.gradle.kts` lê o `key.properties`; se ele não existir e a tarefa for de release, o build para com uma mensagem que aponta o script. Antes saía, sem aviso, um "release" assinado com a chave de depuração. Os builds de depuração (e os testes de integração) não mudam.
- **Endereço da API no build, sem segredo:** `scripts/build-apk.ps1 -ApiUrl ...` passa `--dart-define=API_BASE_URL`, como já fazia o `flutter run`. O script confere o endereço (absoluto, `http`/`https`, sem caminho, consulta ou usuário, porque o app acrescenta `/api/v1`) antes de compilar.
- **HTTPS por padrão; HTTP só pedido:** o APK normal mantém o `network_security_config.xml` da 3.9 (HTTP só para o servidor local do manequim 3D). Com `-AllowHttp`, o Gradle recebe `-P evofit.allowHttp=true` e o manifesto aponta (por `manifestPlaceholders`) para `network_security_config_http.xml`, que libera HTTP — necessário para a API num computador da rede local, sem certificado. Esse APK sai com `-http` no nome, para não ser confundido com o outro. Um endereço `http://` sem `-AllowHttp` é recusado.
- **Saída:** `dist/evofit-<versão>[-http].apk` (pasta ignorada pelo git) com o SHA-256 ao lado. Um APK só para as três arquiteturas (62 MB), mais simples de instalar do que um por ABI; a versão vem do `pubspec.yaml`.
- **Verificado:** o APK foi assinado com a chave nova (`apksigner verify`), não é depurável e usa a configuração de rede esperada em cada variante (`aapt2 dump`). No emulador, o APK `-http` entrou com a conta de demonstração, mostrou o Início e abriu o Meu Corpo em 3D (WebView e servidor local funcionando depois do R8).
- **Limites:** a chave e o `key.properties` existem só neste computador e precisam de cópia de segurança. Sem ofuscação do Dart (`--obfuscate`), porque o app não guarda segredo e os relatórios de erro ficariam ilegíveis. O APK não vai para loja nenhuma; a publicação depende de autorização.

### ADR-068 — Correções do piloto: sugestão de repetições no drop e contador com os segmentos
**Status:** Aceita · Fase 6.4
**Contexto:** o piloto da 5.7 deixou dois pontos “para observar” no registro do treino. Sem sessões com pessoas ainda, os dois foram tratados agora: os dois atrapalham justamente a tarefa 3 (três séries com um drop set), e a correção não muda o modelo de dados.
**Decisões:**
- **O drop sugere as repetições da linha de cima.** Antes a linha D trazia só a carga (20% a menos), e tocar no ✓ sem digitar respondia “Informe as repetições”, contra a regra do caminho crítico (um toque salva com a sugestão). Agora a ordem é: o drop da última vez na mesma linha; senão as repetições da série que ele continua (feitas ou sugeridas). O plano de um drop planejado na ficha vale para a cadeia inteira (é o da série principal), por isso não é usado como sugestão do segmento — usar a carga dele repetiria a carga da série de cima.
- **O rest-pause continua sem repetições sugeridas:** depois de 15 s de pausa elas variam demais, e um número inventado seria salvo com um toque.
- **O contador mostra os segmentos ao lado das séries:** “Séries: 2 + 1 drop” (e “+ N rest-pause”). A contagem de séries não muda — um drop set continua sendo uma série, como na API, no histórico e no Meu Corpo (ADR-033) —, mas o drop feito deixa de parecer perdido para quem esperava 3. O leitor de tela lê o mesmo texto.
- **Verificação:** testes de regra (sugestão do drop feito e planejado, rest-pause sem repetições, o texto do contador com drops e rest-pause) e de fluxo (✓ no drop sem digitar envia 10 repetições e 47,5 kg; o topo mostra “1 + 1 drop”). Com o comportamento antigo de volta, os três testes novos de sugestão falham. O teste de integração da 6.2 passou a deixar as repetições do drop sem digitar e conferir o contador; passou no emulador com a API real, junto com o da conta de demonstração.
