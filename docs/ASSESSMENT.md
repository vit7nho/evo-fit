# Avaliação inicial — Ambiente, viabilidade e riscos (Fase 0)

> Data da inspeção: 2026-10-28 · Máquina: Windows 11 Pro (26H2) · Shells: PowerShell 5.1 e Git Bash

## 1. Estado do repositório

| Item | Situação |
|---|---|
| `Documents/desck/` | **Não** era um repositório Git. Continha apenas `flutter/`. |
| `Documents/desck/flutter/` | Clone do **Flutter SDK** (canal `stable`, 3.47.8, Dart 3.13.7). É o Flutter que está no `PATH`. **Não é código do projeto — não deve ser modificado.** |
| `Documents/desck/evofit/` | Criado nesta fase. Repositório Git novo (branch `main`), ainda sem commits. Contém somente documentação. |

Decisão: o monorepositório fica em `desck/evofit/`, ao lado do SDK, para que o SDK nunca seja versionado nem alterado por comandos do projeto (ver ADR-001 em `DECISIONS.md`).

## 2. Ferramentas instaladas

| Ferramenta | Versão encontrada | Situação |
|---|---|---|
| Git | 2.54.0 | OK |
| Python | 3.14.0 (único interpretador) | OK — usar `py -3.14` ou `python` |
| pip | incluído no Python 3.14 | OK |
| uv / Poetry | — | Ausentes. Não são necessários (usaremos `venv` + `pip` + `pyproject.toml`). |
| Node.js / npm | 24.18.0 / 12.0.2 | OK |
| pnpm / yarn | — | Ausentes. Não são necessários (usaremos npm). |
| Docker / Compose | 29.9.2 / v5.6.1 | Instalados, mas **o daemon não estava em execução** (Docker Desktop fechado). |
| PostgreSQL (`psql`) | — | Ausente na inspeção. **Fase 1:** instalado o PostgreSQL 18 local (porta 5433), usado no lugar do Docker (ADR-021). |
| Flutter / Dart | 3.47.8 / 3.13.7 | OK (`flutter doctor`: Flutter ✔) |
| Android Studio | instalado | OK (inclui JDK em `Android Studio/jbr`) |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` — platform `android-37.0`, build-tools 36.0.0, emulator 37.2 | **Parcial**: falta `cmdline-tools`; licenças não aceitas. |
| AVD | `Medium_Phone_API_35` | Existe, mas não há pasta `system-images` — a imagem do sistema provavelmente precisa ser (re)baixada. |
| Java no PATH | 1.8 (Oracle) | Antigo; Flutter usa o JDK do Android Studio, então não bloqueia. |
| Chrome / Edge | 156 | OK (útil para testar o site e, opcionalmente, o app Flutter na web). |
| Visual Studio (C++) | — | Ausente. Só necessário para app desktop Windows — **fora do escopo**. |

### Pendências de ambiente (ação do usuário, antes ou durante a Fase 1)

1. **Abrir o Docker Desktop** (necessário para PostgreSQL e testes de integração do backend).
2. **Android Studio → SDK Manager → SDK Tools → “Android SDK Command-line Tools (latest)”**.
3. Rodar `flutter doctor --android-licenses` e aceitar as licenças (ação sua: é aceite de termos).
4. **Device Manager**: verificar o AVD `Medium_Phone_API_35`; se não iniciar, baixar a imagem do sistema (recomendado: API 35 ou 36, x86_64, Google APIs).

Nada disso foi executado por mim: envolvem aceite de licenças e downloads grandes.

**Atualização 2026-10-28:** pendências resolvidas pelo usuário e verificadas — Docker Engine 29.9.2 em execução; `flutter doctor` com Android toolchain ✔; AVD `Medium_Phone_API_35` (Android 15, x86_64) inicializa e é reconhecido pelo Flutter como `emulator-5554`. Observação: existe uma segunda pasta de SDK em `C:\Android\Sdk` que não é usada pelo projeto.

## 3. Versões candidatas (consultadas em 2026-10-28)

Consultadas em PyPI, npm e pub.dev. Serão fixadas no `pyproject.toml`, `package.json` e `pubspec.yaml` durante a Fase 1, após a instalação e os testes confirmarem a compatibilidade.

**Backend:** FastAPI 0.162 · Pydantic 2.14 · pydantic-settings 2.16 · SQLAlchemy 2.1 · Alembic 1.20 · psycopg 3.3 · Uvicorn 0.54 · argon2-cffi 25.1 · PyJWT 2.15 · httpx 0.28 · pytest 9.2 · Ruff 0.17. Imagem Docker: `python:3.14-slim` (mesma versão do ambiente local). Banco: PostgreSQL 17 (imagem oficial) — **atualizado para 18 na Fase 1 (ADR-021)**.

**Mobile:** flutter_riverpod 3.4 · go_router 18.1 · dio 5.11 · flutter_secure_storage 11.2 · fl_chart 1.3 · flutter_svg 2.3. Todos declaram compatibilidade com Dart 3.13 / Flutter 3.47.

**Web:** Next.js 16.4 · React 19.3 · Tailwind CSS 4.3 · Motion 14.7 · ESLint 10 · Vitest 5.
⚠ O npm já aponta TypeScript **7.0** (reescrita nativa). Se o Next 16 ainda não suportar oficialmente o TS 7 no momento da instalação, fixaremos a última 5.x/6.x suportada. Verificação na Fase 1.

## 4. Viabilidade técnica

| Área | Viabilidade para o TCC | Observações |
|---|---|---|
| Backend FastAPI + PostgreSQL | **Alta** | Stack madura, bem documentada, ótima para testes. |
| App Flutter Android | **Alta** | SDK pronto; faltam apenas ajustes no Android SDK. |
| Musculação com técnicas avançadas | **Alta**, complexidade média | O desafio está na modelagem (resolvido em `DATA_MODEL.md`) e na UX de registro rápido. |
| Corrida/caminhada (registro manual) | **Alta** | GPS em tempo real foi adiado de propósito. |
| Motor de indicadores | **Alta** | É lógica determinística e muito testável — ponto forte para a banca. |
| Meu Corpo em 2D (frente/costas) | **Alta** | SVG próprio com IDs estáveis por músculo. |
| Meu Corpo em 3D com 360° | **Média/baixa** no prazo | Depende de um modelo GLB anatômico com malhas separadas e licença compatível. Ver seção 6. |
| IA contextual com ferramentas | **Média/alta** | Tecnicamente viável; tem custo por uso e precisa de testes cuidadosos. Ver `AI_DESIGN.md`. |
| Nutrição básica | **Alta** | O ponto crítico é ter uma base de alimentos com licença clara. |
| Site institucional | **Alta** | Independente do resto; pode ser feito em paralelo. |
| Integrações (Strava, Health Connect) | Fora do escopo do TCC | Arquitetura preparada; integrações apenas documentadas. |

**Conclusão:** o escopo das Fases 1–6 é viável para um TCC, **desde que** o 3D seja tratado como evolução opcional e a IA comece com um conjunto pequeno de ferramentas bem testadas.

## 5. Principais riscos

| # | Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|---|
| R1 | Escopo grande demais para o prazo do TCC | Alta | Alto | Fases incrementais; cada fase entrega uma jornada demonstrável. Nutrição e 3D ficam no fim. |
| R2 | Modelo 3D anatômico indisponível ou com licença incompatível | Alta | Médio | Primeira versão em 2D com SVG; um renderer substituível (ADR-010). |
| R3 | Custo, latência e indisponibilidade do provedor de IA | Média | Médio | Camada desacoplada, limite diário por usuário, provedor falso para testes e demonstração offline. |
| R4 | IA inventando dados ou dando recomendações perigosas | Média | Alto | Os números vêm só das ferramentas; prompt de segurança versionado; validação das saídas; testes de consistência. |
| R5 | Dados de saúde (LGPD, art. 11) | Média | Alto | Minimização, consentimento explícito, exclusão de conta, logs sem dados pessoais. Ver `SECURITY_PRIVACY.md`. |
| R6 | UX lenta para registrar séries | Média | Alto | Tela única de sessão, pré-preenchimento com a última sessão, salvamento por série. |
| R7 | Ambiente Android incompleto | Baixa | Médio | Pendências listadas acima; o Flutter também roda no Chrome para depuração da UI. |
| R8 | Metodologia de estímulo ser lida como “ciência exata” | Média | Médio | Pesos configuráveis e documentados; textos explicando que é uma referência, não um diagnóstico. |
| R9 | Versões muito novas (TS 7, SQLAlchemy 2.1, Python 3.14) com incompatibilidades | Média | Baixo | Fixar versões apenas depois de instalar e testar; recuar para a versão anterior se necessário. |
| R10 | Licença da base de exercícios ou alimentos | Média | Médio | Biblioteca de exercícios escrita pelo projeto; base de alimentos verificada antes de importar. |

## 6. Recursos que exigem modelos, APIs ou serviços externos

| Recurso | Dependência | Custo / licença | Quando |
|---|---|---|---|
| Chat de IA contextual | API de LLM com *tool calling* (recomendado: Anthropic Claude; a camada aceita outros) | Pago por token. Chave **somente no backend**. Precisa da sua conta/chave. | Fase 4 |
| Modelo anatômico 3D | Arquivo GLB com músculos separados. Candidatos: **Z-Anatomy** (CC BY-SA 4.0, derivado do BodyParts3D) ou modelo comercial. Renderização: `model_viewer_plus` (WebView) ou `flutter_scene` (Flutter GPU, ainda imaturo). | CC BY-SA exige atribuição e *share-alike* sobre o modelo derivado — avaliar antes de usar. | Pós-Fase 3 (opcional) |
| Mapa muscular 2D | SVG próprio (frente/costas). Há pacotes no pub.dev (`muscle_selector`, `flutter_body_atlas`, etc.), mas a licença e a qualidade de cada um precisam ser verificadas. | Próprio = sem custo e sem risco de licença. | Fase 3 |
| Base de alimentos | TACO (UNICAMP) e/ou Open Food Facts (ODbL) | Gratuitas; termos de reutilização a verificar. Alternativa: alimentos criados pelo usuário + seed pequeno próprio. | Fase 5 |
| Biblioteca de exercícios | Seed próprio em PT-BR (~60–80 exercícios). Alternativas: wger (CC BY-SA), free-exercise-db (domínio público). | Seed próprio = sem risco. | Fase 2 |
| PostgreSQL | Local (18) ou Docker | Gratuito | Fase 1 |
| Hospedagem (API/site) | Ainda não decidida | Pode ter custo. **Sem deploy sem sua aprovação.** | Fase 6+ |
| Strava, Health Connect, wearables | APIs externas com OAuth | Apenas documentadas (`ARCHITECTURE.md` §8) | Futuro |
