# Visão do produto — EvoFit

> “EvoFit” é um nome provisório e configurável (`APP_NAME` no backend, constantes de marca no app e no site). Nenhum domínio, registro de marca ou identidade legal foi criado.

## Problema

Quem treina costuma espalhar os dados por vários lugares: um app para a academia, outro para corrida, uma planilha para a dieta e anotações soltas sobre o peso. Os apps existentes também tendem a supor um perfil único — o praticante de academia focado em hipertrofia. E os assistentes de IA genéricos respondem sem conhecer o histórico real da pessoa.

## Proposta

Uma plataforma única de acompanhamento de **atividade física, nutrição e evolução pessoal**, com uma **IA contextual** que responde a partir dos dados reais do usuário, calculados pelo backend.

## Princípios

1. **Adaptação ao usuário, não o contrário.** Musculação, corrida, caminhada, ciclismo, natação e nutrição são módulos opcionais. A experiência se ajusta ao objetivo, à experiência, à disponibilidade e às limitações informadas.
2. **Números determinísticos, interpretação por IA.** Todo indicador é calculado pelo backend com regras explícitas e testadas. A IA explica e sugere, sem inventar.
3. **Honestidade dos dados.** Não exibir métricas que não foram registradas. Não apresentar estimativas como medidas exatas. Não apresentar cores do mapa muscular como diagnóstico.
4. **Registro rápido.** Registrar uma série deve levar segundos e não exigir troca de tela.
5. **Privacidade por padrão.** Coletar só o necessário; dados de saúde com proteção reforçada (LGPD).
6. **Usuário no controle.** Qualquer alteração sugerida pela IA em fichas, metas ou registros exige confirmação explícita.

## Personas (exemplos de referência, não usuários reais)

| Persona | Objetivo | Módulos principais |
|---|---|---|
| Iniciante em caminhada | Criar uma rotina de 3×/semana | Atividades, Metas, IA |
| Corredor iniciante | Completar os primeiros 5 km | Corrida, planos progressivos, IA |
| Praticante de musculação | Hipertrofia, controle de cargas | Treino, Evolução/Meu Corpo, IA |
| Perfil híbrido | Musculação + corrida + dieta | Todos |

## Escopo do TCC (o que entra)

- Cadastro, login, sessão e perfil com objetivos e preferências.
- Musculação completa: biblioteca, fichas, sessões, séries, técnicas avançadas, histórico, recordes.
- Corrida e caminhada com registro manual, histórico, metas e planos iniciais de 5 km/10 km.
- Ciclismo e natação com registro manual básico (o modelo multimodal já as suporta).
- Evolução: indicadores, gráficos, comparativos e **Meu Corpo em 2D** (frente/costas) com cálculo de estímulo por grupo muscular.
- IA contextual com ferramentas tipadas, análise específica e global, e propostas de alteração com confirmação.
- Nutrição básica: refeições, alimentos, macros estimados, metas diárias; peso e medidas corporais.
- Site institucional.

## Fora do escopo do TCC (preparado na arquitetura)

- GPS em tempo real, integração com Strava, Health Connect e wearables.
- Modelo anatômico 3D com rotação de 360° (investigado; opcional se houver tempo — ver `ASSESSMENT.md` §6).
- Versão iOS (o código Flutter fica pronto para ela, mas não será testado/publicado).
- Monetização, multi-idioma, social/feeds.

## Critérios de sucesso do TCC

1. Um usuário novo consegue se cadastrar, definir objetivos e registrar uma sessão de musculação **e** uma corrida no Android, com os dados persistidos no PostgreSQL.
2. A tela Meu Corpo reflete, com cores calculadas, as séries registradas no período escolhido, e a metodologia está documentada e testada.
3. A IA responde perguntas sobre o histórico do usuário usando somente dados obtidos por ferramentas, e reconhece quando faltam dados.
4. Nenhum usuário acessa dados de outro (testes de autorização automatizados).
5. Testes automatizados passando no backend, no app e no site; ambiente reproduzível com Docker Compose.
