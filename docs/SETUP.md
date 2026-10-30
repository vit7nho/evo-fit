# Configuração e execução (Windows)

Comandos em **PowerShell**, a partir da raiz do repositório (`evofit/`). Equivalentes para Linux/macOS/Git Bash estão indicados quando diferem.

## 1. Ferramentas

| Ferramenta | Versão usada | Observação |
|---|---|---|
| Git | 2.54 | |
| Python | 3.14 | `py -3.14` |
| Node.js / npm | 24 / 12 | |
| PostgreSQL | 18 (local, porta 5433) **ou** Docker Desktop 29 | Escolha pelo `DB_MODE` do `.env` (seção 2) |
| Flutter / Dart | 3.47.8 / 3.13.7 | SDK em `Documents\desck\flutter`, no PATH |
| Android SDK | platform 37, build-tools 36, cmdline-tools | `%LOCALAPPDATA%\Android\Sdk` |
| Emulador | AVD `Medium_Phone_API_35` (Android 15, x86_64) | Primeira inicialização: ~1–2 min |
| Variáveis do usuário | `ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk` · `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\tmp\jdkuds` | Já configuradas nesta máquina (ver Problemas comuns). O Java passa a imprimir “Picked up JAVA_TOOL_OPTIONS…”, o que é esperado |

Verificação: `flutter doctor` deve mostrar ✔ em Flutter e Android toolchain (o aviso de Visual Studio pode ser ignorado: só serve para app desktop Windows).

Em uma máquina nova: Android Studio → SDK Manager → **Android SDK Command-line Tools (latest)** + uma imagem de sistema x86_64; depois `flutter doctor --android-licenses`.

## 2. Variáveis de ambiente

```powershell
Copy-Item .env.example .env
```

O `.env` fica na raiz e é lido pela API, pelos scripts e pelo Docker Compose. Ele nunca é versionado.

`JWT_SECRET` é obrigatório (mínimo 32 caracteres). Gere um valor próprio e substitua o de exemplo:

```powershell
py -3.14 -c "import secrets; print(secrets.token_urlsafe(48))"
```

`DB_MODE` escolhe de onde vem o banco:

- `docker` (padrão do `.env.example`): os scripts sobem o PostgreSQL 18 pelo Compose. Portas **5442** (dev) e **5443** (testes).
- `local`: PostgreSQL instalado na máquina; os scripts não chamam o Docker. Siga a seção 8 e aponte `DATABASE_URL`/`TEST_DATABASE_URL` para ele. **É o modo usado nesta máquina** (PostgreSQL 18 na porta 5433), porque aqui o Docker não consegue iniciar containers (ver Problemas comuns).

API **8000**, site **3000**.

## 3. API (FastAPI)

Atalho que sobe o banco, cria o venv na primeira vez, aplica as migrações e inicia a API com reload:

```powershell
.\scripts\dev-api.ps1
```

Passo a passo equivalente:

```powershell
docker compose up -d --wait db
cd services/api
py -3.14 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
.\.venv\Scripts\alembic.exe upgrade head
.\.venv\Scripts\uvicorn.exe app.main:app --reload --host 0.0.0.0 --port 8000
```

- Documentação interativa: <http://localhost:8000/docs>
- Saúde: <http://localhost:8000/api/v1/health> → `200` com `database: ok`, ou `503` com `database: unavailable` quando o banco não responde (em até ~5 s).
- `--host 0.0.0.0` é necessário para o emulador alcançar a API.

Nova migração (sempre revisar o arquivo gerado antes de aplicar):

```powershell
.\.venv\Scripts\alembic.exe revision --autogenerate -m "descricao"
```

## 4. App (Flutter)

Com o emulador aberto (Android Studio → Device Manager, ou `flutter emulators --launch Medium_Phone_API_35`):

```powershell
cd apps/mobile
flutter pub get
flutter run
```

O app usa `http://10.0.2.2:8000` por padrão (o computador visto de dentro do emulador). Para um celular físico na mesma rede:

```powershell
flutter run --dart-define=API_BASE_URL=http://IP_DO_COMPUTADOR:8000
```

HTTP sem TLS só é permitido no build de debug (`android/app/src/debug/AndroidManifest.xml`).

## 5. Site (Next.js)

```powershell
cd apps/web
npm install
npm run dev      # http://localhost:3000
```

## 6. Tokens de design

A identidade visual vem de `packages/design-tokens/tokens.json`. Depois de editar:

```powershell
python scripts/generate_tokens.py
```

Isso gera `apps/mobile/lib/app/theme/tokens.g.dart` e `apps/web/src/styles/tokens.css` (não edite esses arquivos à mão).

## 7. Testes e verificações

Tudo de uma vez (a parte da API precisa do banco de testes: no modo `docker`, o Docker Desktop aberto; no modo `local`, o PostgreSQL da máquina rodando):

```powershell
.\scripts\test-all.ps1
```

Ou por parte: `.\scripts\test-all.ps1 -Only api,web` · Linux/macOS/Git Bash: `sh scripts/test-all.sh api web`.

| Parte | O que roda |
|---|---|
| tokens | `generate_tokens.py --check` (arquivos gerados atualizados) |
| api | sobe `db-test` (só no modo `docker`); `ruff check`; `ruff format --check`; `pytest` (migrações reais no Postgres, testes transacionais) |
| mobile | `dart format` (checagem); `flutter analyze`; `flutter test` |
| web | `tsc --noEmit`; `eslint`; `vitest run` |

## 8. Alternativa sem Docker: PostgreSQL local

A API e os testes só precisam de duas URLs no `.env`. Com um PostgreSQL instalado na máquina (recomendado: 18, a mesma versão do Compose), crie usuário e bancos como superusuário, no `psql` ou pgAdmin. Exemplo com o PostgreSQL 18 na porta 5433:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -h 127.0.0.1 -p 5433 -U postgres
```

```sql
CREATE ROLE evofit LOGIN PASSWORD 'evofit_dev_only';
CREATE DATABASE evofit OWNER evofit;
CREATE DATABASE evofit_test OWNER evofit;
```

E ajuste o `.env`:

```
DB_MODE=local
DATABASE_URL=postgresql+psycopg://evofit:evofit_dev_only@127.0.0.1:5433/evofit
TEST_DATABASE_URL=postgresql+psycopg://evofit:evofit_dev_only@127.0.0.1:5433/evofit_test
```

`evofit_test` precisa ser exclusivo dos testes: o pytest apaga e recria as tabelas dele a cada execução. Os scripts `dev-api` e `test-all` funcionam normalmente nesse modo.

## 9. Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| `failed to connect to the docker API ... docker_engine` | Docker Desktop fechado | Abrir o Docker Desktop e aguardar “Engine running” |
| Containers ficam em `Created` e `docker run` não retorna | Docker Desktop usando o backend **Docker VMM** (beta) porque o WSL2 não inicia (`wsl --status`: “virtualização não habilitada”). O log `%LOCALAPPDATA%\Docker\log\host\monitor.log` mostra `POST /containers/.../start` sem resposta e erros `vfkit` | Habilitar a *Plataforma de Máquina Virtual* (`wsl.exe --install --no-distribution`, como administrador, e reiniciar) e a virtualização no firmware, se necessário; depois, Docker Desktop → Settings → General → **Use the WSL 2 based engine**. Sem acesso de administrador: usar um PostgreSQL local (ver seção 8) |
| pytest: “Banco de teste indisponível” | Modo `docker`: `db-test` parado. Modo `local`: serviço do PostgreSQL parado | `docker compose up -d --wait db-test` · ou `Get-Service postgresql-x64-18` e iniciar o serviço |
| `.\scripts\dev-api.ps1` “não é reconhecido” · `flutter run`: “No pubspec.yaml file found” | Terminal na pasta errada | Scripts: rodar a partir de `evofit/`. Flutter: a partir de `evofit/apps/mobile` |
| `flutter emulators --launch` sai com código 1 | O mesmo AVD já está aberto (às vezes travado como `offline` no `adb devices`) | Fechar a janela/processo do emulador e abrir de novo com `emulator -avd Medium_Phone_API_35 -no-snapshot-load` |
| `flutter run`: “No supported devices connected” | Emulador fechado | Abrir o emulador antes. **Não** rodar `flutter create .` (criaria plataformas fora do escopo) |
| `Activate.ps1 cannot be loaded` | Política de execução | Use os executáveis direto (`.\.venv\Scripts\python.exe`), como neste guia |
| Scripts `.ps1` com acentos quebrados | Arquivo salvo sem BOM | Os scripts do repositório estão em UTF-8 com BOM; mantenha assim ao editar |
| App mostra “API indisponível” no emulador | API ouvindo só em 127.0.0.1, ou URL `localhost` | Inicie com `--host 0.0.0.0`; o app deve usar `10.0.2.2` |
| Porta 5442/5443 ocupada | Outro serviço | Altere `POSTGRES_PORT`/`POSTGRES_TEST_PORT` e as URLs no `.env` |
| `npm install` com erro de peer `@types/node` | Versão de tipos antiga | O projeto usa `@types/node@^24` (mesma versão do Node) |
| Gradle/`flutter build apk`: `Unable to establish loopback connection` | O Java (JDK 25 do Android Studio) não consegue criar seu socket interno na pasta TEMP do usuário quando ela tem caminho curto do Windows (ex.: `NOME~1.ABC`) | Crie `C:\tmp\jdkuds` e defina `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\tmp\jdkuds` (na sessão: `$env:JAVA_TOOL_OPTIONS=...`; permanente: variáveis de ambiente do usuário). Depois `cd apps/mobile/android; .\gradlew.bat --stop` |
| Emulador fecha na hora com `Cannot find AVD system path` | `ANDROID_HOME` aponta para outra pasta de SDK (ex.: `C:\Android\Sdk`) sem a imagem de sistema | Ajuste `ANDROID_HOME` para `%LOCALAPPDATA%\Android\Sdk` (variáveis de ambiente do usuário) e reabra o terminal |
| Primeiro build Android demora | O Gradle baixa NDK e CMake automaticamente | Normal na primeira vez (licenças já aceitas) |
