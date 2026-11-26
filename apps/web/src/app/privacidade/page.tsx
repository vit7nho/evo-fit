import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { SiteFooter, SiteHeader, SkipLink } from "@/components/site-chrome";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Aviso de privacidade",
  description: `Como o ${site.name} trata os seus dados: consentimentos, dados de saúde, IA, retenção e direitos previstos na LGPD.`,
  alternates: { canonical: "/privacidade" },
};

function Block({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="mt-2xl">
      <h2 id={id} className="font-display text-title font-semibold tracking-tight">
        {title}
      </h2>
      <div className="mt-md space-y-md text-body-sm leading-relaxed text-site-muted">{children}</div>
    </section>
  );
}

/**
 * Aviso de privacidade do projeto, com o que o app faz hoje (docs/SECURITY_PRIVACY.md).
 * É o resumo de um projeto acadêmico, não uma política revisada juridicamente — e diz isso.
 */
export default function Privacy() {
  return (
    <div className="site overflow-x-clip">
      <SkipLink />
      <SiteHeader onHome={false} />
      <main id="conteudo" className="mx-auto w-full max-w-[48rem] px-lg pt-[8rem] pb-[6rem] sm:px-xl">
        <p className="text-caption font-semibold tracking-[0.2em] text-site-muted uppercase">
          Privacidade
        </p>
        <h1 className="mt-md font-display text-[2.5rem] leading-[1.05] font-bold tracking-[-0.035em] sm:text-[3.25rem]">
          Aviso de privacidade
        </h1>
        <p className="mt-lg rounded-[20px] border border-white/15 p-lg text-body-sm leading-relaxed">
          O {site.name} é um projeto de Trabalho de Conclusão de Curso, ainda não publicado. Este
          aviso resume como o app trata os dados hoje; antes de um lançamento real, os Termos de
          Uso e a Política de Privacidade precisam de revisão jurídica.
        </p>

        <Block id="dados" title="Que dados o app guarda">
          <p>
            Identificação (e-mail e nome de exibição), o perfil de treino (objetivo, modalidades,
            disponibilidade, equipamento), os registros de treino e de atividades, as metas e as
            conversas com o assistente.
          </p>
          <p>
            Com o consentimento de dados de saúde: limitações físicas, frequência cardíaca das
            atividades, refeições, metas nutricionais, peso e medidas.
          </p>
          <p>A senha é guardada só como hash (Argon2id); ninguém consegue lê-la.</p>
        </Block>

        <Block id="consentimentos" title="Consentimentos">
          <ul className="list-disc space-y-sm pl-lg">
            <li>
              <strong className="text-white">Termos e privacidade</strong> — no cadastro.
            </li>
            <li>
              <strong className="text-white">Dados de saúde</strong> — pedido no próprio app
              antes de qualquer campo de saúde. Revogar apaga as limitações, a frequência
              cardíaca, as metas de peso, as refeições, as metas nutricionais, o peso e as
              medidas.
            </li>
            <li>
              <strong className="text-white">Análises com IA</strong> — necessário para usar o
              assistente. O texto do consentimento nomeia a empresa que recebe as perguntas.
              Revogar bloqueia as próximas perguntas.
            </li>
          </ul>
        </Block>

        <Block id="ia" title="O assistente de IA">
          <p>
            Para responder, o assistente consulta só os registros ligados à pergunta e os envia
            ao provedor de IA configurado no servidor. Nome e e-mail nunca são enviados. Nos
            planos gratuitos dos provedores, o conteúdo pode ser usado por eles para melhorar os
            produtos; por isso o texto livre das limitações não é enviado, e o consentimento
            avisa.
          </p>
          <p>
            No modo demonstração, as respostas são montadas por regras no próprio servidor e
            nada é enviado a empresas de IA. O registro de cada resposta guarda o provedor, o
            tempo e as ferramentas consultadas — não o conteúdo.
          </p>
        </Block>

        <Block id="seguranca" title="Segurança">
          <p>
            Cada consulta usa a conta autenticada; testes automáticos tentam ler e alterar
            dados de outra pessoa em todas as rotas. O login tem limite de tentativas, a sessão
            usa tokens de curta duração e o token de renovação fica guardado de forma segura no
            aparelho. Os registros técnicos (logs) não guardam senhas, tokens nem dados de saúde.
          </p>
        </Block>

        <Block id="retencao" title="Por quanto tempo">
          <p>
            Os registros ficam enquanto a conta existir. Proposta para o lançamento: conversas
            com a IA por até 180 dias, metadados das respostas por 90 dias e logs técnicos por
            30 dias.
          </p>
        </Block>

        <Block id="direitos" title="Seus direitos (LGPD)">
          <p>
            Você pode corrigir os dados no próprio app, revogar os consentimentos a qualquer
            momento e apagar conversas com o assistente. A exportação de todos os dados e a
            exclusão da conta pelo app estão em desenvolvimento (próxima etapa do projeto).
          </p>
        </Block>

        <p className="mt-2xl text-body-sm">
          <Link className="font-semibold underline underline-offset-4 hover:text-site-muted" href="/">
            Voltar para o início
          </Link>
        </p>
      </main>
      <SiteFooter onHome={false} />
    </div>
  );
}
