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

## 4. Identidade visual — tokens iniciais

Fonte da verdade: `packages/design-tokens/tokens.json` (Fase 1). Valores propostos:

**Cores (tema escuro padrão):**

| Token | Valor | Uso |
|---|---|---|
| `bg.base` | `#0A0D14` | fundo do app |
| `bg.surface` | `#121722` | cards |
| `bg.elevated` | `#1A2030` | sheets, menus |
| `border.subtle` | `#262E40` | divisórias |
| `text.primary` | `#E8ECF4` | texto principal (contraste > 15:1 com o fundo) |
| `text.secondary` | `#9AA4B8` | texto de apoio (≥ 4.5:1) |
| `accent` | `#4C7DFF` (azul elétrico) | ações primárias, foco, destaques |
| `accent.on` | `#FFFFFF` | texto sobre o acento |
| `success / warning / danger` | `#3CCB8B / #F2A93B / #F0566A` | estados |
| Faixas musculares | `none #3A4253` · `low #3D7BFF` · `mid #F28C28` · `high #E5484D` | Meu Corpo (com padrão/rótulo além da cor, por acessibilidade) |

Um único acento (azul) para manter a consistência; o violeta fica como alternativa avaliável nos tokens.

**Tipografia:** *Inter* para a interface (legibilidade, números tabulares para cargas/tempos) e *Space Grotesk* em títulos/números de destaque (o toque tecnológico). Escala: 12 / 14 / 16 / 20 / 24 / 32 / 40.
**Espaçamento:** base 4 → 4, 8, 12, 16, 24, 32, 48.
**Raios:** 8 (inputs), 14 (cards), 999 (chips). **Elevação:** por cor de superfície e borda sutil, com sombras mínimas.
**Movimento:** 150–250 ms, *ease-out*; respeitar a redução de movimento do sistema.
**Toque:** alvo mínimo de 48×48 dp.

## 5. Teste de usabilidade (Fase 5)

Tarefas com 3–5 participantes: (1) cadastrar-se e definir o objetivo; (2) criar uma ficha com um bi-set; (3) registrar 3 séries, incluindo um drop set; (4) registrar uma caminhada; (5) descobrir no Meu Corpo qual músculo recebeu menos estímulo; (6) perguntar à IA sobre a última sessão. Métricas: conclusão, tempo, erros, SUS.
