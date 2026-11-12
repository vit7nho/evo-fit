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

**Início — painel pelo objetivo** (etapa 3.8; `GET /dashboard`): abaixo da saudação, “Seu foco: <objetivo principal>.” e o painel, montado pela API: **Esta semana** (dias ativos contra a meta de dias do perfil, com barra e ✓ verde ao bater; treinos e tempo; a semana passada e a sequência de semanas ativas) → **Seu foco**, na ordem do objetivo — quem quer correr ou criar o hábito de caminhar vê primeiro o plano ativo (semana, sessões feitas e a próxima), quem quer ganhar massa vê primeiro a musculação (séries e volume dos últimos 7 dias contra os 7 anteriores) com o Meu Corpo (“6 músculos sem nenhuma série em 30 dias, como …”), e cada modalidade preferida no perfil ou registrada nos últimos 30 dias ganha um cartão (distância e ritmo dos últimos 7 dias); modalidade não usada não aparece → **Metas**: as 3 primeiras ativas, com barra de progresso quando os registros medem a meta (carga, séries por semana, corrida mais longa, tempo pelo melhor pace, treinos na semana), “Alvo atingido” em verde com o convite para marcá-la, e “Ver as N” quando há mais → **Último registro** (hoje, ontem, há N dias) → **Atalhos** (os cartões de antes). Cada cartão abre a tela dele, e ao voltar o painel é refeito (um treino novo ou uma meta marcada aparece na hora). Carregando: esqueleto; erro: mensagem com “Tentar novamente” e os atalhos continuam.

**Metas** (etapa 2.3): cartão no Início com o número de metas ativas → lista (ativas por prioridade e prazo; concluídas abaixo) → “Nova meta” escolhe o tipo e abre um formulário montado a partir dos campos que a API descreve para esse tipo. Na edição: marcar como alcançada, abandonar, reativar ou excluir (com confirmação). Prazo vencido aparece com ícone e texto, não só cor.

**Fichas** (etapa 2.5; vão para a aba Treino quando ela existir): cartão no Início → lista na ordem do usuário (segurar e arrastar reordena; o TalkBack oferece mover para cima/baixo) → editor com nome, anotações e os exercícios. “Adicionar exercícios” abre a biblioteca com seleção múltipla, na ordem marcada. Cada exercício tem menu de ações (séries e descanso, mover, juntar com o próximo, tirar do grupo, remover); grupos aparecem num contorno com cabeçalho (tipo e descanso após a rodada, ajustáveis). A ficha é salva de uma vez; sair com alterações pede confirmação.

**Histórico** (etapa 2.8; na 3.7, o histórico do exercício ganhou o gráfico “1RM estimado por treino”, do mais antigo ao mais recente, só dos treinos com carga carregados na tela; vai para a aba Treino/Evolução quando existirem): cartão no Início → abas “Treinos” (data, nome, duração, séries, volume, exercícios e selo de recordes; “Carregar mais”) e “Recordes” (por exercício). O detalhe do treino mostra o resumo, os recordes batidos (“antes X”) e cada exercício com as séries (A, número, F, D, RP) e a comparação com a vez anterior (volume e melhor série com 1RM estimado). O histórico do exercício (pelo detalhe do treino, pelos recordes ou pelo botão “Histórico e recordes” no detalhe do exercício) mostra os recordes, a melhor carga por repetições e cada treino. Ao finalizar um treino, o resumo dele abre na hora; voltar leva ao Início. O 1RM aparece sempre como estimativa.

**Exercícios** (etapa 2.4; vai para a aba Treino quando ela existir): cartão no Início → biblioteca com busca sem acentos, filtro por músculo, “Meus” e “Só o que tenho” (cruza o equipamento do exercício com o que a pessoa marcou no perfil; some quando ela tem academia completa ou não marcou nada). O detalhe mostra os músculos principais e secundários, as características e “Como fazer”, com o aviso de que é uma orientação geral. Exercícios próprios podem ser criados, editados e arquivados (e restaurados em “Meus”).

**Nutrição** e **Perfil**: acesso pelo Início (card de nutrição + avatar no topo). Se o usuário marcar nutrição como módulo principal no onboarding, a aba **Atividades** pode ser trocada por **Nutrição** — a barra se adapta às modalidades escolhidas (configurável no Perfil). Módulos não usados não aparecem no dashboard.

## 2. Fluxos principais

**Onboarding (≤ 5 passos, todos puláveis exceto o 1)** — implementado na 2.2 (ADR-026): passos 2–5 em uma tela com barra de progresso; experiência única em vez de por modalidade:
1. Conta + aceite de termos.
2. Objetivo principal (cartões: ganhar massa, emagrecer, manter, correr, criar o hábito de caminhar, saúde geral) + objetivos secundários.
3. Modalidades e experiência por modalidade.
4. Disponibilidade (dias/semana, minutos) e equipamentos.
5. Limitações (opcional, com explicação do uso e consentimento `health_data`) → dashboard.

**Registrar série (caminho crítico — meta: ≤ 2 toques por série)** — refeito em tabela na 2.7 (ADR-034): cada exercício mostra `SÉRIE · ANTERIOR · KG · REPS · ✓`; todas as linhas ficam editáveis com a sugestão em cinza e podem ser concluídas fora de ordem; o ✓ preenchido desfaz; o número abre o menu do tipo (A aquecimento, número = válida, F até a falha, D drop, RP rest-pause, remover); descanso e nota ficam no cabeçalho do exercício; o topo mostra duração, volume e séries ao vivo. Versão da 2.6 (ADR-032), mantida no que não mudou: a próxima série tem os campos com a sugestão em cinza (última sessão, senão o plano, senão a série anterior de hoje); um toque no ✓ salva com a sugestão, digitar só o que mudou. As séries seguintes aparecem apagadas, só com a referência; as feitas mostram o ✓ verde e abrem para corrigir ou apagar. O número vira “A” no aquecimento (toque no número alterna). Erro ao salvar fica na linha, com os valores, para tentar de novo. O descanso começa sozinho (nos grupos, só no fim da rodada) numa barra preta acima de “Finalizar treino”, com −15 s, +15 s e pular; ao terminar, vibra e o leitor de tela anuncia. O tempo de treino fica numa faixa abaixo da barra do topo. Fechar e reabrir o app retoma pelo cartão “Treino em andamento” no Início. Detalhes do plano original:
- A tela da sessão lista os exercícios em cartões; o exercício atual fica expandido.
- Cada linha de série mostra: tipo (aquecimento/efetiva), carga e reps **pré-preenchidas com a última sessão** (em cinza, como “referência”), e um botão ✓.
- Toque no ✓ = salva a série (otimista, com retentativa e indicação de erro na linha) e inicia o cronômetro de descanso (barra fixa na base, com +15 s/−15 s/pular).
- Toque longo/menu na série: transformar em drop set (adiciona segmentos encadeados), rest-pause, marcar falha, observação. **Como ficou na 2.7 (ADR-033):** sem toque longo (gesto escondido); abaixo da última série feita aparecem “Drop”, “Rest-pause” e o chip “Até a falha”. O drop abre uma linha recuada com a carga sugerida (20% a menos, múltiplo de 2,5 kg, ou o drop da última vez) e cancela o descanso; o rest-pause começa com 15 s de pausa e repete a carga. Salvar o segmento inicia o descanso normal. Série planejada como drop/rest-pause na ficha avisa na linha e abre o segmento sozinha depois do ✓. Corrigir uma série feita (toque nela) também marca ou desmarca a falha.
- Bi-set/supersérie: os cartões do grupo aparecem unidos por uma barra lateral colorida e o cronômetro só dispara ao final do grupo.

**Registrar corrida/caminhada:** formulário único: modalidade, data/hora, duração (com seletor h:m:s), distância (opcional para caminhada), RPE (escala 1–10 com descrições), campos avançados recolhidos (FC, elevação), notas. O pace aparece ao vivo quando há distância e duração.

**Atividades** (etapa 3.1; vão para a aba Atividades quando ela existir): cartão no Início → lista da mais recente (modalidade, duração, distância, esforço, dia e hora; “Carregar mais”) → “Registrar atividade”. O formulário tem a modalidade em chips (só na criação), dia e hora (seletores do sistema), duração digitada (“45” = minutos, ou “1:05:30”), distância em km (na natação, em metros), esforço 1–10 e “Como foi?”. Ciclismo: “Em ambiente fechado”. Natação: piscina (25 m, 50 m, águas abertas); na piscina, as voltas substituem a distância e a tela mostra o total. Tocar numa atividade abre a edição, com “Excluir” no topo (confirmação); sair com alterações pede confirmação. Na 3.2: o ritmo aparece enquanto se digita (“Pace: 6:00 /km”; “Velocidade média: 30 km/h” no ciclismo; por 100 m na natação) e nos cartões da lista; “Mais detalhes” (recolhido, aberto quando já há dados) traz ganho de elevação (fora da natação), FC média e FC máxima. Com FC preenchida e sem a autorização de saúde, aparece o cartão “Autorizo o uso dos meus dados de saúde”, e salvar sem marcá-lo explica o motivo.

**Evolução** (etapa 3.4; vira a aba Evolução quando ela existir): cartão no Início → período em chips (7, 30 ou 90 dias até hoje; padrão 30) → cartões “Treinos e atividades”, “Tempo total” (cada um com a comparação com o período anterior do mesmo tamanho, em verde quando melhorou: “+2 (+50%) vs. 30 dias anteriores”; sem base, só a diferença) e “Dias ativos”; “Consistência” (semanas com treino, semanas que bateram a meta de dias do perfil, sequência atual e barras de sessões por semana — as 6 últimas); “Por modalidade” (vezes, tempo, distância; séries e volume na musculação) e, havendo corrida, distância, pace médio e a tendência da distância semanal. Sem registros no período, um vazio explica o que vai aparecer. **Na 3.7:** “Por semana” troca as barras simples por um gráfico de todas as semanas do período, com o indicador em chips (Treinos, Tempo e, havendo musculação, Séries e Volume; contagens com marcas inteiras no eixo); cada modalidade de resistência com distância (corrida, caminhada, ciclismo, natação) ganha um cartão com a distância por semana em barras e, com pelo menos 2 semanas medidas, o ritmo por semana em linha (pace por km, por 100 m na natação — “menor é melhor” — ou velocidade no ciclismo). Tocar numa barra ou ponto mostra a semana e o valor; o leitor de tela lê cada gráfico como uma frase com todos os valores. O eixo usa a data curta (“12/10”); a dica e o leitor de tela, a longa. O botão **Comparar**, no topo, abre os Comparativos.

**Comparativos** (etapa 3.7): atalhos em chips — 7 dias, 30 dias (padrão; os últimos N dias contra os N anteriores), Este mês (do dia 1 até hoje contra o mesmo trecho do mês passado, cortado no último dia quando o mês passado é mais curto) e Escolher — e os cartões dos períodos A (a base, letra em contorno) e B (letra preenchida), que abrem o calendário (até 366 dias cada). Um cartão por indicador: treinos e atividades, dias ativos, tempo total; havendo musculação em algum dos períodos, séries e volume; havendo distância, a distância de cada modalidade e o pace da corrida e da caminhada. Cada cartão tem duas barras (A e B) com os valores e a diferença (“+2 (+50%) no período B”, verde quando B é melhor; no pace o sinal engana e a frase diz “mais rápido” ou “mais lento”). O percentual só aparece com base válida, e um período sem valor mostra “sem dado” (nunca um zero inventado). Os números vêm todos da API (`/analytics/compare`). Nada registrado nos dois períodos: um vazio explica.

**Planos** (etapa 3.3): cartão “Planos” no Início e botão “Planos” no topo de Atividades. Sem plano ativo, a tela oferece os três planos (semanas já ajustadas para a pessoa, e o aviso do 10 km quando cabe) e lista os anteriores; com plano ativo, mostra o cartão dele com “Semana X de Y · N de M sessões” e a barra. A configuração tem os dias em chips (segunda, quarta e sexta já marcados; erro na hora para dias seguidos na corrida), o início (Hoje, Amanhã, Outro dia — até 4 semanas), os ajustes e avisos, e o lembrete de que as datas são sugestões e de parar com dor, tontura ou falta de ar. O plano mostra o progresso, a **próxima sessão** (a primeira não feita, em qualquer data) com “Registrar sessão” e “Usar atividade já registrada”, e as sessões por semana (✓ feita, ▶ próxima). “Registrar sessão” abre o formulário de atividade com o nome da sessão, a modalidade fixa e a duração prevista; ao salvar, a sessão é marcada (se a marcação falhar, a atividade fica e o aviso diz o motivo). “Usar atividade já registrada” lista as da modalidade desde o início do plano que ainda não contam para outra sessão. Tocar numa sessão abre os detalhes; feita, oferece “Ver atividade” e “Desmarcar sessão”. “Encerrar plano” fica no menu (confirmação).

**Meu Corpo** (etapa 3.6, cartão no Início; vira parte da aba Evolução quando ela existir): período em chips (7, 30 ou 90 dias até hoje; padrão 30) e “Outro período” (calendário, até 366 dias) · Frente/Costas · o mapa pintado pela faixa de cada músculo (cinza = nenhuma série; ombros e antebraços aparecem nos dois lados) · legenda com os limites da metodologia ativa (“Baixo: menos de 6”…), o aviso da API e a versão · uma frase com a resposta de “qual recebeu menos” (“Sem nenhuma série em 30 dias: …” ou “Com menos estímulo: … (0,5 séries/semana)”) · a lista dos 13 músculos com cor, séries/semana e faixa em texto (a alternativa acessível ao mapa: o leitor de tela lê o mapa como um resumo e a lista dá o mesmo toque). Tocar num músculo, no mapa ou na lista, contorna-o no mapa (virando para o lado em que ele aparece) e abre a folha com séries/semana e no período, dias treinados, volume, a comparação com o período anterior do mesmo tamanho, os exercícios (papel, séries, ponderadas, maior carga) e a maior carga de cada dia de cada exercício em linha (3.7), com a frase “Cargas: 50 kg (22 de set.) → 62,5 kg (9 de nov.)”. Os botões **Perguntar à IA** e **Sugerir exercícios** entram com o chat (4.5).

*Especificação original:* alternador Frente/Costas · seletor de período (7 d, 30 d, 90 d, personalizado) · legenda das faixas com aviso “referência de volume registrado, não diagnóstico” · toque no músculo → *bottom sheet* com séries ponderadas/semana, frequência, exercícios, evolução de carga, comparação com o período anterior e os botões **Perguntar à IA** e **Sugerir exercícios** (abre o chat com o escopo `muscle`).

**IA:** campo de mensagem com sugestões contextuais; as respostas mostram chips “dados usados” (ferramentas consultadas e período); as propostas aparecem como cartão com diff e os botões Confirmar/Recusar.

## 3. Estados obrigatórios por tela

Carregando (*skeleton*, não um *spinner* em tela cheia), vazio (explica e oferece a ação principal — ex.: “Nenhuma sessão ainda. Criar ficha”), erro (mensagem humana + tentar novamente; erros de validação no próprio campo), sucesso (feedback discreto: *snackbar*/háptico), offline (faixa informativa; a sessão em andamento continua em rascunho). Na sessão (2.9): sem conexão, a série é salva no aparelho e a linha mostra um relógio no lugar do ✓ verde; uma faixa diz quantas alterações estão guardadas, com “Tentar agora”; o envio é automático quando a rede volta (e ao reabrir o app). Finalizar espera a fila esvaziar.

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
- Botões, cards e pílulas encolhem sob o dedo, sempre para 0,97 (`EvoPressable.pressedScale`), e voltam na hora se o dedo arrasta para rolar.
- Avisos de erro abrem e fecham o espaço suavemente; o botão troca texto e indicador com um esmaecimento.
- Tudo é desligado quando o sistema pede redução de movimento. As animações implícitas usam `evoDuration` e `EvoAnimatedSize`, porque `AnimatedSize` e `AnimatedSwitcher` não checam isso sozinhos.

**Toque:** alvo mínimo de 48×48 dp, inclusive nos botões dos diálogos.

**Acessibilidade** (revisão de 2026-10-30, ADR-027):
- **Foco por teclado/D-pad:** contorno preto de 2 px (`EvoFocusRing` e tema dos botões de texto e de ícone). O destaque padrão do Material (10 %) tinha 1,3:1 e não era percebido.
- **Seleção:** pílulas e cartões pintam o fundo com `Ink`, para o efeito de toque aparecer; o marcado tem ícone, não só cor. Os números de "dias por semana" têm a ação no nó de acessibilidade, então o TalkBack os ativa com dois toques.
- **Botões de avançar nunca ficam desabilitados:** com a seção incompleta, mostram o que falta ("Escolha um objetivo principal. Ou toque em Pular."). Um botão apagado não diz o motivo.
- **Formulários:** um envio com erro leva o foco ao primeiro campo inválido; o erro dos termos faz parte da caixa de seleção; o botão em carregamento mantém o nome ("Entrar, carregando").
- **Leitores de tela:** títulos das telas sem barra marcados como cabeçalho; a troca de passo do onboarding é anunciada; o voltar escondido no primeiro passo também sai da árvore do TalkBack.
- **Fonte grande (até 200 %) em 320 dp:** rótulos de botões e pílulas quebram linha; dicas e erros de campo vão até 8 linhas; logo e números de círculo crescem com limite; rodapés fixos rolam quando passam de 40 % da tela. Coberto por `test/app/stress_layout_test.dart`.
- **Saída com alterações não salvas** na edição do perfil pede confirmação ("Descartar alterações?").
- **Textos neutros em gênero** ("Que bom te ver de novo.", "Seu nome ou apelido").

## 5. Teste de usabilidade (Fase 5)

Tarefas com 3–5 participantes: (1) cadastrar-se e definir o objetivo; (2) criar uma ficha com um bi-set; (3) registrar 3 séries, incluindo um drop set; (4) registrar uma caminhada; (5) descobrir no Meu Corpo qual músculo recebeu menos estímulo; (6) perguntar à IA sobre a última sessão. Métricas: conclusão, tempo, erros, SUS.
