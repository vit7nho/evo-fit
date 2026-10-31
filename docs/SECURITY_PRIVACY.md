# Segurança, privacidade e LGPD

> Este documento registra decisões técnicas. **Não substitui revisão jurídica.** Os itens marcados com ⚖ exigem revisão por profissional de privacidade/jurídico antes de um lançamento real.

## 1. Classificação dos dados

| Classe | Exemplos | Tratamento |
|---|---|---|
| Identificação | e-mail, nome de exibição | Acesso só do próprio usuário; e-mail nunca enviado à IA. |
| Credenciais | hash da senha, refresh tokens | Argon2id / SHA-256; nunca em logs nem respostas. |
| **Dados sensíveis de saúde** (LGPD art. 5º II, art. 11) | limitações físicas, sintomas, peso, medidas, FC, registros alimentares | Consentimento específico e destacado; minimização; enviados à IA somente quando a pergunta exigir e o consentimento de IA estiver ativo. |
| Dados de atividade | treinos, séries, corridas | Acesso só do próprio usuário. |
| Conteúdo de conversa com a IA | mensagens | Retenção limitada (ver §5); excluível pelo usuário. |

## 2. Controles técnicos

- **Autorização por usuário em todas as consultas:** repositórios recebem `user_id` do token; não existe repositório “sem dono” para dados pessoais. Testes automatizados para cada endpoint garantem que o usuário B recebe `404` ao acessar um recurso do usuário A.
- **IDs do cliente nunca determinam a propriedade:** o `user_id` nunca vem do corpo da requisição. IDs de entidades relacionadas (ex.: `exercise_id` em uma ficha) são validados quanto à visibilidade (catálogo global ou criado pelo próprio usuário).
- **Validação de entrada:** Pydantic com limites (tamanhos de texto, faixas numéricas plausíveis, ex.: carga 0–1000 kg, repetições 0–200).
- **Senhas:** Argon2id (parâmetros padrão do argon2-cffi, RFC 9106); 10 a 128 caracteres, sem senhas comuns nem o próprio e-mail. E-mail inexistente e senha errada têm a mesma resposta e o mesmo tempo (verificação descartável). ✅ 2.1
- **Limite de tentativas** ✅ 2.1 (em memória, por processo — ADR-022): login 20/5 min por IP e 5 falhas/15 min por e-mail (bloqueia até com a senha certa); cadastro 5/h por IP; refresh 60/5 min por IP. Resposta `429` com `Retry-After`.
- **Sessão:** access token JWT HS256 de 15 min (algoritmo fixo, `iss` e `typ` verificados); refresh opaco de 256 bits, 30 dias, guardado só como SHA-256, com rotação e detecção de reutilização; logout revoga a família de tokens. ✅ 2.1
- **App:** refresh token no Android Keystore (`flutter_secure_storage`); access token só em memória; backup automático do Android desligado para o token não ir a outro aparelho. ✅ 2.1
- **Segredos:** apenas em variáveis de ambiente; `.env` no `.gitignore`; `.env.example` sem valores reais. O app e o site não recebem nenhuma chave de IA.
- **Logs:** JSON estruturado com uma lista de campos removidos (`password`, `token`, `authorization`, `notes`, `limitations`, `content` de mensagens). Os metadados de chamadas à IA registram tokens, latência e ferramentas usadas — **não** o conteúdo.
- **Erros:** respostas sem *stack trace* fora de `development`.
- **CORS:** só as origens configuradas (site e dev). O app mobile não depende de CORS.
- **HTTPS** obrigatório fora do ambiente local (a definir junto com a hospedagem).
- **Criptografia em repouso:** na v1, depende do disco/volume do provedor. Os tokens de integrações externas (futuras) serão criptografados na aplicação (Fernet/AES-GCM, chave em variável de ambiente).

## 3. Consentimentos

**Implementado (2.2):** `health_data` e `ai_processing` são concedidos e revogados pelo usuário (`PUT`/`DELETE /me/consents/{kind}`); `terms_privacy` só no cadastro. Dados de saúde (`limitation_tags`, `limitations_note`) são recusados sem `health_data` ativo, e **revogar `health_data` apaga esses dados** (ADR-026). O app pede o consentimento em um cartão próprio, destacado, antes de mostrar os campos de saúde. **(2.3)** Metas de peso (`weight_loss`, `weight_gain`, `weight_maintenance`) também exigem `health_data` e são apagadas na revogação; o formulário da meta pede a autorização antes de enviar.

Registrados em `user_consents` (tipo, versão do texto, data, revogação):

- `terms_privacy` — obrigatório no cadastro. ⚖ Os textos de Termos e Política de Privacidade precisam ser redigidos/revisados.
- `health_data` — necessário para registrar limitações, peso, medidas e nutrição. Sem ele, esses campos ficam desativados no app.
- `ai_processing` — necessário para usar a IA. Explica que os dados pertinentes à pergunta são enviados a um provedor externo (nomeado) e quais categorias são enviadas. ⚖ Há transferência internacional de dados (LGPD art. 33) — verificar o enquadramento legal.

## 4. Direitos do titular

- **Acesso/portabilidade:** `GET /api/v1/me/export` (JSON com todos os dados do usuário).
- **Exclusão de conta:** `DELETE /api/v1/me` com reautenticação → exclusão física em cascata dos dados pessoais; logs técnicos mantêm só IDs pseudônimos até expirarem.
- **Correção:** edição normal pelos endpoints de cada módulo.
- **Revogação de consentimento:** revogar `ai_processing` bloqueia novas chamadas; revogar `health_data` oferece a exclusão dos dados sensíveis.

## 5. Retenção (proposta)

| Dado | Retenção |
|---|---|
| Conta e registros | Enquanto a conta existir |
| Conversas com a IA | 180 dias (configurável) ou até a exclusão pelo usuário |
| Metadados de execução da IA | 90 dias |
| Logs de aplicação | 30 dias |
| Refresh tokens revogados/expirados | Removidos por limpeza periódica após 7 dias |

⚖ Os prazos devem ser validados juridicamente.

## 6. Pendências antes de um lançamento real ⚖

1. Termos de Uso e Política de Privacidade.
2. Base legal e contrato (DPA) com o provedor de IA; transferência internacional.
3. Encarregado (DPO) e canal do titular.
4. Avaliação de impacto (RIPD) por envolver dados de saúde.
5. Teste de intrusão/revisão de segurança independente.
6. Plano de resposta a incidentes (comunicação à ANPD).
7. Revisão do conteúdo de exercícios e das orientações da IA por profissionais de Educação Física e Nutrição.
