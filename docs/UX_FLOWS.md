# UX — navegação, fluxos e identidade visual

## 1. Navegação

Barra inferior com **5 destinos** (mais que isso fica apertado em telas pequenas):

| Aba | Conteúdo |
|---|---|
| **Início** | Dashboard personalizado + botão “Registrar” (FAB) |
| **Treino** | Fichas, sessão em andamento, biblioteca de exercícios, histórico |
| **Atividades** | Corrida, caminhada, ciclismo, natação; planos; histórico |
| **Evolução** | Meu Corpo · Métricas · Gráficos · Comparativos · Histórico (abas internas) |
| **IA** | Conversas (global/específica) |

**Nutrição** e **Perfil**: acesso pelo Início (card de nutrição + avatar no topo). Se o usuário marcar nutrição como módulo principal no onboarding, a aba **Atividades** pode ser trocada por **Nutrição** — a barra se adapta às modalidades escolhidas (configurável no Perfil). Módulos não usados não aparecem no dashboard.

## 2. Fluxos principais

**Onboarding (≤ 5 passos, todos puláveis exceto o 1):**
1. Conta + aceite de termos.
2. Objetivo principal (cartões: ganhar massa, emagrecer, manter, correr, criar o hábito de caminhar, saúde geral) + objetivos secundários.
3. Modalidades e experiência por modalidade.
4. Disponibilidade (dias/semana, minutos) e equipamentos.
5. Limitações (opcional, com explicação do uso e consentimento `health_data`) → dashboard.

**Registrar série (caminho crítico — meta: ≤ 2 toques por série):**
- A tela da sessão lista os exercícios em cartões; o exercício atual fica expandido.
- Cada linha de série mostra: tipo (aquecimento/efetiva), carga e reps **pré-preenchidas com a última sessão** (em cinza, como “referência”), e um botão ✓.
- Toque no ✓ = salva a série (otimista, com retentativa e indicação de erro na linha) e inicia o cronômetro de descanso (barra fixa na base, com +15 s/−15 s/pular).
- Toque longo/menu na série: transformar em drop set (adiciona segmentos encadeados), rest-pause, marcar falha, observação.
- Bi-set/supersérie: os cartões do grupo aparecem unidos por uma barra lateral colorida e o cronômetro só dispara ao final do grupo.

**Registrar corrida/caminhada:** formulário único: modalidade, data/hora, duração (com seletor h:m:s), distância (opcional para caminhada), RPE (escala 1–10 com descrições), campos avançados recolhidos (FC, elevação), notas. O pace aparece ao vivo quando há distância e duração.

**Meu Corpo:** alternador Frente/Costas · seletor de período (7 d, 30 d, 90 d, personalizado) · legenda das faixas com aviso “referência de volume registrado, não diagnóstico” · toque no músculo → *bottom sheet* com séries ponderadas/semana, frequência, exercícios, evolução de carga, comparação com o período anterior e os botões **Perguntar à IA** e **Sugerir exercícios** (abre o chat com o escopo `muscle`).

**IA:** campo de mensagem com sugestões contextuais; as respostas mostram chips “dados usados” (ferramentas consultadas e período); as propostas aparecem como cartão com diff e os botões Confirmar/Recusar.

## 3. Estados obrigatórios por tela

Carregando (*skeleton*, não um *spinner* em tela cheia), vazio (explica e oferece a ação principal — ex.: “Nenhuma sessão ainda. Criar ficha”), erro (mensagem humana + tentar novamente; erros de validação no próprio campo), sucesso (feedback discreto: *snackbar*/háptico), offline (faixa informativa; a sessão em andamento continua em rascunho).

## 4. Identidade visual

Fonte da verdade: `packages/design-tokens/tokens.json`, gerado para Dart e CSS por `scripts/generate_tokens.py`. Monocromática e clara desde a etapa 2.1 (ADR-025), no app e no site.

**Cores:**

| Token | Valor | Uso |
|---|---|---|
| `bg-base` | `#F6F5F1` (off-white) | fundo do app e do site; abertura nativa do Android |
| `bg-surface` | `#FFFFFF` | cards, campos, diálogos |
| `bg-elevated` | `#ECEBE6` | esqueletos de carregamento, botões desabilitados, ícones em círculo |
| `border-subtle` | `#E3E2DC` | bordas de cards e divisórias |
| `border-strong` | `#8A8983` | contorno dos campos (3,2:1 com o fundo — mínimo de 3:1 da WCAG para componentes) |
| `text-primary` | `#0C0C0D` | texto principal (17,9:1) |
| `text-secondary` | `#5E5E63` | texto de apoio (5,9:1 no fundo; 6,5:1 no branco) |
| `accent` / `on-accent` | `#0C0C0D` / `#FFFFFF` | ação principal: preto com texto branco |
| `success / warning / danger` | `#1E7F4F / #A35F00 / #C62D2D` | só para estados (≥ 5:1 no branco) |
| Faixas musculares | `none #DCDBD5` · `low #3D7BFF` · `mid #F28C28` · `high #E5484D` | Meu Corpo — a única exceção à paleta monocromática, porque é dado (com padrão/rótulo além da cor) |

**Componentes:** botões em pílula de 56 dp (primário preto; secundário branco com contorno); campos brancos com contorno e ícone à esquerda; cards brancos com borda sutil, sem sombra no app.
**Tipografia:** títulos grandes e pesados com espaçamento negativo (44 / 34 px); fonte do sistema no app e *Inter* + *Space Grotesk* no site. Escala: 12 / 14 / 16 / 20 / 24 / 34 / 44.
**Espaçamento:** base 4 → 4, 8, 12, 16, 24, 32, 48.
**Raios:** 14 (campos), 22 (cards), 999 (botões e chips).
**Movimento** (`app/theme/motion.dart` e `globals.css`):
- Curvas *emphasized* do Material 3; durações 150 / 250 / 400 ms e 420 ms para troca de tela.
- Troca de tela: a nova sobe 3,5 % e aparece; a anterior recua (escala 0,97) e esmaece.
- Entrada em cascata dos blocos de cada tela (60 ms entre eles), sem timers.
- Botões e cards encolhem levemente sob o dedo (0,97–0,98).
- Avisos de erro abrem e fecham o espaço suavemente; o botão troca texto e indicador com um cruzamento.
- Tudo é desligado quando o sistema pede redução de movimento.

**Toque:** alvo mínimo de 48×48 dp.

## 5. Teste de usabilidade (Fase 5)

Tarefas com 3–5 participantes: (1) cadastrar-se e definir o objetivo; (2) criar uma ficha com um bi-set; (3) registrar 3 séries, incluindo um drop set; (4) registrar uma caminhada; (5) descobrir no Meu Corpo qual músculo recebeu menos estímulo; (6) perguntar à IA sobre a última sessão. Métricas: conclusão, tempo, erros, SUS.
