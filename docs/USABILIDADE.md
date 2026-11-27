# Testes de usabilidade (etapa 5.7)

Protocolo para testar o EvoFit com **3 a 5 pessoas**, uma por vez, com moderação presencial. Tudo o que a sessão precisa está aqui: preparação, falas do moderador, tarefas, questionários, termo e como registrar e resumir os resultados.

> Este é um teste de usabilidade de um projeto acadêmico, não uma pesquisa clínica: ninguém informa dados de saúde reais e nada identifica a pessoa nos resultados. Mesmo assim, confirme com a orientadora se a coleta precisa de algum registro no Comitê de Ética da instituição.

## 1. Objetivo

Ver se uma pessoa que nunca usou o app consegue fazer, sozinha, o que o EvoFit promete: criar a conta, montar e registrar um treino de musculação, registrar uma atividade, entender o Meu Corpo, registrar o peso e perguntar ao assistente. Medir **conclusão, tempo, erros, facilidade percebida (SEQ)** e a **nota SUS**, e listar os problemas para corrigir.

## 2. Participantes

- **3 a 5 pessoas**, maiores de 18 anos, que não participaram do desenvolvimento.
- Variar o perfil: pelo menos uma que treina musculação, uma iniciante e uma que caminha ou corre.
- Cada pessoa recebe um código (**P1, P2…**) na ordem das sessões. O nome não aparece em nenhuma planilha, anotação ou relatório.

## 3. Ambiente

- **API no notebook em modo demonstração** (`AI_PROVIDER=demo` no `.env`): o assistente responde por regras, no próprio servidor, e nada é enviado a empresas de IA.
- **Aparelho:** o emulador `EvoFit_Aceite` no notebook ou um celular Android com o APK de debug, ligado à API pela rede local. O emulador precisa do fuso de Brasília (veja o checklist); com o fuso em UTC, a hora do formulário e a da lista ficam diferentes.
- **Conta:** o próprio participante cria na tarefa 1, com o e-mail e a senha de um cartão: `p1.sessao@evofit.local` (troque o número) e a senha `cavalo bateria grampo`. Peso e demais dados podem ser inventados; o termo pede isso.
- **Duração:** 30 a 40 minutos por sessão.
- **Não gravar** tela nem áudio. As anotações vão na ficha de observação (seção 9), só com o código.

### Checklist antes de cada sessão

1. API rodando e `GET /health` respondendo; `AI_PROVIDER=demo`.
2. Fuso do emulador: `adb shell settings put global auto_time_zone 0` e `adb shell service call alarm 3 s16 America/Sao_Paulo`; `adb shell date` deve mostrar `-03`.
3. App sem dados de sessões anteriores: `adb shell pm clear br.tcc.evofit.evofit` e abrir o app na tela de login.
4. Cartão com o e-mail e a senha do participante; ficha de observação, cronômetro, termo e questionário SUS impressos ou abertos em outro aparelho.

## 4. Roteiro do moderador

**Abertura (≈ 3 min).** “Obrigado por vir. Vou te pedir para fazer algumas tarefas no EvoFit, um app de treino. Quem está sendo testado é o app, não você: se algo ficar difícil, é exatamente isso que eu preciso descobrir. Pense em voz alta — diga o que está procurando, o que espera que aconteça e o que te surpreendeu. Eu não vou poder ajudar durante as tarefas, mas no fim respondo tudo. Pode parar a qualquer momento.” Ler e assinar o termo (seção 8).

**Durante as tarefas.**
- Ler a tarefa em voz alta e entregar o cartão com ela. Iniciar o cronômetro quando a pessoa tocar na tela.
- Não indicar botões nem confirmar se está certo. Perguntas neutras: “O que você esperava encontrar aqui?”, “O que você faria agora?”.
- **Ajuda:** só se a pessoa pedir duas vezes ou ficar travada por **3 minutos**. Dê a menor dica possível e marque “ajuda”.
- **Limite:** 5 minutos por tarefa. Passou disso, encerre a tarefa como “não concluiu” e leve o app ao ponto de partida da próxima.
- **Erro** = uma ação que afasta da meta e precisa ser desfeita (tela errada, campo errado, salvar sem o que pedia). Anotar cada um.
- Ao terminar cada tarefa, a pergunta **SEQ**: “De 1 a 7, quão fácil foi esta tarefa? 1 é muito difícil, 7 é muito fácil.”

**Fechamento (≈ 8 min).** Questionário SUS (seção 7), depois: “O que foi mais fácil?”, “O que foi mais difícil ou confuso?”, “Usaria um app assim? Por quê?”. Por fim, a pessoa **exclui a conta** em Perfil › Seus dados › Excluir minha conta, com a senha do cartão — assim nada fica no servidor, e a exclusão também é testada.

## 5. Tarefas

As tarefas são cenários, sem o nome dos botões. A ordem é fixa porque cada uma usa o que a anterior criou.

| # | Tarefa (lida para o participante) | Concluiu quando… |
|---|---|---|
| 1 | “Você acabou de baixar o EvoFit. Crie sua conta com o e-mail e a senha do cartão e conte ao app que o seu objetivo é ganhar massa muscular.” | chega ao Início com “Seu foco: Ganhar massa muscular.” |
| 2 | “Monte um treino chamado Treino A com dois exercícios de peito — supino inclinado com halteres e crucifixo com halteres — feitos um atrás do outro, sem descanso entre eles (bi-set).” | a ficha está salva, com os dois exercícios no mesmo bi-set |
| 3 | “Comece esse treino agora. No supino, registre duas séries de 20 kg com 8 repetições e, logo em seguida, uma série com 14 kg e 6 repetições sem descanso (drop set). Depois, finalize o treino.” | o resumo do treino mostra 20 kg × 8 duas vezes e o drop set de 14 kg × 6 |
| 4 | “Agora há pouco você caminhou 2,5 km em 30 minutos. Registre essa caminhada.” | a caminhada aparece em Atividades com 30:00 e 2,5 km |
| 5 | “Descubra um músculo que você não treinou nos últimos 30 dias.” | diz um músculo da lista “Sem nenhuma série em 30 dias” do Meu Corpo |
| 6 | “Você se pesou hoje de manhã. Registre esse peso (pode inventar um número).” | o peso aparece em Peso e medidas (passa pela autorização de dados de saúde) |
| 7 | “Pergunte ao assistente o que você fez no seu último treino.” | a resposta sobre o Treino A aparece na conversa (passa pela autorização das análises com IA) |

## 6. O que medir

| Medida | Como | Onde anotar |
|---|---|---|
| Conclusão | `sim`, `ajuda` ou `nao` | `tarefas.csv`, coluna `concluiu` |
| Tempo | segundos, do primeiro toque até o critério da tarefa | `tempo_s` |
| Erros | número de ações desfeitas (seção 4) | `erros` |
| Facilidade | SEQ, de 1 (muito difícil) a 7 (muito fácil) | `seq` |
| Satisfação | SUS, 10 respostas de 1 a 5 | `sus.csv` |
| Problemas | o que a pessoa disse ou fez, em poucas palavras, sem nome | ficha de observação; resumo na coluna `observacao` |

**Metas de referência:** cada tarefa concluída sem ajuda por pelo menos 4 de 5 pessoas (ou 2 de 3); SEQ médio acima de 5; SUS médio acima de 68, a média de referência da escala.

## 7. Questionário SUS

Para cada frase: 1 = discordo totalmente, 5 = concordo totalmente. Leia as frases na ordem; não explique o que querem dizer.

1. Eu acho que gostaria de usar este app com frequência.
2. Eu achei o app desnecessariamente complexo.
3. Eu achei o app fácil de usar.
4. Eu acho que precisaria da ajuda de uma pessoa com conhecimentos técnicos para usar o app.
5. Eu achei que as várias funções do app estão bem integradas.
6. Eu achei que o app tem muita inconsistência.
7. Eu imagino que a maioria das pessoas aprenderia a usar este app rapidamente.
8. Eu achei o app muito complicado de usar.
9. Eu me senti confiante ao usar o app.
10. Eu precisei aprender várias coisas antes de conseguir usar o app.

A nota vai de 0 a 100: itens ímpares valem resposta − 1, pares valem 5 − resposta, e a soma é multiplicada por 2,5 (Brooke, 1996). O script da seção 10 faz a conta. Se o relatório do TCC pedir uma versão validada em português, use a que a orientadora indicar; a ordem e a escala são as mesmas.

## 8. Termo de participação

> **Teste de usabilidade do EvoFit — Trabalho de Conclusão de Curso**
>
> Você está convidado(a) a testar o EvoFit, um aplicativo de treino desenvolvido como Trabalho de Conclusão de Curso. Vou pedir que você faça algumas tarefas no app, pensando em voz alta, e responda a um questionário curto. Leva de 30 a 40 minutos.
>
> - **O que é anotado:** se você concluiu cada tarefa, o tempo, as dificuldades e as suas respostas ao questionário, identificados só por um código (como P1). Seu nome não aparece em nenhum resultado. Não há gravação de tela nem de áudio.
> - **Dados no app:** use o e-mail e a senha do cartão. Não informe dados reais de saúde; o peso e os treinos podem ser inventados. No fim, você mesmo(a) exclui a conta, e os dados saem do servidor.
> - **O assistente** funciona em modo demonstração: as respostas são montadas no próprio servidor e nada é enviado a empresas de IA.
> - **Participação voluntária:** você pode parar a qualquer momento, sem precisar explicar.
> - **Uso dos resultados:** os resultados anônimos entram no relatório do TCC e na apresentação do projeto.
>
> Declaro que li e concordo em participar.
>
> Data: ____/____/______  Assinatura: ______________________________

O termo assinado fica com o moderador e **não vai para o repositório**.

## 9. Ficha de observação

Uma por participante; preenchida à mão durante a sessão.

```
Participante: P__   Data: __/__/____   Aparelho: emulador / celular   Perfil: treina / iniciante / caminha-corre

Tarefa | Início | Fim | Concluiu (sim/ajuda/não) | Erros | SEQ | O que aconteceu
1      |        |     |                          |       |     |
2      |        |     |                          |       |     |
3      |        |     |                          |       |     |
4      |        |     |                          |       |     |
5      |        |     |                          |       |     |
6      |        |     |                          |       |     |
7      |        |     |                          |       |     |

SUS: q1 __ q2 __ q3 __ q4 __ q5 __ q6 __ q7 __ q8 __ q9 __ q10 __
Mais fácil:
Mais difícil:
Usaria? Por quê:
Conta excluída no fim: sim / não
```

## 10. Registro e análise

1. Depois de cada sessão, passe a ficha para as planilhas em [`docs/usabilidade/`](usabilidade/):
   - `tarefas.csv`, uma linha por tarefa: `participante,tarefa,concluiu,tempo_s,erros,seq,observacao` (ex.: `P1,3,ajuda,210,2,4,procurou o drop set no menu do exercício`);
   - `sus.csv`, uma linha por pessoa: `participante,q1,…,q10`.
   Só códigos e observações curtas; nada que identifique a pessoa.
2. Gere o resumo: `python scripts/usability_report.py --out docs/usabilidade/relatorio.md`. O script confere as planilhas (código, tarefa de 1 a 7, valores nos intervalos, sem linha repetida) e aponta a linha com problema. O texto da coluna `observacao` não vai para o resumo.
3. Liste os problemas encontrados com a gravidade de Nielsen (0 = não é problema … 4 = impede a tarefa), quantas pessoas tiveram cada um e a correção proposta. Corrija primeiro os de gravidade 3 e 4.
4. Registre o resultado e as correções num ADR e no relatório do TCC. Com 3 a 5 pessoas, os números são indicativos: o valor do teste está nos problemas que aparecem.

## 11. Piloto (26/11/2026)

Antes das sessões, o desenvolvedor fez as 7 tarefas no emulador, com a API real em modo demonstração e uma conta descartável (excluída depois). O piloto **não conta como participante**; serviu para conferir o roteiro.

| Achado | O que foi feito |
|---|---|
| Em **Registrar medida**, “Salvar medida” ficava no fim de uma lista de 9 campos; quem só registra o peso precisava rolar pelas medidas vazias, e nos outros formulários o botão fica fixo no rodapé. | **Corrigido:** o botão ficou fixo no rodapé (teste novo garante que ele não está dentro da lista). |
| O leitor de tela lia “1 dias por semana” no cadastro. | **Corrigido:** “1 dia por semana” (teste novo). |
| A tarefa original “qual músculo recebeu menos estímulo” tem várias respostas certas quando a conta tem um treino só. | **Roteiro ajustado:** “um músculo que você não treinou nos últimos 30 dias”. |
| Ao virar drop set, a linha perde a sugestão de repetições; tocar no ✓ sem digitar mostra “Informe as repetições”. A mensagem é clara. | **Corrigido na 6.4:** o drop sugere as repetições da série de cima; um toque no ✓ salva (ADR-068). |
| Com o drop set, o contador “Séries” do treino mostra 2 (o drop set continua a série anterior); quem espera 3 pode estranhar. | **Corrigido na 6.4:** o contador mostra “2 + 1 drop” (a contagem de séries continua a mesma) (ADR-068). |
| Com o emulador em UTC, a hora no formulário e na lista ficavam diferentes. | **Checklist:** acertar o fuso antes da sessão. |

O piloto, feito por comandos e por quem conhece o app, levou cerca de 12 minutos; uma pessoa nova deve levar de 20 a 30.

## 12. Resultados

Ainda não houve sessões. Quando houver, o resumo fica em `docs/usabilidade/relatorio.md` e os problemas e as correções num ADR próprio.
