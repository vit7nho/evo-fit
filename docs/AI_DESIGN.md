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
│   ├── fake.py          # roteirizado/determinístico — testes
│   ├── demo.py          # modo demonstração: regras + ferramentas reais, sem IA externa (ADR-058)
│   ├── gemini.py        # adaptador do Google Gemini (REST, biblioteca padrão) (4.4, ADR-056)
│   ├── groq.py          # adaptador do Groq (Chat Completions no formato da OpenAI, REST) (ADR-057)
│   └── rotation.py      # HTTP e troca de modelo na cota, comuns aos dois
├── fallback.py          # vários provedores em ordem (AI_PROVIDER=gemini,groq,demo)
├── errors.py            # ProviderUnavailable, ProviderTimeout, ProviderRateLimited, InvalidModelOutput, ProviderNotConfigured
├── retry.py             # nova tentativa só para erros transitórios (máx. 2, espera crescente)
└── factory.py           # escolhe o provedor por AI_PROVIDER no ambiente

modules/ai_coach/
├── prompts/
│   └── coach.v1.md … coach.v3.md  # prompts de sistema versionados; o em uso é o coach.v3 (o hash e a versão vão para ai_run_logs)
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

Trocar de fornecedor = escrever um novo adaptador. Nenhum outro arquivo importa o SDK do fornecedor nem conhece o endereço ou o cabeçalho da API dele (um teste confere).

**Implementado na 4.4** (`providers/gemini.py`, ADR-056): `generateContent` da Gemini API por REST com `urllib` (sem dependência nova; transporte injetável nos testes). Ferramentas em `parametersJsonSchema` (o JSON Schema do Pydantic, com `$defs`, aceito como está); `assistant` vira o papel `model` com os `functionCall` e `tool` vira `functionResponse` (o resultado embrulhado em objeto). `ToolCall.signature` guarda a `thoughtSignature` do Gemini e o adaptador a devolve na rodada seguinte — sem ela a API recusa com 400 (verificado). Raciocínio `low` nos modelos 3.x; consumo de saída = resposta + raciocínio. Erros: 429 com o `retryDelay`, 5xx e rede transitórios, 4xx definitivos, bloqueio e chamada malformada como saída inválida; mensagens e logs levam só o código HTTP e o status do Google. `AI_FREE_TIER` liga as salvaguardas do plano gratuito (§8). `AI_MODEL` aceita uma lista (`a,b,c`): com 429 ou 503 no primeiro pedido da pergunta o adaptador passa ao próximo modelo, e o modelo com a cota do dia esgotada fica de lado (na memória do processo) até o prazo informado pelo Google; depois da primeira chamada de ferramenta a pergunta não troca de modelo (a assinatura é de quem a gerou). No app, as respostas mostram o Markdown básico que os modelos usam (negrito, itens de lista, títulos), sem pacote novo.

**Groq e cadeia de provedores** (ADR-057): `providers/groq.py` fala o formato da OpenAI (`tools` com `parameters`, `tool_calls` com argumentos em texto JSON, mensagens `tool`); os `$ref` do Pydantic são resolvidos no lugar; nos `gpt-oss`, raciocínio `low` sem o texto do raciocínio e uma ferramenta por vez. `AI_PROVIDER=groq,gemini` monta um `FallbackProvider`: com 429/503 no primeiro pedido, a pergunta vai ao próximo provedor; depois da primeira ferramenta, fica no provedor que começou. Dentro do Groq a troca de modelo vale também no meio da pergunta (o limite de 8.000 tokens por minuto estoura na terceira chamada; o `gpt-oss-20b` tem a própria cota). O registro da execução guarda o provedor e o modelo que de fato responderam.

**Implementado na 4.1** (`app/integrations/ai/`, ADR-049): `Message` (`user`, `assistant` com texto e/ou `tool_calls`, `tool` com `tool_results`; mensagens incoerentes são recusadas), `ToolSpec`, `ToolCall`, `ToolResult`, `Usage` e `Completion` (com `stop_reason` `end|tool_use|max_tokens` e o modelo que respondeu); o `FakeProvider` em dois modos — roteirizado (respostas, exceções ou funções do pedido; guarda cópia de cada pedido) e demonstração (texto fixo dizendo que é simulado, sem números); os erros com `code`, `transient` e `user_message`; `complete_with_retry` (só transitórios, 0,5 s e 1 s, `Retry-After` até 5 s); e `build_provider` (`fake` padrão; `anthropic` dá `ProviderNotConfigured` até a 4.4). *Depois:* a 4.4 escolheu o Gemini e o Groq (ADR-056, ADR-057) e acrescentou o modo `demo` (ADR-058); `anthropic` continua sem adaptador.

**Implementado na 4.3** (`modules/ai_coach/`, ADR-051): `orchestrator.py` (laço com até 6 consultas e 5 chamadas ao modelo por resposta — a última sem ferramentas, para forçar o texto —; pedidos além do limite voltam como erro explicado), `prompts/coach.v1.md` (versão e hash de 16 caracteres no registro), `context.py` (data de hoje, dia da semana, fuso, foco do modo específico e unidades — nada pessoal), `guardrails.py` (resposta com até 4000 caracteres e a conferência heurística de números) e `service.py`/`router.py` (conversas, consentimento, limites, falhas e registro). Na v1 a conferência não bloqueia: os números não conferidos vão só para `ai_run_logs.unverified_numbers`.

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

**Implementado na 4.2** (`app/modules/ai_coach/tools/`, ADR-050): as 11 ferramentas de leitura das Fases 2 e 3 — `get_profile_summary`, `get_goals`, `get_workout_history`, `get_current_session`, `get_session_detail`, `get_exercise_history`, `get_muscle_stimulus`, `compare_periods`, `get_activities`, `get_endurance_progress` e `search_exercises`. Ficaram para depois `get_nutrition_summary` e `get_body_trend` — **implementadas na 5.4** (ADR-061), só com números, sem nomes de alimentos nem observações — e `prepare_change_proposal` (4.6). Os arquivos agrupam as ferramentas por módulo (perfil, metas, treinos, análises, atividades), cada uma com seu modelo de entrada; períodos opcionais (padrão: os últimos 30 dias até hoje, no fuso da pessoa).

## 4. Modos de análise

- **Específico:** a conversa nasce com `scope` (`session`, `exercise`, `muscle`, `activity`, `period`) a partir de botões no app (“Perguntar à IA” no Meu Corpo, na sessão, etc.). O `scope_ref` entra no contexto inicial e orienta quais ferramentas usar primeiro.
- **Global:** `scope = global`; o modelo combina ferramentas de vários módulos.
- Uma conversa por foco: os atalhos **Perguntar à IA** abrem uma conversa específica, e “Perguntar sobre tudo” abre uma geral. O seletor no topo do chat foi descartado (ADR-052).

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
| Saída | Resposta não vazia; tamanho máx.; números citados checados de forma heurística contra os resultados das ferramentas da rodada (números ausentes nos resultados geram um alerta no log; a nova tentativa prevista não foi implementada). |
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

**Implementado na 4.6** (`modules/ai_coach/proposals.py`, ADR-053): tipos `template_add_exercise`, `template_replace_exercise`, `template_adjust_sets` e `goal_create`; a ferramenta de leitura `get_templates` dá os ids das fichas e dos itens; a proposta é validada pelas regras do serviço dono (`TemplateService.check`, `GoalService.check`), guarda a impressão digital da ficha e o texto do cartão; no máximo 3 abertas por conversa; aceitar valida de novo, recusa se a ficha mudou e aplica pelo `replace` da ficha ou pelo `create` da meta, gravando o status junto. Prompt `coach.v2` (o v1 continua no repositório).

## 8. Privacidade

- O e-mail, o nome real e os IDs internos desnecessários não são enviados ao modelo.
- `limitations_note` (texto livre) só é enviado se a pergunta envolver limitações/dor.
- `ai_run_logs` guarda metadados, não conteúdo. As conversas seguem a retenção definida em `SECURITY_PRIVACY.md`.

## 9. Testes

- **Unitários das ferramentas:** dados semeados para dois usuários; cada ferramenta retorna apenas os dados do usuário do contexto.
- **Orquestrador com `FakeProvider` roteirizado:** sequência de tool calls → resposta; limites de iteração; tratamento de argumentos inválidos; indisponibilidade/timeout/rate limit.
- **Segurança:** tentativa de passar `user_id` ou IDs de outro usuário → ignorada/negada; proposta inválida → rejeitada; meta nutricional extrema → rejeitada.
- **Avaliação (opcional, manual):** um conjunto de ~20 perguntas de referência (as do enunciado do projeto) executadas contra o provedor real, com uma checklist (usou ferramentas? números corretos? admitiu falta de dados?). Resultado registrado em `docs/` — útil para a banca. **(4.7)** Implementada como roteiro de testes (`tests/coach_eval.py`, ADR-054): 21 perguntas, checagens automáticas e relatório com a revisão humana; método e perguntas em `AVALIACAO_IA.md`. Com os provedores reais, a rodada completa ficou pendente por causa das cotas dos planos gratuitos (ADR-056, ADR-057; ver [LIMITACOES](LIMITACOES.md)).

## 10. Custos

Custo ≈ (tokens de entrada + saída) × preço do modelo. Para conter os custos: cartão de contexto enxuto, resultados de ferramentas resumidos, limite diário por usuário, modelo econômico por padrão e histórico de conversa truncado (últimas N mensagens + resumo). No TCC o custo é zero: Groq e Gemini nos planos gratuitos e o modo demonstração sem IA externa (ADR-056 a ADR-058); o limite por pessoa (`AI_DAILY_LIMIT`, `AI_PER_MINUTE_LIMIT`) e o máximo de tokens por resposta seguram o uso.

**Modo demonstração** (ADR-058): `providers/demo.py` responde por regras, sem IA externa, mas pelo mesmo orquestrador e pelas mesmas ferramentas — os números vêm dos registros da pessoa e passam pela mesma conferência. Palavras-chave escolhem a intenção; a intenção escolhe as ferramentas (uma ou várias por passo) e o modelo de texto da resposta. Dor, dieta, hormônio e outra conta: respostas fixas com encaminhamento, sem consulta. No fim da cadeia (`gemini,groq,demo`), é a reserva quando a cota acaba; a resposta vem marcada (`demo: true`) e o app avisa. Passa nas 21 perguntas da avaliação (teste sem rede).
