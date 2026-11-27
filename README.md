# EvoFit

Plataforma de acompanhamento de atividade física, nutrição e evolução pessoal com IA contextual.

**Projeto de TCC (Portfólio)** · Bacharelado em Engenharia de Software · Católica de Santa Catarina
**Autor:** Vitor Santos · vitor00.santos@catolicasc.edu.br

> “EvoFit” é um nome provisório. O EvoFit não substitui o acompanhamento de profissionais de saúde, Educação Física ou Nutrição.

![Sessão de treino no site do EvoFit (dados fictícios)](docs/img/sessao-de-treino.png)

## Sumário

1. [Contexto e problema](#1-contexto-e-problema)
2. [Justificativa](#2-justificativa)
3. [Objetivos](#3-objetivos)
4. [Escopo](#4-escopo)
5. [Requisitos](#5-requisitos)
6. [Casos de uso](#6-casos-de-uso)
7. [Arquitetura](#7-arquitetura)
8. [Tecnologias](#8-tecnologias)
9. [Segurança e privacidade](#9-segurança-e-privacidade)
10. [Metodologia e pacotes de entrega](#10-metodologia-e-pacotes-de-entrega)
11. [Testes e qualidade](#11-testes-e-qualidade)
12. [Resultados atuais](#12-resultados-atuais)
13. [Como executar](#13-como-executar)
14. [Estrutura do repositório](#14-estrutura-do-repositório)
15. [Documentação](#15-documentação)
16. [Limitações conhecidas](#16-limitações-conhecidas)
17. [Referências](#17-referências)

## 1. Contexto e problema

Quem treina costuma espalhar os registros por vários lugares: um app para a academia, outro para a corrida, uma planilha para a dieta e anotações soltas sobre o peso. Os apps existentes tendem a supor um único perfil, o praticante de musculação focado em hipertrofia. E os assistentes de IA genéricos respondem sem conhecer o histórico real da pessoa.

A Organização Mundial da Saúde recomenda de 150 a 300 minutos semanais de atividade física moderada para adultos (WHO, 2020). Acompanhar a própria evolução de forma simples ajuda a manter essa rotina.

## 2. Justificativa

- **Um só lugar:** reunir musculação, corrida, caminhada, nutrição e medidas corporais, com módulos que o usuário liga conforme o objetivo.
- **Números confiáveis:** todo indicador é calculado pelo backend com regras explícitas e testadas. A IA explica e sugere, sem inventar números.
- **Dados sensíveis tratados com cuidado:** dados de saúde são dados pessoais sensíveis pela LGPD (BRASIL, 2018) e exigem consentimento específico, minimização e controle do titular.

## 3. Objetivos

**Objetivo geral:** desenvolver o EvoFit, uma plataforma (app Android, API e site) de acompanhamento de atividade física, nutrição e evolução pessoal, com uma IA contextual que responde a partir dos dados reais do usuário e só altera fichas ou metas com a confirmação dele.

**Objetivos específicos:**

1. Permitir o registro rápido de treinos de musculação, com técnicas avançadas (drop set, rest-pause, até a falha, aquecimento) e grupos (bi-set, tri-set, supersérie).
2. Registrar corrida, caminhada, ciclismo e natação em um modelo multimodal.
3. Calcular histórico, recordes, tendências e o estímulo por grupo muscular (tela **Meu Corpo**).
4. Oferecer uma IA contextual que consulta os dados por ferramentas tipadas e reconhece quando faltam dados.
5. Garantir privacidade por padrão e isolamento total dos dados entre usuários.

**Personas de referência** (exemplos, não usuários reais): iniciante em caminhada, corredor iniciante, praticante de musculação e perfil híbrido (musculação + corrida + dieta). Detalhes em [VISION](docs/VISION.md).

## 4. Escopo

**Dentro do TCC:**

- Cadastro, login, sessão e perfil com objetivos, modalidades, equipamentos e consentimentos.
- Musculação completa: biblioteca, fichas, sessões, séries, técnicas avançadas, histórico e recordes.
- Corrida e caminhada com registro manual, metas e planos iniciais de 5 km e 10 km; ciclismo e natação básicos.
- Evolução: indicadores, gráficos, comparativos, painel do Início e Meu Corpo em 2D (frente/costas), com uma prova de conceito em 3D.
- IA contextual com propostas de alteração confirmadas pelo usuário.
- Nutrição básica (refeições, macros estimados, metas diárias), peso e medidas.
- Direitos do titular (LGPD): exportação dos dados e exclusão da conta.
- Site institucional.
- Preparação da demonstração: conta de demonstração, testes de integração no emulador e APK de release.

**Fora do TCC (a arquitetura já prevê):** GPS em tempo real, Strava, Health Connect e wearables; o 3D como padrão do Meu Corpo; versão iOS publicada; monetização, multi-idioma e recursos sociais. O que ficou pela metade está em [Limitações conhecidas](#16-limitações-conhecidas).

## 5. Requisitos

### Requisitos funcionais

| ID | Requisito | Situação |
|---|---|---|
| RF01 | Cadastrar-se, entrar, renovar a sessão e sair | ✅ |
| RF02 | Completar o onboarding: objetivo, modalidades, experiência, disponibilidade, equipamentos e limitações | ✅ |
| RF03 | Conceder e revogar consentimentos (termos, dados de saúde, uso de IA) | ✅ |
| RF04 | Criar, editar, concluir e excluir metas | ✅ |
| RF05 | Consultar a biblioteca de exercícios com busca e filtros, e criar exercícios próprios | ✅ |
| RF06 | Montar fichas de treino com ordenação e grupos (bi-set, tri-set, supersérie) | ✅ |
| RF07 | Executar a sessão de treino com séries pré-preenchidas pela última sessão e cronômetro de descanso | ✅ |
| RF08 | Registrar drop set, rest-pause, série até a falha e aquecimento | ✅ |
| RF09 | Consultar o histórico, os recordes e a comparação com a sessão anterior | ✅ |
| RF10 | Continuar a sessão em andamento depois de fechar o app ou ficar sem internet | ✅ |
| RF11 | Registrar corrida, caminhada, ciclismo e natação, com pace e velocidade calculados e FC e elevação opcionais | ✅ |
| RF12 | Seguir planos progressivos de caminhada, 5 km e 10 km, com as sessões marcadas pelas atividades | ✅ |
| RF13 | Visualizar o Meu Corpo 2D com o estímulo por grupo muscular | ✅ |
| RF14 | Ver dashboard, gráficos e comparativos de períodos | ✅ |
| RF15 | Conversar com a IA sobre o próprio histórico e confirmar ou recusar propostas | ✅ (avaliação com os provedores reais incompleta) |
| RF16 | Registrar refeições, metas nutricionais, peso e medidas | ✅ (sem o catálogo da TACO) |
| RF17 | Exportar os dados e excluir a conta (LGPD) | ✅ |

### Requisitos não funcionais

| ID | Requisito |
|---|---|
| RNF01 | **Segurança:** senhas com Argon2id; access token JWT de 15 min e refresh token rotativo com detecção de reutilização; limite de tentativas no login. |
| RNF02 | **Autorização:** nenhum usuário acessa dados de outro, verificado por testes automatizados em todos os endpoints. |
| RNF03 | **Privacidade (LGPD):** consentimento específico para dados de saúde e para a IA; revogar o consentimento apaga os dados de saúde; logs sem dados sensíveis. |
| RNF04 | **Usabilidade:** registrar uma série em até 2 toques, sem trocar de tela. |
| RNF05 | **Acessibilidade:** suporte a TalkBack, foco visível, fonte grande e redução de movimento (WCAG 2.2). |
| RNF06 | **Resiliência:** a sessão de treino continua offline e sincroniza quando a rede volta. |
| RNF07 | **Manutenibilidade:** monólito modular, OpenAPI como contrato e decisões registradas em ADRs. |
| RNF08 | **Qualidade:** testes automatizados e lint no backend, no app e no site. |
| RNF09 | **Reprodutibilidade:** ambiente local com Docker Compose ou PostgreSQL local e versões fixadas. |
| RNF10 | **Honestidade dos dados:** estimativas (como o 1RM) aparecem como estimativa; métricas não registradas não são exibidas. |

## 6. Casos de uso

O usuário se cadastra, configura objetivos e consentimentos, monta fichas e executa a sessão registrando cada série. As técnicas avançadas estendem o registro da série. Ele também registra atividades de resistência e pode seguir um plano progressivo de caminhada, 5 km ou 10 km.

![Casos de uso do EvoFit](docs/img/casos-de-uso.png)

Fluxos detalhados em [UX_FLOWS](docs/UX_FLOWS.md).

## 7. Arquitetura

Um **monólito modular** em FastAPI atende o app e o site. Cada módulo separa `router → service`, e toda consulta do serviço filtra pelo usuário do token, nunca por um id enviado no corpo da requisição. O app e o site nunca falam direto com o provedor de IA: as chaves ficam só no backend.

![Arquitetura do EvoFit](docs/img/arquitetura.png)

Detalhes em [ARCHITECTURE](docs/ARCHITECTURE.md), modelo de dados em [DATA_MODEL](docs/DATA_MODEL.md) e endpoints em [API](docs/API.md).

## 8. Tecnologias

| Parte | Tecnologia |
|---|---|
| App mobile (`apps/mobile`) | Flutter 3.47 · Dart 3.13 · Riverpod · go_router · dio · flutter_secure_storage (alvo: Android) |
| API (`services/api`) | Python 3.14 · FastAPI · Pydantic 2 · SQLAlchemy 2 · Alembic · PostgreSQL 18 |
| Site (`apps/web`) | Next.js 16 · React 19 · TypeScript · Tailwind CSS 4 |
| IA | Camada própria desacoplada do fornecedor, com ferramentas tipadas; adaptadores REST do Groq e do Google Gemini, em ordem configurável, e um modo demonstração por regras sem IA externa (ADR-056 a ADR-058) |
| Testes e qualidade | pytest · Ruff · flutter_test · integration_test · flutter analyze · Vitest · ESLint |
| Infra local | Docker Compose ou PostgreSQL 18 local (`DB_MODE`) |
| Identidade visual | `packages/design-tokens/tokens.json`, gerado para Dart e CSS |

As versões exatas estão fixadas em `pyproject.toml`, `pubspec.yaml` e `package.json` (ADR-019 e ADR-021).

## 9. Segurança e privacidade

- **Autenticação:** Argon2id (BIRYUKOV et al., 2021) e JWT HS256 de 15 min (JONES; BRADLEY; SAKIMURA, 2015), com refresh opaco de 256 bits guardado só como SHA-256.
- **No app:** refresh token no Android Keystore; access token só em memória; backup automático do Android desligado.
- **Autorização:** matriz única de testes ligada ao OpenAPI. Se surgir um endpoint novo sem classificação, a suíte quebra (ADR-038). Segue o OWASP API Security Top 10 (OWASP, 2023).
- **Dados de saúde:** só com o consentimento `health_data`; revogar apaga limitações e metas de peso (ADR-026). A frequência cardíaca das atividades também é tratada como dado de saúde (ADR-040).
- **IA:** as chaves dos provedores ficam só na API; a IA lê os dados por ferramentas que recebem o usuário do token e nunca grava sem a confirmação da pessoa (ADR-050, ADR-053). Consentimento próprio (`ai_processing`) que nomeia as empresas.
- **Direitos do titular:** exportação completa em JSON e exclusão física da conta, com a senha (ADR-063).
- **Segredos:** só em variáveis de ambiente; `.env`, a chave de assinatura do APK e o `key.properties` fora do Git.

Detalhes e pendências jurídicas em [SECURITY_PRIVACY](docs/SECURITY_PRIVACY.md).

## 10. Metodologia e pacotes de entrega

O desenvolvimento é **incremental**: cada fase termina com uma jornada demonstrável, os testes passando e a documentação atualizada. O backlog é priorizado em P0 (indispensável), P1 (importante) e P2 (desejável). As decisões técnicas são registradas como ADRs (NYGARD, 2011) em [DECISIONS](docs/DECISIONS.md) — 69 ao todo. Os commits seguem o padrão de commits convencionais (`feat:`, `test:`, ...).

| Pacote | Conteúdo | Situação |
|---|---|---|
| Fase 0 — Planejamento | Ambiente, viabilidade, riscos, arquitetura, modelo de dados, IA, UX e segurança | ✅ |
| Fase 1 — Fundação técnica | Monorepo, API com `/health`, migrações, app e site com testes e lint, scripts | ✅ |
| Fase 2 — Musculação | Auth, onboarding, metas, biblioteca, fichas, sessão, técnicas, histórico, rascunho offline, testes de autorização | ✅ (aceite cumprido) |
| Fase 3 — Evolução e modalidades | Atividades multimodais, pace, planos progressivos, motor de análise, Meu Corpo 2D, gráficos, dashboard, prova do 3D | ✅ |
| Fase 4 — IA contextual | Camada de LLM, ferramentas, orquestrador, provedores reais e modo demonstração, chat, propostas com confirmação, avaliação | ✅ (4.7 em parte) |
| Fase 5 — Nutrição e refinamento | Alimentos e refeições, metas nutricionais, peso e medidas, site completo, LGPD, protocolo de usabilidade | ✅ (5.1 sem a TACO; 5.7 sem as sessões) |
| Fase 6 — Demonstração | Conta de demonstração, testes de integração, APK de release, correções do piloto, documentação final | ✅ |

Backlog completo e critérios de aceite em [ROADMAP](docs/ROADMAP.md).

## 11. Testes e qualidade

| Parte | Ferramentas | Testes |
|---|---|---|
| API | pytest (com PostgreSQL de teste) · Ruff (lint e formatação) | 782 (+1 que só roda quando pedido: a avaliação com o provedor real) |
| App | flutter_test (widget e fluxo) · flutter analyze | 285 |
| Site | Vitest · ESLint · TypeScript | 13 |
| Integração | integration_test: o app no emulador com a API real | 2 fluxos (a jornada completa e a conta de demonstração) |

São **1.080 testes automatizados** de API, app e site, todos passando em 2026-11-26; os 2 testes de integração passaram no emulador na etapa 6.4. A autorização entre usuários é testada numa matriz ligada ao OpenAPI: uma rota nova sem classificação quebra a suíte (ADR-038). Um único script roda as verificações de API, app e site; outro, os testes de integração:

```powershell
.\scripts\test-all.ps1                 # tudo
.\scripts\test-all.ps1 -Only api,web   # só algumas partes
.\scripts\test-e2e.ps1                 # app no emulador + API real (AI_PROVIDER=demo)
```

Não há pipeline de integração contínua: os scripts rodam na máquina (ver [Limitações](#16-limitações-conhecidas)).

## 12. Resultados atuais

As seis fases estão concluídas, com três etapas entregues em parte (ver [Limitações conhecidas](#16-limitações-conhecidas)). Os critérios de aceite das fases foram executados no emulador Android com a API real e contas novas:

- **Musculação (Fase 2):** um usuário novo cria uma ficha com bi-set e drop set, executa a sessão, fecha e reabre o app no meio do treino, finaliza e vê o histórico e os recordes. A biblioteca tem 71 exercícios, 67 com fotos (ADR-029, ADR-030). O treino continua sem internet e sincroniza depois (ADR-037).
- **Evolução (Fase 3):** corrida, caminhada, ciclismo e natação, com pace calculado (5 km em 30 min = 6:00/km); planos de caminhada, 5 km e 10 km; tela Evolução, gráficos e comparativos; painel do Início pelo objetivo; **Meu Corpo** 2D com as cores certas para 7 e 30 dias, e o 3D como prova de conceito.
- **IA (Fase 4):** o Assistente responde a partir dos registros (“O que fiz na minha última sessão?”), diz “ainda não há registros” para quem não tem dados e só altera uma ficha ou cria uma meta depois do toque em Confirmar. Funciona com o Groq e o Gemini ou, sem IA externa, no modo demonstração, que passa nas 21 perguntas da avaliação automática.
- **Nutrição e refinamento (Fase 5):** refeições, metas diárias com limites de segurança, peso e medidas com tendência, o site institucional (Lighthouse 100 em acessibilidade, boas práticas e SEO), exportação dos dados e exclusão da conta.
- **Demonstração (Fase 6):** conta de demonstração com 8 semanas de dados terminando no dia (`python -m app.demo_seed`), testes de integração no emulador, APK de release assinado e as correções do piloto de usabilidade.

## 13. Como executar

Pré-requisitos: Git, Python 3.14, Node.js 24, Flutter 3.47 com Android SDK e emulador, e Docker Desktop ou PostgreSQL 18 local. Passo a passo em [SETUP](docs/SETUP.md).

```powershell
Copy-Item .env.example .env
.\scripts\dev-api.ps1                     # banco + migrações + API em http://localhost:8000/docs
cd apps/mobile; flutter run               # com o emulador aberto
cd apps/web; npm install; npm run dev     # http://localhost:3000
```

Roteiro do dia a dia (depois de ligar o PC), a conta de demonstração, os testes de integração e o APK de release em [COMO_INICIAR](docs/COMO_INICIAR.md). Para o assistente responder sem IA externa, use `AI_PROVIDER=demo` no `.env`.

## 14. Estrutura do repositório

```
apps/mobile/            app Flutter (Android)
apps/web/               site institucional (Next.js)
services/api/           API FastAPI + Alembic + testes
packages/design-tokens/ identidade visual compartilhada (tokens.json)
scripts/                dev-api, test-all, test-e2e, make-keystore, build-apk, generate_tokens, usability_report
tools/body3d/           gerador do manequim 3D (GLB) do Meu Corpo
docs/                   planejamento, decisões, avaliação, usabilidade e diagramas (docs/img)
```

## 15. Documentação

| Documento | Conteúdo |
|---|---|
| [ASSESSMENT](docs/ASSESSMENT.md) | Ambiente inspecionado, viabilidade, riscos, dependências externas |
| [VISION](docs/VISION.md) | Problema, princípios, personas, escopo e critérios de sucesso |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Monólito modular, estrutura de pastas, app, site, integrações |
| [DATA_MODEL](docs/DATA_MODEL.md) | Entidades, técnicas avançadas, metodologia de estímulo muscular |
| [API](docs/API.md) | Convenções e mapa de endpoints por fase |
| [AI_DESIGN](docs/AI_DESIGN.md) | Ferramentas, guardrails, confirmação de alterações, testes, custos |
| [UX_FLOWS](docs/UX_FLOWS.md) | Navegação, fluxos críticos, identidade visual |
| [SECURITY_PRIVACY](docs/SECURITY_PRIVACY.md) | Autorização, segredos, LGPD, retenção, pendências jurídicas |
| [DECISIONS](docs/DECISIONS.md) | Registro de decisões (ADRs) |
| [AVALIACAO_IA](docs/AVALIACAO_IA.md) | Avaliação do assistente: perguntas, checagens e resultados |
| [USABILIDADE](docs/USABILIDADE.md) | Protocolo dos testes de usabilidade e o piloto |
| [LIMITACOES](docs/LIMITACOES.md) | Limitações conhecidas da versão entregue |
| [ROADMAP](docs/ROADMAP.md) | Fases, backlog priorizado e critérios de aceite |
| [SETUP](docs/SETUP.md) | Instalação e execução no Windows |
| [COMO_INICIAR](docs/COMO_INICIAR.md) | Como iniciar tudo depois de ligar o PC |

## 16. Limitações conhecidas

A lista completa, com o efeito de cada item e a decisão correspondente, está em [LIMITACOES](docs/LIMITACOES.md). As principais:

- **Entregue em parte:** a avaliação da IA com os provedores reais parou nas cotas dos planos gratuitos (4.7); o catálogo de alimentos da TACO não foi importado (5.1); as sessões de usabilidade com 3 a 5 pessoas não foram feitas (5.7).
- **Operação:** sem servidor público nem HTTPS (a API roda no computador; o APK de demonstração usa HTTP para o emulador); sem integração contínua; limite de login em memória; prazos de retenção não automatizados.
- **Validação:** conteúdo de exercícios, planos e metodologia do Meu Corpo sem revisão de profissionais; verificado no emulador Android (sem registro de teste em aparelho físico) e não testado no iOS; pendências jurídicas antes de um lançamento real.

## 17. Referências

- BIRYUKOV, A. et al. **RFC 9106: Argon2 memory-hard function for password hashing and proof-of-work applications**. IETF, 2021.
- BRASIL. **Lei nº 13.709, de 14 de agosto de 2018**. Lei Geral de Proteção de Dados Pessoais (LGPD). Brasília, DF, 2018.
- JONES, M.; BRADLEY, J.; SAKIMURA, N. **RFC 7519: JSON Web Token (JWT)**. IETF, 2015.
- NYGARD, Michael. **Documenting architecture decisions**. Cognitect, 2011.
- OWASP FOUNDATION. **OWASP API Security Top 10**: 2023. 2023.
- W3C. **Web Content Accessibility Guidelines (WCAG) 2.2**. 2023.
- WORLD HEALTH ORGANIZATION. **WHO guidelines on physical activity and sedentary behaviour**. Geneva: WHO, 2020.
