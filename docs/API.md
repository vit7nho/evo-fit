# API — convenções e endpoints planejados

> **Planejamento.** Nenhum endpoint existe ainda. A fonte da verdade, depois de implementada, será o OpenAPI gerado (`/docs`, `/openapi.json`) e exportado para `docs/openapi.json` (ADR-008). Este arquivo registra as convenções e o mapa previsto.

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
| POST | `/auth/register` | cadastro + consentimento `terms_privacy` |
| POST | `/auth/login` | access + refresh |
| POST | `/auth/refresh` | rotação do refresh |
| POST | `/auth/logout` | revoga a família |
| GET/PATCH | `/me` | conta + perfil |
| PUT/DELETE | `/me/consents/{kind}` | conceder/revogar consentimento |
| GET/POST | `/goals` · GET/PATCH/DELETE `/goals/{id}` | metas |
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
