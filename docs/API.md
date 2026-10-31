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
| GET | `/muscle-groups` | catálogo de grupos |
| GET/POST | `/exercises` · GET/PATCH `/exercises/{id}` | biblioteca (global + próprios); filtros `muscle`, `equipment`, `q` |
| GET | `/exercises/{id}/history` | séries do usuário nesse exercício + recordes |
| CRUD | `/workout-templates`, `/workout-templates/{id}/items` | fichas, itens e grupos (bi-set etc.) |
| POST | `/workout-sessions` | iniciar (livre ou a partir de ficha; `409` se já houver uma em andamento) |
| GET | `/workout-sessions/current` · `/workout-sessions/{id}` | |
| POST | `/workout-sessions/{id}/pause` · `/resume` · `/finish` · `/discard` | ciclo de vida |
| POST/PATCH/DELETE | `/workout-sessions/{id}/exercises[/{seid}/sets[/{set_id}]]` | registro de séries (salvamento por série) |
| GET | `/workout-sessions/{id}/comparison?with=previous` | comparação com a sessão anterior da mesma ficha |

### Fase 3: modalidades e evolução
| Método | Caminho | Descrição |
|---|---|---|
| GET/POST | `/activities` · GET/PATCH/DELETE `/activities/{id}` | atividades (corpo discriminado por `modality`) |
| GET/POST | `/training-plans` · GET `/training-plans/{id}` | planos 5 km/10 km/caminhada |
| GET | `/analytics/overview?from&to` | frequência, consistência, duração, resumo por modalidade |
| GET | `/analytics/muscles?from&to` | Meu Corpo: `{methodology_version, period_days, muscles:[{muscle_id, weighted_sets, weighted_sets_per_week, band, frequency, volume_load_kg}]}` |
| GET | `/analytics/muscles/{muscle_id}?from&to&compare=previous` | detalhe: exercícios, evolução de cargas, comparação |
| GET | `/analytics/endurance?modality&from&to` | distância/pace por semana |
| GET | `/analytics/compare?metric&a_from&a_to&b_from&b_to` | comparação de períodos (percentual só com base válida) |
| GET | `/analytics/records` | recordes pessoais |

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
