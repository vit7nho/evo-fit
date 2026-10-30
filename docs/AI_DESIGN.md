# Design da IA contextual

## 1. Princípios

1. **A IA interpreta; o backend calcula.** Todo número citado pela IA vem de uma ferramenta que executa código determinístico e testado.
2. **Contexto mínimo e pertinente.** Nada de despejar o banco no prompt. O modelo pede os dados por ferramentas com escopo e período.
3. **Escopo do usuário garantido pelo servidor.** As ferramentas não recebem `user_id` do modelo; o executor injeta o usuário autenticado.
4. **Nenhuma escrita direta.** As alterações viram `change_proposals`, que o usuário confirma na interface.
5. **Honestidade e segurança em saúde.** Separar fatos de hipóteses, admitir falta de dados, não diagnosticar e encaminhar a profissionais quando necessário.

## 2. Componentes (`services/api/app/integrations/ai` + `modules/ai_coach`)

```
integrations/ai/
├── provider.py          # Protocol LLMProvider + tipos neutros (Message, ToolSpec, ToolCall, Completion, Usage)
├── providers/
│   ├── fake.py          # roteirizado/determinístico — testes e demonstração offline
│   └── anthropic.py     # adaptador (SDK oficial ou httpx); único lugar que conhece o fornecedor
├── errors.py            # ProviderUnavailable, ProviderRateLimited, InvalidModelOutput
└── factory.py           # escolhe o provedor por AI_PROVIDER no ambiente

modules/ai_coach/
├── prompts/
│   └── coach.v1.md      # prompt de sistema versionado (o hash e a versão vão para ai_run_logs)
├── tools/               # uma ferramenta por arquivo: schema de entrada Pydantic + handler + schema de saída
├── context.py           # monta o cartão de contexto mínimo (objetivos, modalidades, limitações-tag, unidades)
├── orchestrator.py      # laço: modelo → tool calls → executor → modelo … (máx. N iterações)
├── guardrails.py        # validação de saída, filtros de segurança, limites
├── service.py / router.py
```

Interface neutra:

```python
class LLMProvider(Protocol):
    def complete(self, *, system: str, messages: list[Message], tools: list[ToolSpec],
                 max_tokens: int, timeout_s: float) -> Completion: ...
```

Trocar de fornecedor = escrever um novo adaptador. Nenhum outro arquivo importa o SDK do fornecedor.

## 3. Ferramentas (v1)

Todas são somente leitura, exceto `prepare_change_proposal`. Os nomes estão em inglês por convenção do código; as descrições enviadas ao modelo ficam em português.

| Ferramenta | Entrada (validada) | Saída |
|---|---|---|
| `get_profile_summary` | — | objetivos ativos, modalidades, experiência, disponibilidade, `limitation_tags` (o texto livre só se a pergunta tratar de limitações) |
| `get_goals` | `status?` | metas e progresso calculado |
| `get_workout_history` | `from, to, limit≤20` | sessões resumidas (data, ficha, duração, nº de séries) |
| `get_current_session` | — | sessão em andamento, se houver |
| `get_session_detail` | `session_id` | exercícios, séries, cargas, técnicas |
| `get_exercise_history` | `exercise_id \| name, from?, to?` | séries por data, melhores marcas, tendência de e1RM (rotulada como estimativa) |
| `get_muscle_stimulus` | `from, to, muscle_ids?` | séries ponderadas/semana, faixa, frequência, exercícios, versão da metodologia |
| `compare_periods` | `metric, period_a, period_b` | valores, diferença absoluta; percentual só quando a base for válida |
| `get_activities` | `modality?, from, to, limit≤30` | atividades com métricas presentes (ausentes = `null`, nunca estimadas) |
| `get_endurance_progress` | `modality, from, to` | distância semanal, pace médio quando calculável, consistência |
| `get_nutrition_summary` | `from, to` | médias diárias vs. metas configuradas, dias registrados (cobertura) |
| `get_body_trend` | `metric, from, to` | série temporal e tendência (média móvel) |
| `search_exercises` | `muscle_id?, equipment?, query?` | exercícios do catálogo compatíveis com o equipamento do usuário |
| `prepare_change_proposal` | união discriminada por `kind` | cria uma `change_proposal` `pending` e devolve o resumo para a IA apresentar |

Limites: máx. 6 chamadas de ferramenta por resposta; resultados truncados (ex.: 30 itens) com o indicador `truncated: true`; períodos limitados a 366 dias.

## 4. Modos de análise

- **Específico:** a conversa nasce com `scope` (`session`, `exercise`, `muscle`, `activity`, `period`) a partir de botões no app (“Perguntar à IA” no Meu Corpo, na sessão, etc.). O `scope_ref` entra no contexto inicial e orienta quais ferramentas usar primeiro.
- **Global:** `scope = global`; o modelo combina ferramentas de vários módulos.
- O usuário alterna entre os modos por um seletor no topo do chat; a troca cria uma nova conversa vinculada (o contexto fica limpo e explícito).

## 5. Prompt de sistema (resumo do `coach.v1.md`)

- Papel: assistente de acompanhamento de treino e hábitos, em PT-BR, tom objetivo e encorajador.
- Usar **somente** dados retornados pelas ferramentas; se não houver dados, dizer isso e sugerir o que registrar.
- Marcar explicitamente o que é **dado registrado**, o que é **cálculo** e o que é **hipótese/sugestão**.
- Respeitar as limitações informadas; diante de dor, sintomas cardíacos, tontura ou lesão → recomendar avaliação profissional e não prescrever.
- Proibido: diagnósticos, promessas de resultado, dietas muito restritivas (ex.: metas abaixo de limites mínimos configurados), recomendações de fármacos/suplementos hormonais.
- Alterações em fichas/metas: somente por `prepare_change_proposal`, deixando claro que é preciso confirmar.

## 6. Guardrails e validação

| Camada | Verificação |
|---|---|
| Entrada | Tamanho máx. da mensagem; consentimento `ai_processing` ativo; limite diário por usuário (ex.: 30 mensagens) e por minuto. |
| Ferramentas | Argumentos validados por Pydantic; erro de validação volta ao modelo como mensagem de ferramenta (1 nova tentativa). |
| Propostas | Payload validado pelo serviço dono da entidade (exercício existe e é visível, séries dentro de limites, meta coerente). Regras de segurança nutricional: meta de kcal abaixo do mínimo configurado → rejeitada. |
| Saída | Resposta não vazia; tamanho máx.; números citados checados de forma heurística contra os resultados das ferramentas da rodada (números ausentes nos resultados geram um alerta no log e, na v2, uma nova tentativa). |
| Falhas | Timeout (30 s), `429` e `5xx` do provedor → mensagem amigável + `outcome` registrado; *retry* com backoff só para erros transitórios (máx. 2). |

## 7. Fluxo de confirmação de alterações

```
usuário: "adicione um exercício para posterior de coxa na ficha B"
  → IA: search_exercises(muscle_id="hamstrings", equipment=...) → prepare_change_proposal(kind="template_add_exercise", ...)
  → API devolve a mensagem + card da proposta {id, resumo, diff}
  → app mostra [Confirmar] [Recusar]
  → POST /api/v1/ai/proposals/{id}/accept → serviço de training valida de novo e aplica em transação
```

Propostas expiram em 7 dias. Uma proposta aceita registra `decided_at` e o resultado.

## 8. Privacidade

- O e-mail, o nome real e os IDs internos desnecessários não são enviados ao modelo.
- `limitations_note` (texto livre) só é enviado se a pergunta envolver limitações/dor.
- `ai_run_logs` guarda metadados, não conteúdo. As conversas seguem a retenção definida em `SECURITY_PRIVACY.md`.

## 9. Testes

- **Unitários das ferramentas:** dados semeados para dois usuários; cada ferramenta retorna apenas os dados do usuário do contexto.
- **Orquestrador com `FakeProvider` roteirizado:** sequência de tool calls → resposta; limites de iteração; tratamento de argumentos inválidos; indisponibilidade/timeout/rate limit.
- **Segurança:** tentativa de passar `user_id` ou IDs de outro usuário → ignorada/negada; proposta inválida → rejeitada; meta nutricional extrema → rejeitada.
- **Avaliação (opcional, manual):** um conjunto de ~20 perguntas de referência (as do enunciado do projeto) executadas contra o provedor real, com uma checklist (usou ferramentas? números corretos? admitiu falta de dados?). Resultado registrado em `docs/` — útil para a banca.

## 10. Custos

Custo ≈ (tokens de entrada + saída) × preço do modelo. Para conter os custos: cartão de contexto enxuto, resultados de ferramentas resumidos, limite diário por usuário, modelo econômico por padrão e histórico de conversa truncado (últimas N mensagens + resumo). Valores concretos dependem do provedor escolhido (ADR-012).
