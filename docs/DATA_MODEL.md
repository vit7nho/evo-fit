# Modelo de dados preliminar

> Preliminar: será refinado durante a implementação de cada fase, sempre por migrações Alembic. Convenções: `id uuid` (v7) como PK; `created_at`/`updated_at timestamptz` em todas as tabelas mutáveis; unidades em SI; `user_id` com `ON DELETE CASCADE` em tudo o que pertence ao usuário.

## 1. Visão geral (ER resumido)

```
users ─┬─ user_profiles (1:1)        ─ user_consents        ─ refresh_tokens
       ├─ goals
       ├─ workout_templates ─ template_items (séries planejadas em JSONB, §3)
       │        └─ exercise_groups (técnicas entre exercícios)
       ├─ activities ─┬─ workout_sessions ─ session_exercises ─ set_entries
       │              ├─ endurance_details ─┬─ cycling_details
       │              │                     └─ swim_details
       ├─ training_plans ─ plan_sessions (planos de corrida/caminhada)
       ├─ meals ─ meal_items ─ foods (globais ou do usuário)
       ├─ nutrition_targets
       ├─ body_measurements
       ├─ ai_conversations ─ ai_messages ─ ai_tool_calls
       ├─ ai_run_logs
       └─ change_proposals

exercises ─ exercise_muscles ─ muscle_groups        (catálogo global + exercícios do usuário)
stimulus_methodologies                              (configuração versionada, §6)
```

## 2. Usuários, perfil e metas

**users**: `id`, `email` (único, citext), `password_hash`, `status` (`active|disabled`), `last_login_at`.

**user_profiles** (1:1): `display_name`, `birth_year` (ano — em vez da data completa, por minimização), `sex_for_calculations` (opcional: `female|male|unspecified`; usado só se o usuário quiser estimativas de gasto), `timezone`, `unit_system` (`metric|imperial`), `experience_level` (`beginner|intermediate|advanced`), `weekly_availability` (JSONB: `{days_per_week, minutes_per_session}`), `preferred_modalities` (array de enum), `equipment` (array de enum: `gym|dumbbells|bands|bodyweight|bike|pool|...`), `dietary_preferences` (array: `vegetarian|vegan|lactose_free|...`), `limitations_note` (texto livre, **sensível**), `limitation_tags` (array controlado: `knee|lower_back|shoulder|cardiac_condition_reported|...`), `primary_objective` e `secondary_objectives` (motivação declarada no onboarding — as metas mensuráveis ficam em `goals`), `onboarding_completed_at` (migração 0002).

**user_consents**: `user_id`, `kind` (`terms_privacy|health_data|ai_processing`), `version`, `granted_at`, `revoked_at`.

**refresh_tokens**: `user_id`, `family_id`, `token_hash` (único), `expires_at`, `rotated_at`, `revoked_at`, `user_agent` (truncado).

**goals** (migração 0003): `user_id`, `kind` (texto com o código de `app/modules/goals/kinds.py`: `strength|hypertrophy|weight_loss|weight_maintenance|weight_gain|run_distance|run_time|frequency|habit|custom` — texto e não enum, para um tipo novo não exigir migração), `title`, `target` (JSONB validado pelos campos do `kind`, ex.: `{distance_km: 5}` ou `{sessions_per_week: 3, modality: "walk"}`), `start_date`, `target_date` (≥ `start_date`, CHECK), `status` (`active|achieved|abandoned`), `priority` (1–3, CHECK), `closed_at`. Índice `(user_id, status)`.
> Um JSONB tipado por `kind` evita uma tabela por tipo de meta, que seriam todas pequenas. A validação é feita a partir de uma definição de campos por tipo (a mesma que o app usa para montar o formulário), em vez de uma classe Pydantic por tipo. Metas de peso são dado de saúde e saem junto com o consentimento `health_data`. O progresso automático depende dos registros de treino e de medidas (Fases 3 e 5).

## 3. Musculação

**muscle_groups** (migração 0004, dados de referência com `position` para a ordem de exibição; fonte: `app/modules/exercises/catalog.py`): `id` texto estável (`chest`, `lats`, `traps`, `delts`, `biceps`, `triceps`, `forearms`, `abs`, `obliques`, `glutes`, `quads`, `hamstrings`, `calves`), `name_pt`, `body_region` (`upper|core|lower`), `view` (`front|back|both`). Subdivisões (ex.: `delts_front`) poderão entrar com `parent_id` quando houver dados e um visual que as suporte.

**exercises** (migração 0004): `owner_user_id` (NULL = catálogo global), `name`, `slug` (único no catálogo e, separadamente, por dono: índices parciais), `search_name` (nome sem acentos e em minúsculas, para a busca sem extensões no PostgreSQL), `instructions` (texto/markdown), `mechanics` (`compound|isolation`), `equipment` (`barbell|dumbbells|machine|cable|kettlebell|bands|pull_up_bar|bodyweight`, com os mesmos códigos do perfil quando o significado coincide), `load_type` (`external|bodyweight|assisted|time`) — define se o volume `carga × reps` faz sentido —, `unilateral` (bool), `is_active`. As fotos do catálogo não ficam no banco: são arquivos versionados junto do seed (`seed/images/{slug}/0.jpg|1.jpg`, mapeados em `seed/images.v1.json`, ADR-030).

**exercise_muscles**: `exercise_id`, `muscle_group_id`, `role` (`primary|secondary`), PK composta. O peso numérico **não** fica aqui: vem da metodologia (§6), para poder mudar sem migrar dados.

**workout_templates** (fichas, migração 0005): `user_id`, `name`, `notes`, `position`. Sem `archived_at`: excluir é definitivo e as sessões da 2.6 vão guardar o próprio registro (`template_id` anulável).

**exercise_groups**: `id`, `template_id` **ou** `session_id` (exatamente um, via CHECK — a 2.6 acrescenta `session_id` e o CHECK), `position`, `kind` (`superset|biset|triset|giant_set`), `rest_after_s`. Agrupa itens consecutivos da ficha/sessão.

**template_items**: `template_id`, `exercise_id`, `position`, `exercise_group_id` (nullable), `planned_sets` (JSONB com uma lista de séries planejadas `[{kind, reps_min, reps_max, duration_s, load_kg, rir_target}]`; `kind` em `warmup|working|drop|rest_pause` faz o papel da antiga `technique`), `rest_s`, `notes`. `exercise_id` com `ON DELETE CASCADE`: exercícios só saem na exclusão da conta.
> A prescrição fica em JSONB porque é um plano (lido e editado como um bloco, nunca agregado). O que é executado fica em tabelas normalizadas.

**activities** (base multimodal): `user_id`, `modality` (`strength|run|walk|cycle|swim|other`), `started_at`, `ended_at`, `duration_s`, `perceived_effort` (RPE 1–10, opcional), `notes`, `source` (`manual|app_session|import:<provider>`), `external_id` (nullable; único por `user_id+source`), `deleted_at` (exclusão lógica para recalcular indicadores com histórico; exclusão de conta é física).

**workout_sessions** (migração 0006): `activity_id` (1:1), `user_id` (repetido da atividade, para filtrar pelo dono), `template_id` (nullable, `SET NULL` — sessões livres são permitidas e a ficha pode ser excluída), `name` (copiado da ficha), `status` (`in_progress|paused|completed`; descartar apaga, sem estado `discarded`), `paused_at`, `paused_total_s`. Índice único parcial: uma sessão aberta por usuário.

**session_exercises**: `session_id`, `exercise_id`, `position`, `group_id`, `planned_sets` (cópia do plano da ficha), `rest_s`, `notes`. Os grupos da sessão usam `exercise_groups.session_id` (CHECK: ficha **ou** sessão).

**set_entries** (séries executadas):

| coluna | tipo | observação |
|---|---|---|
| `session_exercise_id` | uuid | |
| `position` | int | ordem dentro do exercício |
| `kind` | enum | `warmup`, `working`, `drop`, `rest_pause`, `cluster` |
| `parent_set_id` | uuid null | segmentos de drop/rest-pause apontam para a série principal |
| `reps` | int null | |
| `load_kg` | numeric(6,2) null | carga externa; para `assisted`, a assistência |
| `duration_s` | int null | exercícios isométricos/por tempo |
| `rir` / `rpe` | numeric null | opcionais |
| `to_failure` | bool | |
| `completed_at` | timestamptz | |

Restrição: `kind in (drop, rest_pause, cluster)` ⇔ `parent_set_id IS NOT NULL`.

**Recordes pessoais**: **calculados sob demanda** (consultas indexadas por `user_id, exercise_id`), não armazenados. Tipos: maior carga para N reps, maior e1RM estimado (Epley, rotulado como estimativa), maior volume em uma sessão. Uma *materialized view* só será considerada se houver problema de desempenho.

## 4. Atividades de resistência (corrida, caminhada, ciclismo, natação)

**endurance_details** (1:1 com `activities`): `distance_m`, `elevation_gain_m`, `avg_hr`, `max_hr`, `avg_cadence`, `moving_time_s`. Todos opcionais, exceto que corrida/caminhada exigem `duration_s`. **Pace e velocidade não são armazenados** — são calculados quando há distância e duração.

**cycling_details**: `avg_power_w`, `indoor` (bool). **swim_details**: `pool_length_m`, `laps`, `stroke` (`freestyle|mixed|...`).

**training_plans**: `user_id`, `kind` (`walk_habit|run_5k|run_10k`), `template_version`, `start_date`, `days_per_week`, `status`, `adapted_for` (JSONB: experiência e limitações consideradas na geração).
**plan_sessions**: `plan_id`, `week`, `day_index`, `prescription` (JSONB, ex.: `[{type:"walk", s:300},{type:"run", s:60}, ...]`), `scheduled_date`, `completed_activity_id` (nullable).
> Os planos são gerados por **templates determinísticos versionados** (não pela IA), ajustados por regras simples (iniciante sem histórico começa com caminhada/intervalos). A IA pode explicar ou propor ajustes via `change_proposals`.

## 5. Nutrição e corpo

**foods**: `owner_user_id` (NULL = catálogo), `name`, `source` (`user|seed|taco|off`), `source_ref`, valores por 100 g: `kcal`, `protein_g`, `carbs_g`, `fat_g`, `fiber_g` (opcional), `default_portion_g`.
**meals**: `user_id`, `eaten_at`, `meal_type` (`breakfast|lunch|dinner|snack|other`), `notes`.
**meal_items**: `meal_id`, `food_id`, `quantity_g`, **cópia dos nutrientes calculados** (`kcal`, `protein_g`, …) no momento do registro — para que editar um alimento depois não altere o histórico.
**nutrition_targets**: `user_id`, `valid_from`, `kcal`, `protein_g`, `carbs_g`, `fat_g` (todos opcionais; histórico por `valid_from`).
**body_measurements**: `user_id`, `measured_at`, `weight_kg`, `body_fat_pct` (rotulado como estimativa), `waist_cm`, `hip_cm`, `chest_cm`, `arm_cm`, `thigh_cm`, `calf_cm`, `notes`. Todos opcionais, mas ao menos um valor obrigatório.

## 6. Metodologia de estímulo muscular (v1)

**stimulus_methodologies**: `version` (PK, ex.: `v1`), `config` (JSONB), `active` (bool), `description`. A resposta da API sempre informa a versão usada.

Configuração inicial proposta (`v1`):

```json
{
  "role_weights": { "primary": 1.0, "secondary": 0.5 },
  "set_kind_weights": { "warmup": 0.0, "working": 1.0, "drop": 0.5, "rest_pause": 0.33, "cluster": 0.33 },
  "drop_chain_cap": 2.0,
  "count_sets_without_reps": false,
  "bands_weekly_sets": { "none": [0, 0.5], "low": [0.5, 6], "mid": [6, 12], "high": [12, null] }
}
```

Algoritmo (função pura, `analytics/stimulus.py`):

1. Seleciona `set_entries` do usuário no período, de sessões `completed`, com atividades não excluídas.
2. Ignora séries de aquecimento (peso 0) e, se configurado, séries sem repetições/tempo.
3. Para cada série, `valor = set_kind_weight`; a soma de uma cadeia (série principal + segmentos de drop/rest-pause) é limitada a `drop_chain_cap`.
4. Distribui o valor para cada músculo do exercício: `valor × role_weight`.
5. Soma por músculo → `weighted_sets`. Também calcula `frequency` (número de dias distintos com `weighted_sets > 0`), `exercises[]` e `volume_load_kg` (apenas exercícios com `load_type = external`).
6. Normaliza para **séries ponderadas por semana**: `weighted_sets / (dias_do_período / 7)`, permitindo comparar períodos de durações diferentes.
7. Classifica em faixas (`none` → cinza, `low` → azul, `mid` → laranja, `high` → vermelho) pelos limites configurados.

Por que faixas absolutas por semana, e não “relativas ao músculo mais treinado”: com normalização relativa, quem treinou só um músculo veria esse músculo em vermelho, como se tivesse alto volume. As faixas são referências gerais configuráveis, **não prescrições**, e a interface exibe esse aviso. Uma visão alternativa “distribuição relativa (%)” é oferecida como gráfico separado.

Casos de teste obrigatórios: sem histórico; período sem sessões; série sem reps; exercício só com músculos primários; exercício com secundários; drop set com 3 segmentos (aplicação do teto); rest-pause; aquecimento ignorado; sessão excluída depois; períodos de 7 vs. 30 dias; mudança de versão da metodologia.

## 7. IA

**ai_conversations**: `user_id`, `scope` (`global|session|exercise|muscle|activity|period`), `scope_ref` (JSONB, ex.: `{muscle_id: "lats", from, to}`), `title`, `created_at`.
**ai_messages**: `conversation_id`, `role` (`user|assistant|tool`), `content`, `created_at`.
**ai_tool_calls**: `message_id`, `tool_name`, `arguments` (JSONB), `result_summary` (JSONB, truncado), `status`, `duration_ms`.
**ai_run_logs**: `user_id`, `conversation_id`, `provider`, `model`, `prompt_version`, `input_tokens`, `output_tokens`, `latency_ms`, `outcome` (`ok|provider_error|rate_limited|invalid_output|refused`). **Sem conteúdo.**
**change_proposals**: `user_id`, `conversation_id`, `kind` (`template_add_exercise|template_replace_exercise|template_adjust_sets|goal_create|goal_update|plan_adjust`), `target_id`, `payload` (JSONB validado por `kind`), `rationale`, `status` (`pending|accepted|rejected|expired|failed`), `expires_at`, `decided_at`.

## 8. Armazenado × calculado

| Armazenado | Calculado sob demanda |
|---|---|
| Registros brutos (séries, atividades, refeições, medidas) | Pace, velocidade, volume, recordes, estímulo, consistência, tendências, adesão a metas |
| Nutrientes de `meal_items` no momento do registro | Totais diários |
| Metas e alvos com histórico (`valid_from`) | Comparações entre períodos |

Cache de indicadores (tabela ou Redis) só será criado se houver necessidade medida.

## 9. Índices principais

- `activities (user_id, started_at DESC) WHERE deleted_at IS NULL`
- `set_entries (session_exercise_id, position)`; `session_exercises (exercise_id)` + junção para histórico do exercício por usuário
- `meals (user_id, eaten_at DESC)`; `body_measurements (user_id, measured_at DESC)`
- `exercises (owner_user_id, slug)` único; busca por nome com `pg_trgm` (Fase 2)
- `refresh_tokens (token_hash)` único; `change_proposals (user_id, status)`
