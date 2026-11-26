import { site } from "@/lib/site";

/** Perguntas frequentes: a mesma lista vira a seção da página e o JSON-LD (FAQPage). */
export const faq: Array<{ question: string; answer: string }> = [
  {
    question: `O ${site.name} está disponível para baixar?`,
    answer:
      "Ainda não. É um projeto de Trabalho de Conclusão de Curso, com o app Android em desenvolvimento e testado em emulador. Não está à venda nem publicado em lojas.",
  },
  {
    question: "Quais atividades ele acompanha?",
    answer:
      "Musculação (fichas com técnicas, séries, recordes), corrida, caminhada, ciclismo e natação, além de alimentação, peso e medidas do corpo, metas e planos progressivos de caminhada e corrida.",
  },
  {
    question: "A IA pode inventar números?",
    answer:
      "Ela só responde com o que consulta nos seus registros, pelo servidor e com a sua conta. Os números citados são conferidos contra os dados consultados, e a tela mostra o que foi consultado. Nenhuma alteração é feita sem você confirmar.",
  },
  {
    question: "Meus dados vão para empresas de IA?",
    answer:
      "Só se você autorizar as análises com IA. Nesse caso, apenas os registros ligados à pergunta são enviados ao provedor nomeado no consentimento — nunca o nome nem o e-mail. No modo demonstração, as respostas são montadas por regras no próprio servidor e nada sai dele.",
  },
  {
    question: "Substitui um personal trainer ou um nutricionista?",
    answer:
      "Não. O app organiza e analisa o que você registra. Diante de dor, sintomas ou pedidos de dieta restritiva, ele recomenda procurar um profissional de saúde e não faz diagnósticos.",
  },
  {
    question: "Como o Meu Corpo decide as cores dos músculos?",
    answer:
      "Pelas séries válidas de cada semana: o músculo principal do exercício conta uma série, o secundário meia. As faixas (nenhum, pouco, médio, muito) seguem uma metodologia versionada e são uma referência pelo volume registrado, não um diagnóstico.",
  },
  {
    question: "Como os dados de saúde são tratados?",
    answer:
      "Peso, medidas, alimentação, frequência cardíaca e limitações físicas são dados sensíveis (LGPD). Registrá-los exige um consentimento específico, e revogá-lo apaga esses dados.",
  },
];

/** Dados estruturados da página inicial: o aplicativo e as perguntas frequentes. */
export function homeJsonLd() {
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "SoftwareApplication",
        name: site.name,
        description: site.description,
        applicationCategory: "HealthApplication",
        operatingSystem: "Android",
        inLanguage: "pt-BR",
        url: site.url,
      },
      {
        "@type": "FAQPage",
        mainEntity: faq.map((item) => ({
          "@type": "Question",
          name: item.question,
          acceptedAnswer: { "@type": "Answer", text: item.answer },
        })),
      },
    ],
  };
}

/** JSON no `<script>` sem deixar fechar a tag (recomendação do guia de JSON-LD do Next). */
export function jsonLdScript(data: unknown) {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
