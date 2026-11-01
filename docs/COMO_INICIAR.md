# Como iniciar tudo depois de ligar o PC

Roteiro curto do dia a dia. A instalação inicial e os detalhes estão em [SETUP.md](SETUP.md).

**Resumo:** o banco já liga sozinho; você abre a **API**, o **emulador** e o **app**, nessa ordem, cada um no seu terminal. O site é opcional.

| O quê | Onde rodar | Fica aberto? |
|---|---|---|
| Banco (PostgreSQL 18) | nada a fazer: inicia com o Windows | — |
| API | Terminal 1, na pasta `evofit` | sim |
| Emulador Android | Terminal 2 (qualquer pasta) | sim (a janela do celular) |
| App | Terminal 2, na pasta `evofit\apps\mobile` | sim |
| Site (opcional) | Terminal 3, na pasta `evofit\apps\web` | sim |

## 0. Banco de dados (só conferir)

O serviço `postgresql-x64-18` está como **automático**: liga junto com o Windows. Para conferir:

```powershell
Get-Service postgresql-x64-18
```

Deve aparecer `Running`. Se aparecer `Stopped`, inicie pelo menu Iniciar → **Serviços** → `postgresql-x64-18` → Iniciar.

## 1. API (Terminal 1)

```powershell
cd C:\Users\vitor.santos\Documents\desck\evofit
.\scripts\dev-api.ps1
```

O script aplica as migrações pendentes e sobe a API. Está pronta quando aparecer `Application startup complete`. Deixe este terminal aberto.

Para conferir, abra no navegador: <http://localhost:8000/api/v1/health> → deve mostrar `"status":"ok","database":"ok"`. A documentação interativa fica em <http://localhost:8000/docs>.

## 2. Emulador (Terminal 2)

```powershell
flutter emulators --launch Medium_Phone_API_35
```

A janela do celular abre; espere a tela inicial do Android (1–2 minutos na primeira vez do dia). Para conferir que ele está pronto:

```powershell
flutter devices
```

Deve listar `emulator-5554`.

## 3. App (Terminal 2)

```powershell
cd C:\Users\vitor.santos\Documents\desck\evofit\apps\mobile
flutter run
```

A primeira compilação do dia leva 1–2 minutos. Com o app aberto, no terminal:

| Tecla | Faz |
|---|---|
| `r` | recarrega o código alterado sem perder a tela (*hot reload*) |
| `R` | reinicia o app |
| `q` | fecha o app e libera o terminal |

O app fala com a API pelo endereço `10.0.2.2:8000`, que é o seu PC visto de dentro do emulador. Por isso a API precisa estar rodando antes.

## 4. Site (opcional, Terminal 3)

```powershell
cd C:\Users\vitor.santos\Documents\desck\evofit\apps\web
npm run dev
```

Abra <http://localhost:3000>.

## Antes de um commit

Roda todas as verificações (tokens, API, app e site), na pasta `evofit`:

```powershell
.\scripts\test-all.ps1
```

## Para desligar

1. No terminal do app: `q`.
2. Nos terminais da API e do site: `Ctrl + C`.
3. Feche a janela do emulador.

Nada precisa ser salvo: os dados ficam no banco, que continua no PC.

## Se algo der errado

| Sintoma | O que fazer |
|---|---|
| `dev-api.ps1` “não é reconhecido” | O terminal não está na pasta `evofit`. Rode o `cd` do passo 1. |
| `flutter run`: “No pubspec.yaml file found” | O terminal não está em `evofit\apps\mobile`. Rode o `cd` do passo 3. |
| `flutter run`: “No supported devices connected” | O emulador não está aberto ou ainda está ligando. Faça o passo 2 e espere. |
| `flutter emulators --launch` sai com código 1 | O emulador já está aberto (ou travado). Feche a janela dele e rode de novo. Se continuar: `& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd Medium_Phone_API_35 -no-snapshot-load` |
| A API não sobe: porta 8000 em uso | Ficou uma API antiga aberta. Feche o outro terminal ou encerre o processo: `Stop-Process -Id (Get-NetTCPConnection -LocalPort 8000 -State Listen).OwningProcess` |
| No app: “Não foi possível conectar” | A API não está rodando. Confira o passo 1 e toque em “Tentar novamente”. |
| `/health` mostra `"database":"unavailable"` | O PostgreSQL está parado. Veja o passo 0. |

Mais casos em [SETUP.md §9](SETUP.md#9-problemas-comuns).
