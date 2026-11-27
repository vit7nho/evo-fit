# Limitações conhecidas

O que o EvoFit **não faz**, faz só em parte ou não foi verificado, na versão entregue no TCC (Fase 6). Cada item diz o efeito para quem usa e onde está a decisão. O que está aqui é conhecido e foi aceito para o prazo do TCC; não é uma lista de defeitos escondidos.

Situação em 2026-11-26 (etapa 6.5, ADR-069).

## 1. Etapas entregues em parte

| Item | O que falta | Efeito | Onde |
|---|---|---|---|
| Avaliação da IA com os provedores reais (4.7) | A rodada completa das 21 perguntas num plano com cota suficiente e a revisão humana das respostas. As rodadas feitas pararam no limite do plano gratuito: 16 de 21 sem falha automática com o Gemini na frente, 8 de 21 com o Groq na frente. | A qualidade das respostas com um modelo de verdade foi medida só em parte. O modo demonstração passa nas 21, mas responde por regras (ver §3). | [AVALIACAO_IA](AVALIACAO_IA.md), ADR-054, ADR-056 a ADR-058 |
| Catálogo de alimentos da TACO (5.1) | Importar a planilha oficial. Os valores não foram digitados de memória nem copiados de terceiros. | A busca de alimentos só encontra os alimentos que a própria pessoa criou (e os da conta de demonstração). | ADR-055, ROADMAP 5.1 |
| Testes de usabilidade (5.7) | As sessões com 3 a 5 pessoas. Protocolo, termo, planilhas e o piloto do desenvolvedor estão prontos; o piloto não conta como participante. | Não há resultado de SUS nem de taxa de conclusão com usuários reais. | [USABILIDADE](USABILIDADE.md), ADR-064 |

## 2. Funções que o app não tem

- **Unidades imperiais:** o perfil guarda a escolha (`unit_system`), mas o app mostra sempre kg, km e cm (ADR-028).
- **Recordes durante o treino:** os recordes aparecem no histórico e no fim da sessão, não ao vivo enquanto a série é registrada (ADR-035).
- **Tema escuro:** só o tema claro (ADR-025).
- **Meu Corpo em 3D:** é uma prova de conceito, só no Android, com um manequim simples gerado pelo projeto. O padrão é o mapa 2D (ADR-048).
- **iOS:** o projeto Flutter não foi compilado nem testado para iOS.
- **Fora do escopo do TCC:** GPS em tempo real, Strava, Health Connect e relógios, recursos sociais, mais de um idioma, monetização.

## 3. Inteligência artificial

- **Plano gratuito:** as cotas por minuto e por dia dos provedores acabam rápido; quando acabam, a pergunta vai para o próximo da lista (`AI_PROVIDER=gemini,groq,demo`). No plano gratuito do Gemini, o Google pode usar o conteúdo enviado para melhorar os produtos dele; por isso a demonstração usa contas e dados fictícios, o texto livre das limitações não é enviado e o consentimento avisa (ADR-056, ADR-057).
- **Modo demonstração:** responde por regras, no próprio servidor. Não entende perguntas fora do roteiro nem variações muito diferentes das palavras-chave, não conversa (cada pergunta é independente) e as respostas têm sempre o mesmo formato. Serve para a demonstração sem internet ou sem cota, não substitui um modelo (ADR-058).
- **Conferência de números:** cada número da resposta é procurado nos dados consultados, mas a conferência é uma heurística que registra e não bloqueia a resposta (ADR-051). Um modelo real ainda pode errar uma conta ou uma interpretação.
- **Propostas:** a IA só propõe acrescentar, trocar ou ajustar um exercício de uma ficha e criar metas. Outras alterações a pessoa faz pelas telas (ADR-053).

## 4. Operação e infraestrutura

- **Sem servidor público:** a API roda no computador do desenvolvedor. O APK de demonstração aponta para `http://10.0.2.2:8000` (a máquina vista pelo emulador) e só essa variante libera HTTP; um APK para um servidor de verdade exige HTTPS (ADR-067).
- **Sem integração contínua:** não há pipeline de CI/CD nem análise estática contínua (como o SonarQube). Os testes e o lint rodam por script, na máquina: `scripts/test-all.ps1` e `scripts/test-e2e.ps1`.
- **Docker:** o `docker-compose.yml` existe, mas o Docker não estava disponível na máquina de desenvolvimento; tudo foi executado com o PostgreSQL 18 instalado localmente (`DB_MODE=local`, ADR-021).
- **Limite de tentativas de login em memória:** vale por processo da API; reiniciar a API zera a contagem, e várias instâncias não compartilham o limite (ADR-022).
- **Retenção:** os prazos de [SECURITY_PRIVACY](SECURITY_PRIVACY.md) §5 são uma proposta. Não há rotina automática que apague conversas antigas, registros da IA ou tokens vencidos.
- **Chave de assinatura única e local:** a keystore do APK fica em `%USERPROFILE%\.evofit`, fora do repositório. Sem ela (e sem `key.properties`) não dá para publicar uma atualização que o Android aceite por cima do app instalado; precisa de cópia de segurança.

## 5. Conteúdo e validação por profissionais

- **Exercícios:** 71 exercícios escritos pelo projeto, 67 com fotos de um banco em domínio público. O texto ainda não foi revisado por um profissional de Educação Física (ADR-016, ADR-029, ADR-030).
- **Estímulo muscular e planos:** a metodologia do Meu Corpo (séries ponderadas por semana e as faixas de cor) e os planos de caminhada, 5 km e 10 km são referências do projeto, explicadas na tela, não uma prescrição validada por profissional.
- **Nutrição:** as metas diárias têm limites de segurança (ADR-059), mas não são orientação de nutricionista; fora dos limites, o app recusa e indica procurar um profissional.
- **Pendências jurídicas antes de um lançamento real:** Termos de Uso, Política de Privacidade, contrato (DPA) com o provedor de IA, encarregado (DPO), relatório de impacto (RIPD), teste de intrusão independente e plano de resposta a incidentes. Lista completa em [SECURITY_PRIVACY](SECURITY_PRIVACY.md) §6.

## 6. Verificação

- **Onde foi testado:** no emulador Android 15 (EvoFit_Aceite para os aceites e o do dia a dia), com a API real. O APK de release foi instalado e usado no emulador; não há registro de teste num aparelho físico.
- **Testes de integração no aparelho:** cobrem os dois fluxos críticos (a jornada completa de um usuário novo e a conta de demonstração), não todas as telas (ADR-066). O resto é coberto por testes de widget e de fluxo com a API simulada e pelos testes da API com o PostgreSQL de teste.
- **Leitor de tela e fonte grande:** verificados no emulador nas telas principais; não houve teste com pessoas que usam tecnologia assistiva.
