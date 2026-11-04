# API — convenções e endpoints planejados

> **Implementados:** `/health`, `/auth/*` (2.1), `/me`, `/me/consents/{kind}` e `/profile-options` (2.2). O restante do mapa ainda é planejamento. A fonte da verdade, depois de implementada, será o OpenAPI gerado (`/docs`, `/openapi.json`) e exportado para `docs/openapi.json` (ADR-008). Este arquivo registra as convenções e o mapa previsto.

## Convenções

- Base: `/api/v1`. Uma quebra de compatibilidade cria `/api/v2`; mudanças aditivas não.
- JSON em `snake_case`. Datas em ISO 8601 com fuso (`2026-10-28T19:00:00Z`); datas sem hora como `YYYY-MM-DD`, interpretadas no fuso do perfil.
- Unidades em SI nos campos e no nome (`distance_m`, `load_kg`, `duration_s`).
- Autenticação: `Authorization: Bearer <access_token>`.
- Paginação por cursor: `?limit=20&cursor=...` → `{ "items": [...], "next_cursor": "..." | null }`.
- Códigos: `200` leitura/alteração, `201` criação (com `Location`), `204` sem corpo, `400` regra de negócio, `401` não autenticado, `403` sem consentimento/permissão, `404` inexistente **ou de outro usuário**, `409` conflito (ex.: sessão já em andamento), `422` validação, `429` limite, `503` provedor de IA indisponível.
- Erros (`application/problem+json`):

```json
{ "type": "https://evofit.local/errors/validation", "title": "Dados inválidos", "status": 422,
  "code": "validation_error", "detail": "...", "errors": [{ "field": "reps", "message": "..." }], "request_id": "..." }
```

## Mapa de endpoints (por fase)

### Fase 1–2: base, autenticação e musculação
| Método | Caminho | Descrição |
|---|---|---|
| GET | `/health` | liveness + verificação do banco |
| POST | `/auth/register` ✅ | cadastro + consentimento `terms_privacy`; `201` com o par de tokens |
| POST | `/auth/login` ✅ | access + refresh |
| POST | `/auth/refresh` ✅ | rotação do refresh |
| POST | `/auth/logout` ✅ | revoga a família; `204` (idempotente) |
| GET ✅ / PATCH ✅ | `/me` | conta + perfil + consentimentos ativos; PATCH parcial (só os campos enviados) |
| PUT ✅ / DELETE ✅ | `/me/consents/{kind}` | conceder (idempotente) / revogar; `health_data` revogado apaga os dados de saúde |
| GET ✅ | `/profile-options` | vocabulários do perfil com rótulos PT-BR (público, cache 1 h) |
| GET ✅ / POST ✅ | `/goals` · GET/PATCH/DELETE `/goals/{id}` ✅ | metas; `?status=` filtra; metas de peso exigem `health_data` |
| GET ✅ | `/goal-options` | tipos de meta, campos do alvo de cada um e rótulos (público, cache 1 h) |
| GET ✅ | `/muscle-groups` | grupos musculares com ids estáveis (público, cache 1 h) |
| GET ✅ | `/exercise-options` | grupos, equipamentos, mecânicas e tipos de carga (público, cache 1 h) |
| GET ✅ / POST ✅ | `/exercises` · GET/PATCH `/exercises/{id}` ✅ | biblioteca (global + próprios); filtros `q`, `muscle`, `equipment` (repetível), `mine`, `include_archived` |
| GET ✅ | `/exercises/{id}/history` | séries do usuário nesse exercício + recordes |
| GET ✅ / POST ✅ | `/workout-templates` · GET/PUT/DELETE `/workout-templates/{id}` ✅ · PUT `/workout-templates/order` ✅ | fichas salvas inteiras (nome, itens e grupos), ADR-031 |
| GET ✅ | `/workout-options` | tipos de agrupamento e de série planejada (público, cache 1 h) |
| POST ✅ | `/workout-sessions` | iniciar (livre ou a partir de ficha; `409` se já houver uma em andamento) |
| GET ✅ | `/workout-sessions/current` · `/workout-sessions/{id}` | o aberto (`204` se não houver) · um treino |
| POST ✅ | `/workout-sessions/{id}/pause` · `/resume` · `/finish` · `/discard` | ciclo de vida |
| POST/PATCH/DELETE ✅ · POST/PATCH/DELETE ✅ | `/workout-sessions/{id}/exercises[/{seid}]` · `…/{seid}/sets[/{set_id}]` | exercícios do treino e registro de séries (salvamento por série) |
| GET | `/workout-sessions/{id}/comparison?with=previous` | comparação com a sessão anterior da mesma ficha |

### Fase 3: modalidades e evolução
| Método | Caminho | Descrição |
|---|---|---|
| GET/POST ✅ | `/activities` · GET/PATCH/DELETE `/activities/{id}` | atividades de resistência (campos por `modality`) |
| GET ✅ | `/activity-options` | modalidades, estilos de nado e piscinas (público, cache 1 h) |
| GET/POST | `/training-plans` · GET `/training-plans/{id}` | planos 5 km/10 km/caminhada |
| GET | `/analytics/overview?from&to` | frequência, consistência, duração, resumo por modalidade |
| GET | `/analytics/muscles?from&to` | Meu Corpo: `{methodology_version, period_days, muscles:[{muscle_id, weighted_sets, weighted_sets_per_week, band, frequency, volume_load_kg}]}` |
| GET | `/analytics/muscles/{muscle_id}?from&to&compare=previous` | detalhe: exercícios, evolução de cargas, comparação |
| GET | `/analytics/endurance?modality&from&to` | distância/pace por semana |
| GET | `/analytics/compare?metric&a_from&a_to&b_from&b_to` | comparação de períodos (percentual só com base válida) |
| GET ✅ | `/analytics/records` | recordes pessoais |

### Fase 4: IA
| Método | Caminho | Descrição |
|---|---|---|
| POST | `/ai/conversations` | cria com `scope` + `scope_ref` |
| GET | `/ai/conversations` · `/ai/conversations/{id}` | histórico |
| POST | `/ai/conversations/{id}/messages` | envia a pergunta; resposta com texto + propostas (streaming SSE opcional) |
| DELETE | `/ai/conversations/{id}` | exclusão |
| GET | `/ai/proposals?status=pending` | propostas |
| POST | `/ai/proposals/{id}/accept` · `/reject` | confirmação explícita |

### Fase 5: nutrição e corpo
| Método | Caminho | Descrição |
|---|---|---|
| GET/POST | `/foods` | catálogo + próprios; busca `q` |
| CRUD | `/meals`, `/meals/{id}/items` | refeições |
| GET | `/nutrition/daily?date` · `/nutrition/summary?from&to` | totais vs. metas |
| GET/PUT | `/nutrition/targets` | metas (com histórico) |
| CRUD | `/body-measurements` | peso e medidas |
| GET | `/analytics/body?metric&from&to` | tendência |

### Privacidade
| Método | Caminho | Descrição |
|---|---|---|
| GET | `/me/export` | exportação completa (JSON) |
| DELETE | `/me` | exclusão da conta (exige a senha) |

## Autenticação (implementada na etapa 2.1)

Resposta de `register`, `login` e `refresh`:

```json
{ "access_token": "<JWT>", "refresh_token": "<opaco>", "token_type": "bearer",
  "expires_in": 900, "refresh_expires_in": 2592000 }
```

| Situação | Status | `code` |
|---|---|---|
| Sem `Authorization` | 401 | `not_authenticated` |
| Access token inválido, expirado, de conta desativada ou refresh usado como access | 401 | `invalid_token` |
| E-mail inexistente **ou** senha errada (resposta idêntica) | 401 | `invalid_credentials` |
| Conta desativada (só depois da senha correta) | 403 | `account_disabled` |
| E-mail já cadastrado | 409 | `email_already_registered` |
| Senha fora da política, termos não aceitos, campo extra | 422 | `validation_error` (com `errors[].field`) |
| Refresh desconhecido, expirado ou revogado | 401 | `invalid_refresh_token` |
| Refresh já rotacionado reapresentado (a família é revogada) | 401 | `refresh_token_reused` |
| Limite de tentativas | 429 | `too_many_requests` + `Retry-After` |

Todo 401 traz `WWW-Authenticate: Bearer`. O access token contém apenas `sub` (id), `jti`, `iss`, `typ`, `iat` e `exp` — nenhum dado pessoal.

## Perfil e consentimentos (implementados na etapa 2.2)

`PATCH /me` — atualização parcial; campos ausentes não mudam, `null` limpa os opcionais e esvazia as listas. Campos: `display_name`, `birth_year` (13–100 anos), `sex_for_calculations`, `timezone` (IANA), `unit_system`, `experience_level`, `weekly_availability` (`{days_per_week 1–7, minutes_per_session 10–300}`), `primary_objective`, `secondary_objectives` (≤ 5, sem repetir o principal), `preferred_modalities`, `equipment`, `dietary_preferences`, `limitation_tags`, `limitations_note` (≤ 1000), `onboarding_completed: true`. Os vocabulários ficam em `app/modules/users/vocabulary.py` e são expostos em `GET /profile-options`.

| Situação | Status | `code` |
|---|---|---|
| Valor fora do vocabulário, repetido, fora da faixa, campo extra (ex.: `email`, `user_id`) | 422 | `validation_error` |
| `limitation_tags`/`limitations_note` não vazios sem consentimento `health_data` ativo | 403 | `consent_required` |
| `PUT /me/consents/terms_privacy` (aceito só no cadastro) | 422 | `validation_error` |
| `DELETE /me/consents/terms_privacy` | 409 | `consent_not_revocable` |

Os logs registram só os **nomes** dos campos alterados, nunca os valores.

## Metas (implementadas na etapa 2.3)

`POST /goals` — `kind`, `title` (2–80), `target` (objeto validado pelos campos do tipo), `start_date` (opcional; padrão: hoje no fuso do perfil), `target_date` (opcional), `priority` (1 alta, 2 média, 3 baixa; padrão 2). Responde `201` com `Location` e a meta, incluindo `summary` (o alvo em texto, ex.: "5 km em 25:30").

`PATCH /goals/{id}` — parcial: `title`, `target` (validado pelo tipo existente), `start_date`, `target_date` (`null` remove o prazo), `status` (`active|achieved|abandoned`), `priority`. O tipo não muda. Sair de `active` grava `closed_at`; reativar o limpa.

Tipos e campos (fonte única: `app/modules/goals/kinds.py`, expostos em `GET /goal-options`; unidades métricas):

| `kind` | `target` |
|---|---|
| `strength` | `exercise` (texto 2–80), `load_kg` (1–500, passo 0,5), `reps` (1–30) |
| `hypertrophy` | `muscle_group` (grupos de DATA_MODEL §3), `weekly_sets` (1–40) |
| `weight_loss` / `weight_gain` 🔒 | `target_weight_kg` (30–300, passo 0,1) |
| `weight_maintenance` 🔒 | `target_weight_kg`, `tolerance_kg` (0,5–5, passo 0,5) |
| `run_distance` | `distance_km` (0,1–100, passo 0,1) |
| `run_time` | `distance_km`, `time_s` (60–86 400) |
| `frequency` | `sessions_per_week` (1–14), `modality` (opcional) |
| `habit` | `description` (texto 2–120), `days_per_week` (1–7) |
| `custom` | `description` (opcional, até 500) |

🔒 Peso é dado de saúde: exige o consentimento `health_data`, e revogá-lo apaga essas metas.

| Situação | Status | `code` |
|---|---|---|
| Tipo inválido, campo do alvo ausente, desconhecido, fora da faixa ou fora do passo; campo extra (ex.: `user_id`, `kind` no PATCH) | 422 | `validation_error` (campo como `target.load_kg`) |
| Prazo no passado (na criação), antes do início ou além de 10 anos; início fora de −5 anos/+1 ano | 422 | `validation_error` |
| Meta de peso sem `health_data` ativo | 403 | `consent_required` |
| 30 metas ativas (ao criar ou reativar) | 409 | `goal_limit` |
| Meta de outra pessoa ou inexistente | 404 | `not_found` |

Os logs registram o id e o tipo da meta, nunca o título ou o alvo.

## Biblioteca de exercícios (implementada na etapa 2.4)

O catálogo global (71 exercícios em PT-BR, seed `v1`, ADR-016) chega com a migração 0004. Os ids dos exercícios do catálogo são UUID v5 derivados do slug: são os mesmos em qualquer ambiente.

`GET /exercises` — visíveis para o usuário: catálogo + os próprios, em ordem alfabética (sem acentos). `q`: cada palavra precisa aparecer no nome, ignorando acentos e maiúsculas (curingas do SQL não valem). `muscle`: o músculo aparece como principal ou secundário. `equipment`: um ou mais (`?equipment=bodyweight&equipment=bands`). `mine=true`: só os próprios. `include_archived=true`: inclui os próprios arquivados. Cada exercício traz `is_custom`, `muscles` (principais primeiro, na ordem do catálogo) e `images`: caminhos das fotos de posição inicial e final (`/api/v1/media/exercises/{slug}/0.jpg` e `1.jpg`), vazio para exercícios próprios e para os 4 do catálogo sem foto. As fotos são arquivos públicos, sem login, com `Cache-Control: public, max-age=86400`.

`POST /exercises` — exercício próprio: `name` (2–80, único entre os seus, sem diferenciar maiúsculas e acentos), `instructions` (até 2000), `mechanics`, `equipment`, `load_type`, `unilateral`, `muscles` (`[{muscle_group_id, role}]`, ao menos um principal, sem repetir). `PATCH /exercises/{id}` — parcial; `muscles` substitui a lista; `is_active: false` arquiva (não há exclusão: as sessões vão apontar para o exercício).

| Situação | Status | `code` |
|---|---|---|
| Vocabulário inválido, sem músculo principal, músculo repetido, campo extra (ex.: `owner_user_id`) | 422 | `validation_error` |
| Nome repetido entre os seus | 409 | `exercise_exists` |
| 200 exercícios próprios | 409 | `exercise_limit` |
| Alterar um exercício do catálogo | 403 | `exercise_read_only` |
| Exercício próprio de outra pessoa ou inexistente | 404 | `not_found` |

## Fichas de treino (implementadas na etapa 2.5)

A ficha é enviada **inteira** em `POST /workout-templates` e `PUT /workout-templates/{id}` (ADR-031):

```json
{
  "name": "Treino A",
  "notes": null,
  "groups": [{"kind": "biset", "rest_after_s": 90}],
  "items": [
    {"exercise_id": "…", "planned_sets": [{"kind": "warmup", "reps_min": 15}, {"reps_min": 8, "reps_max": 12, "load_kg": 60, "rir_target": 2}], "rest_s": 120, "notes": null, "group": null},
    {"exercise_id": "…", "planned_sets": [{"reps_min": 10}], "group": 0},
    {"exercise_id": "…", "planned_sets": [{"reps_min": 10}], "group": 0}
  ]
}
```

- `items` na ordem de execução (até 30); `group` é o índice em `groups`.
- **Grupos:** membros em sequência; `biset` e `superset` têm 2 exercícios, `triset` 3 e `giant_set` de 4 a 6. `rest_after_s` é o descanso depois da rodada.
- **Séries planejadas** (1 a 10 por exercício): `kind` (`warmup|working|drop|rest_pause`); repetições (`reps_min`/`reps_max`, 1–100; só uma delas preenche as duas) **ou** `duration_s` (5–3600), conforme o exercício seja por tempo (`load_type = time`) ou não; `load_kg` (0–1000, passo 0,25) e `rir_target` (0–5) opcionais.
- `rest_s` (0–600) é o descanso entre as séries do exercício.
- A resposta tem o mesmo formato, mais `id`, `position`, o exercício resumido em cada item e o resumo `exercise_count`, `set_count` (sem aquecimento) e `muscles` (principais).
- `PUT /workout-templates/order` recebe `{"template_ids": [...]}` com todas as fichas do usuário, cada uma uma vez.

| Situação | Status | `code` |
|---|---|---|
| Grupo fora de sequência, vazio ou com tamanho errado; série sem repetições nem duração (ou com as duas); exercício por tempo com repetições; campo extra | 422 | `validation_error` (campo como `groups.0` ou `items.1.planned_sets.0`) |
| Exercício próprio de outra pessoa ou inexistente | 422 | `validation_error` (`items.N.exercise_id`) |
| 50 fichas | 409 | `template_limit` |
| Ficha de outra pessoa ou inexistente | 404 | `not_found` |

## Sessões de treino (implementadas na etapa 2.6)

- `POST /workout-sessions` — `{"template_id": "…"}` copia da ficha os exercícios, grupos, séries planejadas e descansos (a ficha pode mudar ou sair depois sem afetar o treino); sem `template_id`, treino livre ("Treino livre" ou `name`). Uma sessão aberta (em andamento ou pausada) por usuário: a segunda recebe `409 session_in_progress`, com o id da aberta em `errors[0].message`.
- **Resposta (`SessionOut`)**: `status` (`in_progress|paused|completed`), `started_at`, `paused_total_s`, `elapsed_s` (tempo ativo calculado no servidor na hora da resposta: o app soma o tempo local, sem depender do relógio do aparelho), `groups`, `exercises` (com `planned_sets`, `rest_s`, `sets` feitas e `previous`: as séries da última sessão concluída com o exercício, base do pré-preenchimento, mais `previous_at`) e o resumo `set_count` (sem aquecimento) e `volume_kg` (carga × repetições, só carga externa).
- **Séries**: `POST …/sets` com `kind` (`warmup|working|drop|rest_pause`), `reps` (1–200) **ou** `duration_s` conforme o exercício seja por tempo, `load_kg` (passo 0,25), `rir` (0–10) e `rpe` (1–10, passo 0,5) opcionais. `PATCH` corrige; `DELETE` apaga. Até 20 séries por exercício e 30 exercícios por treino.
- **Ciclo**: `pause`/`resume` acumulam `paused_total_s`; `finish` (`perceived_effort` 1–10 e `notes` opcionais) exige ao menos uma série e grava a duração ativa; `discard` apaga o treino aberto (atividade, exercícios e séries).

| Situação | Status | `code` |
|---|---|---|
| Já existe um treino aberto | 409 | `session_in_progress` |
| Alterar um treino concluído | 409 | `session_closed` |
| Finalizar sem séries | 422 | `session_empty` |
| Série sem repetições (ou com duração) num exercício por repetições, e o contrário; tipo desconhecido; campo extra | 422 | `validation_error` |
| Drop/rest-pause sem `parent_set_id`, apontando para aquecimento, outro segmento, outro exercício ou série de outra pessoa; série principal com `parent_set_id`; mais de 5 segmentos | 422 | `validation_error` (`parent_set_id`) |
| `to_failure` com `rir` maior que 0; mudar o tipo de um segmento; virar aquecimento uma série que tem segmentos | 422 | `validation_error` |
| Ficha, treino, exercício ou série de outra pessoa (ou inexistente) | 404 | `not_found` |

## Técnicas na sessão (implementadas na etapa 2.7)

- **Drop set e rest-pause são segmentos** da série que continuam: `POST …/sets` com `kind` `drop` ou `rest_pause` e `parent_set_id` = id de uma série **válida** (`working`) do mesmo exercício no mesmo treino. Até 5 segmentos por série. O tipo de um segmento não muda no `PATCH`; apagar a série apaga os segmentos dela.
- **Até a falha**: `to_failure` (booleano) em qualquer série ou segmento, no `POST` e no `PATCH`. Com `to_failure`, `rir` só pode ser 0 ou vazio.
- **Resposta**: `SetOut.parent_set_id` (nulo nas séries principais). No resumo, `set_count` conta só as séries principais válidas (um drop set é uma série); `volume_kg` soma os segmentos.
- **Pré-preenchimento**: cada item de `previous` traz `to_failure` e `segments` (os segmentos daquela série na última sessão).
- **Na ficha**, uma série planejada como `drop`/`rest_pause` marca onde aplicar a técnica; no treino ela é registrada como `working` e os segmentos vêm depois.
- **Ajustes do exercício no treino**: `PATCH /workout-sessions/{id}/exercises/{seid}` com `rest_s` (0–600) e/ou `notes` (até 500; vazio limpa). Vale só para este treino (a ficha não muda) e devolve o treino inteiro. Treino concluído: `409 session_closed`; de outra pessoa: `404`.

## Histórico e recordes (implementados na etapa 2.8)

Só treinos **concluídos**, de atividades não excluídas, do dono do token. Recordes são calculados na hora (DATA_MODEL §3), sem tabela própria.

- `GET /workout-sessions?limit=20&before=…` — histórico, do mais recente. Cada item: `id`, `name`, `started_at`, `duration_s`, `set_count`, `volume_kg`, `exercise_count`, `exercise_names` (até 4) e `record_count`. `next_before` (data) vai como `before` na próxima página; nulo quando acabou.
- `GET /workout-sessions/{id}` — o mesmo detalhe do treino; concluído, traz `records`: os recordes batidos nele (`exercise_id`, `kind`, `value`, `reps`, `load_kg`, `previous`). `previous` (pré-preenchimento e comparação) passa a ser a última sessão **anterior a este treino**, não a mais recente.
- `GET /exercises/{id}/history?limit=10&before=…` — `records` (os melhores de sempre), `rep_records` (melhor carga para exatamente N repetições, 1 a 20), `sessions` (uma por treino: séries com `is_segment`, `volume_kg`, `best_e1rm` e os recordes batidos naquele dia) e `next_before`. Exercício próprio de outra pessoa: `404`.
- `GET /analytics/records` — por exercício feito, do mais recente: os recordes e `last_done_at`.

| `kind` | Exercícios | Valor |
|---|---|---|
| `max_load` | carga externa | maior carga numa série válida (com as repetições) |
| `best_e1rm` | carga externa | 1RM estimado por Epley, `carga × (1 + reps/30)`, só de 1 a 12 repetições — **estimativa**, não teste |
| `max_volume` | carga externa | maior volume num treino (inclui drop e rest-pause) |
| `max_reps` | peso do corpo, assistido | mais repetições numa série |
| `max_duration` | por tempo | maior duração numa série |

Aquecimentos não contam; segmentos (drop, rest-pause) só entram no volume. A primeira vez num exercício não conta como recorde batido (não havia com o que comparar).

## Envio idempotente de séries (etapa 2.9)

- `POST …/sets` aceita `client_id` (UUID gerado no app). Reenviar com o mesmo `client_id` no mesmo exercício devolve a série já salva, sem duplicar — vale para resposta perdida, app reaberto com o rascunho ou dois envios simultâneos (índice único `session_exercise_id + client_id`, migração 0007).
- O pai de um drop ou rest-pause pode vir por `parent_client_id` (o `client_id` da série de cima), para quando o app ainda não sabe o id dela no servidor. Não pode vir junto com `parent_set_id`; inexistente no exercício: `422` (`parent_client_id`).
- `SetOut` devolve `client_id`.

## Atividades (implementadas na etapa 3.1)

Corrida (`run`), caminhada (`walk`), ciclismo (`cycle`) e natação (`swim`), registradas à mão (`source = manual`). Musculação continua em `/workout-sessions`: a atividade por trás de um treino responde `404` aqui e não aparece na lista.

- **Corpo** (`POST`, campos planos): `modality`, `started_at` (com fuso; até 5 min no futuro, no máximo 5 anos atrás), `duration_s` (60 s a 24 h), `distance_m` (opcional; limite por modalidade: 300 km, 150 km, 1000 km, 30 km), `perceived_effort` (1–10), `notes` (até 1000). Só no ciclismo: `indoor` (padrão `false`). Só na natação: `pool_length_m` (10–100; sem piscina = águas abertas), `laps` (1–2000), `stroke` (`freestyle|breaststroke|backstroke|butterfly|mixed`). Campo de outra modalidade: `422` no campo, para não ser guardado e ignorado.
- **Natação na piscina**: sem `distance_m`, a distância é `voltas × piscina`; informada junto, precisa bater (`422 distance_m`). Corrigir voltas ou piscina recalcula a distância.
- **Resposta**: os campos acima mais `id`, `ended_at` (início + duração), `created_at`, `updated_at`; os de outras modalidades vêm `null`. Pace e velocidade ficam para a 3.2.
- **Lista**: da mais recente; `modality`, `before` (início da última da página anterior) e `limit` (1–50, padrão 20).
- **`PATCH`**: parcial; `null` limpa os opcionais; `started_at` e `duration_s` não podem ser `null`; `modality` não muda (`422`).
- **`DELETE`**: lógico (`deleted_at`), para os indicadores recalcularem o histórico; depois disso, `404`.
- **Posse**: tudo filtrado pelo dono do token; atividade de outra pessoa = `404`, igual a uma inexistente. As rotas novas entraram na matriz da 2.10.

## Pace, velocidade, FC e elevação (etapa 3.2)

- **Calculados, nunca guardados** (com distância e duração; sem distância, `null`): corrida, caminhada e ciclismo devolvem `pace_s_per_km` (inteiro) e `speed_kmh` (1 casa); a natação, `pace_s_per_100m`. 5 km em 30 min = `pace_s_per_km: 360` (6:00/km).
- **Velocidade improvável**: acima de 30 km/h (corrida), 15 (caminhada), 120 (ciclismo) ou 10 (natação) → `422 distance_m` (“confira a distância e a duração”). Vale no registro e na correção (mudando distância, duração, voltas ou piscina).
- **Campos opcionais novos** (migração 0009): `elevation_gain_m` (0–10 000; não se aplica à natação → `422`), `avg_hr` (30–230) e `max_hr` (30–250, não menor que a média → `422 max_hr`).
- **FC é dado de saúde**: gravar `avg_hr`/`max_hr` exige o consentimento `health_data` (`403 consent_required`, como as metas de peso); limpar (`null`) não exige. **Revogar `health_data` apaga a FC de todas as atividades** da pessoa (o resto da atividade fica).
