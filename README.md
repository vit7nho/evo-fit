# EvoFit

Plataforma de acompanhamento de atividade física, nutrição e evolução pessoal com IA contextual — projeto de TCC de Engenharia de Software.

**Estado atual:** Fase 2 em andamento — autenticação (2.1) e onboarding/perfil com consentimentos (2.2) concluídos na API e no app Android (ver [ROADMAP](docs/ROADMAP.md)). Próxima: 2.3 (metas).

## Início rápido (Windows)

```powershell
Copy-Item .env.example .env
.\scripts\dev-api.ps1                     # banco + migrações + API em http://localhost:8000/docs
cd apps/mobile; flutter run               # com o emulador aberto
cd apps/web; npm install; npm run dev     # http://localhost:3000
.\scripts\test-all.ps1                    # todas as verificações
```

Roteiro do dia a dia (depois de ligar o PC) em [docs/COMO_INICIAR.md](docs/COMO_INICIAR.md). Detalhes e solução de problemas em [docs/SETUP.md](docs/SETUP.md).

## Estrutura

```
apps/mobile/            app Flutter (Android)
apps/web/               site institucional (Next.js)
services/api/           API FastAPI + Alembic + testes
packages/design-tokens/ identidade visual compartilhada (tokens.json)
scripts/                dev-api, test-all, generate_tokens
docs/                   planejamento e decisões
```

## Stack planejada

| Parte | Tecnologia |
|---|---|
| App mobile (`apps/mobile`) | Flutter 3.47 · Dart 3.13 · Riverpod · go_router · dio — alvo Android |
| API (`services/api`) | Python 3.14 · FastAPI · Pydantic 2 · SQLAlchemy 2 · Alembic · PostgreSQL 18 · pytest |
| Site (`apps/web`) | Next.js 16 · React 19 · TypeScript · Tailwind CSS 4 |
| IA | Camada própria desacoplada do fornecedor, com ferramentas tipadas (provedor a definir) |
| Infra local | PostgreSQL 18 local ou Docker Compose (`DB_MODE`) |

As versões exatas estão fixadas nos manifestos de cada app (`pyproject.toml`, `pubspec.yaml`, `package.json`); as decisões de versão estão em [docs/DECISIONS.md](docs/DECISIONS.md) (ADR-019 e ADR-021).

## Documentação

| Documento | Conteúdo |
|---|---|
| [ASSESSMENT](docs/ASSESSMENT.md) | Ambiente inspecionado, viabilidade, riscos, dependências externas |
| [VISION](docs/VISION.md) | Problema, princípios, escopo do TCC e critérios de sucesso |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Monólito modular, estrutura de pastas, app, site, multimodalidade, integrações |
| [DATA_MODEL](docs/DATA_MODEL.md) | Entidades, técnicas avançadas, metodologia de estímulo muscular |
| [API](docs/API.md) | Convenções e mapa de endpoints por fase |
| [AI_DESIGN](docs/AI_DESIGN.md) | Ferramentas, guardrails, confirmação de alterações, testes, custos |
| [UX_FLOWS](docs/UX_FLOWS.md) | Navegação, fluxos críticos, tokens visuais |
| [SECURITY_PRIVACY](docs/SECURITY_PRIVACY.md) | Autorização, segredos, LGPD, retenção, pendências jurídicas |
| [DECISIONS](docs/DECISIONS.md) | Registro de decisões (ADRs) |
| [ROADMAP](docs/ROADMAP.md) | Fases, backlog priorizado e critérios de aceite |
| [SETUP](docs/SETUP.md) | Instalação e execução no Windows |
| [COMO_INICIAR](docs/COMO_INICIAR.md) | Como iniciar tudo depois de ligar o PC |

## Aviso

O EvoFit não substitui o acompanhamento de profissionais de saúde, Educação Física ou Nutrição.
