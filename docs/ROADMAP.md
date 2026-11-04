# Roadmap incremental e backlog priorizado

Cada fase termina com uma **jornada demonstrável**, testes passando e a documentação atualizada. As fases são uma ordem de execução, não um compromisso de prazo.

Legenda de prioridade: **P0** indispensável para o TCC · **P1** importante · **P2** desejável se houver tempo.

---

## Fase 0 — Planejamento ✅
Inspeção do ambiente, avaliação de viabilidade e riscos, arquitetura, modelo de dados, design da IA, convenções da API, UX e segurança.

## Fase 1 — Fundação técnica ✅
**Objetivo:** os três apps sobem localmente com um comando cada, conversam com o backend e têm testes/lint configurados.

| # | Tarefa | Prio |
|---|---|---|
| 1.1 | `.gitignore`, `.env.example`, `docker-compose.yml` (db, db-test, api) | P0 |
| 1.2 | Backend: `pyproject.toml` (versões fixadas após instalação), estrutura `core/ db/ api/v1`, config, erros *problem+json*, logging com remoção de campos sensíveis, `GET /health` | P0 |
| 1.3 | Alembic configurado + primeira migração (`users`, `user_profiles`, `user_consents`, `refresh_tokens`) | P0 |
| 1.4 | pytest com Postgres de teste, fixtures transacionais; Ruff (lint + format) | P0 |
| 1.5 | `packages/design-tokens/tokens.json` + script que gera `tokens.dart` e `tokens.css` | P1 |
| 1.6 | App Flutter: `flutter create` (Android), Riverpod, go_router, dio, tema escuro com tokens, `EvoButton/EvoCard/EvoState*`, tela de *splash* que chama `/health` | P0 |
| 1.7 | Testes de widget dos componentes e dos estados carregando/erro/vazio; `flutter analyze` | P0 |
| 1.8 | Site Next.js: projeto, Tailwind com tokens, layout base, página inicial esqueleto, lint/typecheck, Vitest | P1 |
| 1.9 | Scripts `scripts/dev-api.ps1` / `scripts/test-all.ps1` (+ `test-all.sh`) | P1 |
| 1.10 | `SETUP.md` validado do zero na máquina | P0 |

**Critérios de aceite:**
- `docker compose up -d db` + `alembic upgrade head` criam o schema sem erro.
- `pytest` passa (health, config, formato de erro).
- O app roda no emulador Android e mostra “API conectada” (ou o estado de erro, se a API estiver desligada).
- `npm run lint && npm run typecheck && npm test` passam no site.
- Nenhum segredo versionado.

**Situação em 2026-10-28 — Fase 1 concluída:**

| Critério | Estado |
|---|---|
| Migração aplicada no Postgres | ✅ `alembic upgrade head` → `0001 (head)` no PostgreSQL 18.6 local (Docker indisponível nesta máquina; ver ADR-021) |
| pytest | ✅ 20 testes passam, incluindo migrações = models, downgrade/upgrade, UUID v7, constraints, cascata e `/health` 200 |
| App no emulador | ✅ APK de debug no Android 15: “API conectada” com o banco ativo; “Banco de dados indisponível” e “API indisponível” + nova tentativa também verificados |
| Site | ✅ typecheck, lint, 4 testes e `next build` passam |
| App (testes) | ✅ `flutter analyze` limpo, 16 testes passam |
| Segredos | ✅ só `.env.example` com valores de desenvolvimento; `.env` no `.gitignore` |

## Fase 2 — Primeiro fluxo funcional (musculação)
| # | Tarefa | Prio |
|---|---|---|
| 2.1 ✅ | Auth completa (registro, login, refresh rotativo, logout) + testes de segurança | P0 |
| 2.2 ✅ | Onboarding: perfil, objetivos, modalidades, equipamentos, consentimentos | P0 |
| 2.3 ✅ | Metas (CRUD) | P0 |
| 2.4 ✅ | Grupos musculares + seed próprio de exercícios + biblioteca com filtros | P0 |
| 2.5 ✅ | Fichas: CRUD, ordenação, agrupamentos (bi-set/tri-set/supersérie) | P0 |
| 2.6 ✅ | Sessão: iniciar/pausar/finalizar, registro de séries em tela única, pré-preenchimento com a última sessão, cronômetro de descanso | P0 |
| 2.7 ✅ | Técnicas: drop set, rest-pause, até a falha, aquecimento | P0 |
| 2.8 ✅ | Histórico por exercício, recordes, comparação com a sessão anterior | P0 |
| 2.9 ✅ | Rascunho local da sessão em andamento (sobrevive ao fechamento do app) | P1 |
| 2.10 ✅ | Testes de autorização entre usuários em todos os endpoints | P0 |

**Aceite:** um usuário novo cria uma ficha com um bi-set e um drop set, executa a sessão no Android, fecha e reabre o app, finaliza e vê o histórico e os recordes — tudo persistido.

## Fase 3 — Evolução e modalidades
| # | Tarefa | Prio |
|---|---|---|
| 3.1 | Atividades multimodais (corrida, caminhada; ciclismo e natação básicos) | P0 |
| 3.2 | Pace/velocidade calculados; métricas opcionais (FC, elevação) | P0 |
| 3.3 | Planos progressivos (caminhada, 5 km, 10 km) a partir de templates versionados | P1 |
| 3.4 | Motor de análise: frequência, consistência, volume, tendências, comparação de períodos | P0 |
| 3.5 | Metodologia de estímulo v1 + testes da matriz de casos (`DATA_MODEL.md` §6) | P0 |
| 3.6 | Meu Corpo 2D (SVG frente/costas, seleção, filtros de período, detalhe do músculo) | P0 |
| 3.7 | Gráficos (fl_chart) e tela de comparativos | P0 |
| 3.8 | Dashboard personalizado pelos objetivos | P0 |
| 3.9 | Prova de conceito do 3D (GLB + model_viewer_plus) com uma decisão documentada | P2 |

**Aceite:** com dados reais registrados, Meu Corpo mostra as cores corretas para os períodos de 7 e 30 dias (verificadas pelos testes); uma corrida de 5 km em 30 min mostra 6:00/km.

## Fase 4 — IA contextual
| # | Tarefa | Prio |
|---|---|---|
| 4.1 | Camada `LLMProvider` + `FakeProvider` + erros | P0 |
| 4.2 | Ferramentas de leitura (tabela em `AI_DESIGN.md` §3) com testes de escopo | P0 |
| 4.3 | Orquestrador, prompt `coach.v1`, limites, logs de execução | P0 |
| 4.4 | Adaptador do provedor real (após a decisão do ADR-012) | P0 |
| 4.5 | Chat no app: modos global/específico, atalhos a partir do Meu Corpo e da sessão | P0 |
| 4.6 | Propostas de alteração + confirmação | P1 |
| 4.7 | Conjunto de avaliação com ~20 perguntas | P1 |

**Aceite:** “O que fiz na minha última sessão?” é respondida com dados corretos; um usuário sem histórico recebe “ainda não há registros” em vez de números inventados; uma alteração de ficha só acontece após a confirmação.

## Fase 5 — Nutrição e refinamento
| # | Tarefa | Prio |
|---|---|---|
| 5.1 | Alimentos (próprios + seed; avaliar a licença da TACO), refeições, totais diários | P0 |
| 5.2 | Metas nutricionais configuráveis (com validação de segurança) | P0 |
| 5.3 | Peso e medidas + tendências | P0 |
| 5.4 | Integração ao dashboard e às ferramentas da IA | P1 |
| 5.5 | Site institucional completo (seções, mockups rotulados, SEO, acessibilidade) | P0 |
| 5.6 | Exportação e exclusão de conta (LGPD) | P0 |
| 5.7 | Testes de usabilidade com 3–5 pessoas (roteiro em `UX_FLOWS.md`) | P1 |

## Fase 6 — Preparação para a demonstração
Dados de demonstração identificados (`scripts/seed_demo.py`, usuário `demo@evofit.local`), correção de erros, testes de integração dos fluxos críticos, build APK de release (assinatura de debug ou chave local), documentação final, limitações conhecidas.

---

## Próxima etapa

**Fase 2** em andamento: 2.1 (autenticação) e 2.2 (onboarding, perfil e consentimentos) concluídas, verificadas no emulador com a API real. Depois da 2.2, uma revisão de interface e acessibilidade (ADR-027) corrigiu foco, TalkBack, redução de movimento e fonte grande. 2.3 (metas) concluída: API, app e emulador com a API real. 2.4 (biblioteca de exercícios) concluída, com fotos de 67 exercícios (ADR-030). 2.5 (fichas de treino), 2.6 (sessão de treino), 2.7 (técnicas e tela de séries em tabela), 2.8 (histórico, recordes e comparação), 2.9 (rascunho local da sessão) e 2.10 (testes de autorização entre usuários) concluídas. Próximo: critério de aceite da Fase 2 (fluxo completo no Android com um usuário novo). A Fase 1 foi executada na ordem 1.1 → 1.4 → 1.6 → 1.7 → 1.5 → 1.8 → 1.9 → 1.10.
