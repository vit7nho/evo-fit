import Link from "next/link";
import { Fragment, type CSSProperties, type ReactNode } from "react";

import { Reveal } from "@/components/motion";
import {
  BodyScreen,
  CoachScreen,
  HistoryScreen,
  NutritionScreen,
  RecordsScreen,
  SessionScreen,
  WeightScreen,
} from "@/components/phone";
import { ZoomablePhone } from "@/components/phone-zoom";
import { SiteFooter, SiteHeader, SkipLink } from "@/components/site-chrome";
import AnimatedGradient from "@/components/spell/animated-gradient";
import { faq, homeJsonLd, jsonLdScript } from "@/lib/content";
import { site } from "@/lib/site";

/** Cores do mapa de estímulo do app (pouco, médio, muito): a paleta do site. */
const STIMULUS = "linear-gradient(90deg, #3D7BFF 0%, #F28C28 55%, #E5484D 100%)";

const techniques = [
  "Bi-set",
  "Supersérie",
  "Drop set",
  "Rest-pause",
  "Corrida",
  "Caminhada",
  "Meu Corpo",
  "Recordes pessoais",
  "Metas nutricionais",
  "Peso e medidas",
  "IA com seus dados",
];

/** Título que entra palavra por palavra. */
function Words({ text, delay = 0 }: { text: string; delay?: number }) {
  // O espaço fica fora da palavra: dentro do inline-block, o nome acessível do
  // título saía grudado ("Suaevolução").
  return text.split(" ").map((word, i) => (
    <Fragment key={`${word}-${i}`}>
      <span
        className="site-word"
        style={{ animationDelay: `${delay + i * 70}ms` } satisfies CSSProperties}
      >
        {word}
      </span>{" "}
    </Fragment>
  ));
}

function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <p className="text-caption font-semibold tracking-[0.2em] text-site-muted uppercase">
      {children}
    </p>
  );
}

/** Cabeçalho de seção: rótulo, título (h2) e texto opcional. */
function SectionTitle({
  id,
  eyebrow,
  title,
  children,
}: {
  id: string;
  eyebrow: string;
  title: ReactNode;
  children?: ReactNode;
}) {
  return (
    <Reveal className="max-w-[48rem]">
      <Eyebrow>{eyebrow}</Eyebrow>
      <h2
        id={id}
        className="mt-md font-display text-[2.25rem] leading-[1.02] font-bold tracking-[-0.035em] sm:text-[3.5rem]"
      >
        {title}
      </h2>
      {children && (
        <p className="mt-lg max-w-[42rem] text-body leading-relaxed text-site-muted">{children}</p>
      )}
    </Reveal>
  );
}

/** Cartão de recurso: a demonstração em cima, o texto embaixo. */
function Feature({
  eyebrow,
  title,
  description,
  delay = 0,
  children,
}: {
  eyebrow: string;
  title: string;
  description: string;
  delay?: number;
  children: ReactNode;
}) {
  return (
    <Reveal delay={delay} className="flex">
      <article className="flex w-full flex-col overflow-hidden rounded-[28px] border border-white/10 bg-white/[0.03]">
        <div
          aria-hidden="true"
          className="relative flex min-h-56 flex-1 items-center justify-center p-xl"
        >
          {children}
        </div>
        <div className="border-t border-white/10 p-xl">
          <Eyebrow>{eyebrow}</Eyebrow>
          <h3 className="mt-sm font-display text-title font-semibold tracking-tight">{title}</h3>
          <p className="mt-sm text-body-sm leading-relaxed text-site-muted">{description}</p>
        </div>
      </article>
    </Reveal>
  );
}

/** Bi-set em miniatura: dois exercícios unidos por uma barra, descanso após a rodada. */
function BisetDemo() {
  return (
    <div className="w-full max-w-[20rem] border-l-4 border-white pl-md">
      <p className="text-[0.6875rem] text-site-muted">Bi-set · descanso 1 min após a rodada</p>
      {["Supino reto com barra", "Crucifixo com halteres"].map((name, i) => (
        <div key={name} className="mt-sm rounded-[14px] bg-white/[0.06] px-md py-sm">
          <p className="text-body-sm font-semibold">{name}</p>
          <p className="text-caption text-site-muted">
            {i === 0 ? "3 × 8–12 · 60 kg" : "3 × 12 · 14 kg"}
          </p>
        </div>
      ))}
    </div>
  );
}

/** Ritmo semana a semana de quem corre (linha). */
function PaceDemo() {
  return (
    <svg viewBox="0 0 300 120" className="w-full max-w-[20rem]" fill="none">
      <defs>
        <linearGradient id="pace" x1="0" x2="1">
          <stop offset="0" stopColor="#3D7BFF" />
          <stop offset="1" stopColor="#E5484D" />
        </linearGradient>
      </defs>
      {[30, 60, 90].map((y) => (
        <line key={y} x1="0" x2="300" y1={y} y2={y} stroke="rgba(255,255,255,0.08)" />
      ))}
      <path
        d="M0 90 C 40 80, 60 50, 100 58 S 160 30, 200 40 S 260 20, 300 24"
        stroke="url(#pace)"
        strokeWidth="4"
        strokeLinecap="round"
      />
      <text x="0" y="116" fill="rgba(255,255,255,0.5)" fontSize="11">
        Plano de 5 km · semana 4 de 8 · 5:42 /km
      </text>
    </svg>
  );
}

/** Mapa de estímulo estilizado: cada músculo na cor de quanto foi treinado. */
function BodyDemo() {
  const parts: Array<[string, string]> = [
    ["M88 30a12 12 0 1 0 24 0a12 12 0 1 0 -24 0", "#DCDBD5"],
    ["M70 52h60l-6 46H76z", "#E5484D"],
    ["M52 56l16-4 4 40-14 4z", "#F28C28"],
    ["M148 56l-16-4-4 40 14 4z", "#F28C28"],
    ["M76 100h48l-4 26H80z", "#3D7BFF"],
    ["M80 128h18l-2 60H82z", "#F28C28"],
    ["M102 128h18l-2 60h-14z", "#F28C28"],
  ];
  return (
    <div className="flex items-center gap-xl">
      <svg viewBox="40 14 120 180" className="h-48">
        {parts.map(([d, fill]) => (
          <path key={d} d={d} fill={fill} />
        ))}
      </svg>
      <ul className="space-y-sm text-caption text-site-muted">
        {[
          ["#E5484D", "Muito"],
          ["#F28C28", "Médio"],
          ["#3D7BFF", "Pouco"],
          ["#DCDBD5", "Nada"],
        ].map(([color, label]) => (
          <li key={label} className="flex items-center gap-sm">
            <span className="size-3 rounded-pill" style={{ background: color }} />
            {label}
          </li>
        ))}
      </ul>
    </div>
  );
}

/** O dia contra a meta (barras) e o peso caindo semana a semana. */
function NutritionDemo() {
  const bars: Array<[string, number]> = [
    ["Calorias", 0.69],
    ["Proteína", 0.44],
    ["Carboidratos", 0.78],
  ];
  return (
    <div className="w-full max-w-[20rem] space-y-md">
      {bars.map(([label, ratio]) => (
        <div key={label}>
          <div className="flex justify-between text-caption text-site-muted">
            <span>{label}</span>
            <span>{Math.round(ratio * 100)}% da meta</span>
          </div>
          <div className="mt-xs h-2 rounded-pill bg-white/10">
            <div
              className="h-full rounded-pill"
              style={{ width: `${ratio * 100}%`, background: STIMULUS }}
            />
          </div>
        </div>
      ))}
      <p className="text-caption text-site-muted">Peso: 80 → 77,6 kg em 4 semanas</p>
    </div>
  );
}

/** Metas medidas pelos registros. */
function GoalsDemo() {
  const goals: Array<[string, string, number]> = [
    ["Supino 70 kg × 5", "62,5 kg", 0.89],
    ["Correr 10 km", "6 km", 0.6],
    ["Chegar a 72 kg", "77,6 kg", 0.3],
  ];
  return (
    <ul className="w-full max-w-[20rem] space-y-md">
      {goals.map(([title, now, ratio]) => (
        <li key={title}>
          <div className="flex justify-between text-body-sm">
            <span className="font-semibold">{title}</span>
            <span className="text-site-muted">{now}</span>
          </div>
          <div className="mt-xs h-1.5 rounded-pill bg-white/10">
            <div className="h-full rounded-pill bg-white" style={{ width: `${ratio * 100}%` }} />
          </div>
        </li>
      ))}
    </ul>
  );
}

/** Conversa com a IA a partir dos dados do treino. */
function AiDemo() {
  return (
    <div className="w-full max-w-[20rem] space-y-sm text-body-sm">
      <p className="ml-auto w-fit rounded-[18px] rounded-br-[6px] bg-white px-md py-sm text-black">
        Como foi meu supino este mês?
      </p>
      <p className="w-fit rounded-[18px] rounded-bl-[6px] bg-white/[0.08] px-md py-sm">
        Sua maior carga em 8 repetições subiu de 60 para 62,5 kg — um recorde no dia 3. O 1RM
        estimado ficou em cerca de 79 kg.
      </p>
      <p className="text-caption text-site-muted">Consultou: histórico do exercício</p>
    </div>
  );
}

const screens: Array<{ title: string; text: string; label: string; screen: ReactNode }> = [
  {
    title: "Registro em tabela",
    text: "A, 1, F, D, RP: aquecimento, válida, falha, drop e rest-pause no número da série.",
    label: "Tela do treino com a tabela de séries.",
    screen: <SessionScreen />,
  },
  {
    title: "Histórico",
    text: "Cada treino com duração, séries, volume e os recordes que caíram.",
    label: "Tela do histórico com treinos concluídos e selo de recordes.",
    screen: <HistoryScreen />,
  },
  {
    title: "Recordes",
    text: "Maior carga, 1RM estimado e a melhor carga para cada número de repetições.",
    label: "Tela de recordes de um exercício com a melhor carga por repetições.",
    screen: <RecordsScreen />,
  },
  {
    title: "Meu Corpo",
    text: "O estímulo de cada músculo no período, em cores e numa lista acessível.",
    label:
      "Tela do Meu Corpo: silhueta com os músculos coloridos pela faixa de estímulo e a lista de séries por semana.",
    screen: <BodyScreen />,
  },
  {
    title: "Nutrição",
    text: "As calorias e os macronutrientes do dia contra as metas que você definiu.",
    label: "Tela da nutrição: total do dia contra a meta de calorias, macronutrientes e uma refeição.",
    screen: <NutritionScreen />,
  },
  {
    title: "Peso e medidas",
    text: "A tendência das semanas, não o susto de um dia: variação, ritmo e gráfico.",
    label: "Tela de peso e medidas: último peso, variação, ritmo por semana e gráfico das pesagens.",
    screen: <WeightScreen />,
  },
  {
    title: "Assistente",
    text: "Responde com os seus registros, mostra o que consultou e pede confirmação.",
    label:
      "Tela do assistente: resposta sobre a semana de treinos, o que foi consultado e uma proposta com os botões Confirmar e Recusar.",
    screen: <CoachScreen />,
  },
];

const steps: Array<[string, string]> = [
  [
    "Registre",
    "Séries no treino, corridas, refeições e pesagens — em poucos toques, com a última vez ao lado.",
  ],
  [
    "Acompanhe",
    "Painel pelo seu objetivo, Meu Corpo, recordes, comparativos e metas medidas pelos registros.",
  ],
  [
    "Pergunte",
    "O assistente consulta os seus dados para responder e só altera uma ficha ou meta depois do seu sim.",
  ],
];

const aiRules: Array<[string, string]> = [
  [
    "Consulta antes de responder",
    "Cada número vem de uma consulta aos seus registros, feita pelo servidor com a sua conta — nunca com dados de outra pessoa.",
  ],
  [
    "Mostra o que consultou",
    "Embaixo de cada resposta: “Consultou: treinos e atividades”. Números que não estão nos dados são contados e registrados.",
  ],
  [
    "Pede confirmação",
    "Sugestões para a ficha ou para as metas aparecem como proposta, com Confirmar e Recusar. Nada muda sozinho.",
  ],
  [
    "Conhece os limites",
    "Não faz diagnósticos nem monta dietas: diante de dor, sintomas ou dieta restritiva, recomenda um profissional.",
  ],
];

const privacy: Array<[string, string]> = [
  [
    "Consentimentos separados",
    "Termos no cadastro; dados de saúde e análises com IA só com autorização própria, que você desliga quando quiser.",
  ],
  [
    "Dados de saúde protegidos",
    "Peso, medidas, alimentação e frequência cardíaca exigem consentimento específico; revogar apaga esses dados.",
  ],
  [
    "Cada um vê só o seu",
    "Todas as consultas usam a conta autenticada, com testes automáticos que tentam ler dados de outra pessoa.",
  ],
  [
    "A IA recebe o mínimo",
    "Só os registros ligados à pergunta, sem nome nem e-mail, para o provedor nomeado no consentimento.",
  ],
];

const working = [
  "Fichas com bi-set, supersérie, drop set e rest-pause",
  "Treino em tabela, histórico, recordes e 1RM estimado",
  "Corrida, caminhada, ciclismo e natação, com planos progressivos",
  "Painel pelo objetivo, Meu Corpo, Evolução e comparativos",
  "Nutrição com metas, peso e medidas com tendência",
  "Assistente com propostas e modo demonstração",
  "Exportação de todos os dados e exclusão da conta pelo app (LGPD)",
];

const next = ["Testes de usabilidade com 3 a 5 pessoas"];

export default function Home() {
  return (
    <div className="site overflow-x-clip">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: jsonLdScript(homeJsonLd()) }}
      />
      <SkipLink />
      <SiteHeader />

      <main id="conteudo">
        <section
          aria-labelledby="hero-title"
          className="relative isolate flex min-h-[100svh] items-center overflow-hidden pt-[6rem]"
        >
          <AnimatedGradient
            config={{
              preset: "custom",
              color1: "#070709",
              color2: "#2F5BFF",
              color3: "#E5484D",
              rotation: 0,
              proportion: 55,
              scale: 0.6,
              speed: 20,
              distortion: 8,
              swirl: 55,
              swirlIterations: 8,
              softness: 100,
              offset: -120,
              shape: "Checks",
              shapeSize: 30,
            }}
            noise={{ opacity: 0.35, scale: 1 }}
            style={{ zIndex: -2 }}
          />
          {/* Por cima do gradiente: escurece à esquerda (texto) e embaixo (próxima seção). */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-0 -z-1 bg-[linear-gradient(90deg,rgba(7,7,9,0.85)_0%,rgba(7,7,9,0.35)_55%,rgba(7,7,9,0.1)_100%),linear-gradient(180deg,transparent_60%,#070709_100%)]"
          />

          <div className="mx-auto grid w-full max-w-6xl items-center gap-3xl px-lg py-3xl sm:px-xl lg:grid-cols-[1.15fr_0.85fr]">
            <div>
              <p className="site-word inline-flex items-center gap-sm rounded-pill border border-white/15 bg-black/30 px-md py-xs text-caption text-site-muted backdrop-blur">
                <span aria-hidden="true" className="size-1.5 rounded-pill bg-[#3D7BFF]" />
                Musculação · corrida · nutrição · IA
              </p>
              <h1
                id="hero-title"
                className="mt-xl font-display text-[2.75rem] leading-[0.98] font-bold tracking-[-0.045em] text-balance sm:text-[4.5rem] lg:text-[5.25rem]"
              >
                <Words text="Sua evolução," />
                {/* O gradiente fica num filho sem animação: animar o próprio elemento
                    com background-clip:text faz o texto piscar em alguns navegadores. */}
                <span className="site-word" style={{ animationDelay: "160ms" }}>
                  <span
                    className="bg-clip-text text-transparent"
                    style={{ backgroundImage: STIMULUS }}
                  >
                    série por série.
                  </span>
                </span>
              </h1>
              <p
                className="site-word mt-xl max-w-[34rem] text-body leading-relaxed text-site-muted sm:text-title-sm sm:leading-relaxed"
                style={{ animationDelay: "320ms" }}
              >
                {site.description}
              </p>
              <div
                className="site-word mt-2xl flex flex-wrap gap-md"
                style={{ animationDelay: "420ms" }}
              >
                <a
                  href="#app"
                  className="rounded-pill bg-white px-xl py-md text-body-sm font-semibold text-black transition-transform hover:-translate-y-0.5"
                >
                  Ver o app
                </a>
                <a
                  href="#recursos"
                  className="rounded-pill border border-white/20 px-xl py-md text-body-sm font-semibold transition-colors hover:bg-white/10"
                >
                  O que ele faz
                </a>
              </div>
            </div>

            <div className="relative mx-auto">
              <div className="site-float">
                <ZoomablePhone
                  title="Treino em andamento"
                  tiltLimit={10}
                  label="Tela do treino no app: tabela com série, anterior, carga, repetições e confirmação; aquecimento, válida, até a falha e drop set; descanso em contagem regressiva."
                >
                  <SessionScreen />
                </ZoomablePhone>
              </div>
              {/* z-20: por cima do celular (que inclina e cria a própria camada). */}
              <p
                className="site-chip absolute top-24 -left-24 z-20 hidden sm:block"
                aria-hidden="true"
              >
                🏆 Recorde · 62,5 kg × 8
              </p>
              <p
                className="site-chip absolute -right-16 bottom-36 z-20 hidden sm:block"
                style={{ animationDelay: "1.2s" }}
                aria-hidden="true"
              >
                D · drop set sem descanso
              </p>
            </div>
          </div>
        </section>

        <div aria-hidden="true" className="site-marquee border-y border-white/10 py-lg">
          <div className="site-marquee-track flex w-max flex-nowrap">
            {/* Duas cópias iguais lado a lado, cada item com o próprio espaço à direita:
                a trilha anda exatamente uma cópia (−50%) e a volta não pula. */}
            {[0, 1].map((copy) => (
              <div key={copy} className="flex shrink-0 flex-nowrap">
                {[...techniques, ...techniques].map((t, i) => (
                  <span
                    key={`${t}-${i}`}
                    className="flex items-center gap-xl pr-xl font-display text-title font-semibold whitespace-nowrap"
                  >
                    {t}
                    <span className="size-2 rounded-pill" style={{ background: STIMULUS }} />
                  </span>
                ))}
              </div>
            ))}
          </div>
        </div>

        <section aria-labelledby="app-title" id="app" className="mx-auto max-w-6xl px-lg py-[7rem] sm:px-xl">
          <SectionTitle id="app-title" eyebrow="O app" title="Feito para a academia, não para a planilha.">
            Cada série com a última vez ao lado, um toque para confirmar e o descanso começando
            sozinho. Depois, o histórico, o Meu Corpo e o assistente mostram o que evoluiu. As
            telas abaixo são ilustrativas, com dados de exemplo — toque para ampliar.
          </SectionTitle>
          <div className="mt-3xl grid justify-items-center gap-x-2xl gap-y-3xl sm:grid-cols-2 lg:grid-cols-3">
            {screens.map((item, i) => (
              <Reveal key={item.title} delay={(i % 3) * 120}>
                <figure className="flex max-w-[260px] flex-col items-center">
                  <ZoomablePhone title={item.title} label={item.label}>
                    {item.screen}
                  </ZoomablePhone>
                  <figcaption className="mt-lg text-center">
                    <span className="block font-display text-title-sm font-semibold">
                      {item.title}
                    </span>
                    <span className="mt-xs block text-body-sm text-site-muted">{item.text}</span>
                  </figcaption>
                </figure>
              </Reveal>
            ))}
          </div>
        </section>

        <section aria-labelledby="recursos-title" id="recursos" className="mx-auto max-w-6xl px-lg pb-[7rem] sm:px-xl">
          <SectionTitle id="recursos-title" eyebrow="Recursos" title={`O que o ${site.name} reúne`} />
          <div className="mt-3xl grid gap-lg md:grid-cols-2">
            <Feature
              eyebrow="Musculação"
              title="Fichas com técnicas de verdade"
              description="Bi-sets, superséries, tri-sets, drop set, rest-pause e aquecimento planejados na ficha e registrados no treino, com histórico, recordes e 1RM estimado por exercício."
            >
              <BisetDemo />
            </Feature>
            <Feature
              eyebrow="Cardio"
              title="Corrida, caminhada, ciclismo e natação"
              description="Distância, duração, pace ou velocidade e esforço percebido, com planos progressivos de caminhada, primeiros 5 km e 10 km marcados pelas suas atividades."
              delay={90}
            >
              <PaceDemo />
            </Feature>
            <Feature
              eyebrow="Evolução"
              title="Meu Corpo"
              description="Um mapa muscular de frente e de costas com o estímulo registrado no período, por uma metodologia transparente e versionada — referência, não diagnóstico."
            >
              <BodyDemo />
            </Feature>
            <Feature
              eyebrow="Nutrição e corpo"
              title="Alimentação, metas, peso e medidas"
              description="Refeições com calorias e macronutrientes, metas diárias com limites de segurança e a tendência do peso e das medidas, semana a semana."
              delay={90}
            >
              <NutritionDemo />
            </Feature>
            <Feature
              eyebrow="Metas"
              title="Metas medidas pelos registros"
              description="Força, corrida, frequência, hipertrofia e peso: o progresso vem do que você registrou, sem número inventado, e o painel do Início se organiza pelo seu objetivo."
            >
              <GoalsDemo />
            </Feature>
            <Feature
              eyebrow="IA contextual"
              title="Respostas a partir dos seus dados"
              description="Pergunte sobre o treino, a corrida, a alimentação ou o peso. A IA consulta seus registros, mostra o que consultou e pede confirmação antes de alterar algo."
              delay={90}
            >
              <AiDemo />
            </Feature>
          </div>
        </section>

        <section aria-labelledby="como-title" id="como-funciona" className="mx-auto max-w-6xl px-lg pb-[7rem] sm:px-xl">
          <SectionTitle id="como-title" eyebrow="Como funciona" title="Três passos, todos os dias." />
          <ol className="mt-3xl grid gap-lg md:grid-cols-3">
            {steps.map(([title, text], i) => (
              <li key={title}>
                <Reveal delay={i * 90} className="h-full">
                  <div className="h-full rounded-[28px] border border-white/10 bg-white/[0.03] p-xl">
                    <span
                      aria-hidden="true"
                      className="font-display text-[3rem] leading-none font-bold"
                      style={{ backgroundImage: STIMULUS, WebkitBackgroundClip: "text", color: "transparent" }}
                    >
                      {i + 1}
                    </span>
                    <h3 className="mt-md font-display text-title font-semibold">{title}</h3>
                    <p className="mt-sm text-body-sm leading-relaxed text-site-muted">{text}</p>
                  </div>
                </Reveal>
              </li>
            ))}
          </ol>
        </section>

        <section aria-labelledby="ia-title" id="ia" className="mx-auto max-w-6xl px-lg pb-[7rem] sm:px-xl">
          <SectionTitle id="ia-title" eyebrow="A IA" title="Fatos dos seus registros, não palpites.">
            O assistente funciona com um provedor de IA escolhido pelo servidor ou, sem internet
            e sem custo, num modo demonstração que monta as respostas por regras — e avisa
            quando é ele que responde.
          </SectionTitle>
          <ul className="mt-3xl grid gap-lg sm:grid-cols-2">
            {aiRules.map(([title, text], i) => (
              <li key={title}>
                <Reveal delay={(i % 2) * 90} className="h-full">
                  <div className="h-full rounded-[28px] border border-white/10 p-xl">
                    <h3 className="font-display text-title-sm font-semibold">{title}</h3>
                    <p className="mt-sm text-body-sm leading-relaxed text-site-muted">{text}</p>
                  </div>
                </Reveal>
              </li>
            ))}
          </ul>
        </section>

        <section aria-labelledby="privacidade-title" id="privacidade" className="mx-auto max-w-6xl px-lg pb-[7rem] sm:px-xl">
          <SectionTitle id="privacidade-title" eyebrow="Privacidade" title="Seus dados de saúde, sob seu controle.">
            O projeto segue a LGPD desde o desenho: peso, medidas, alimentação e frequência
            cardíaca são dados sensíveis.
          </SectionTitle>
          <ul className="mt-3xl grid gap-lg sm:grid-cols-2">
            {privacy.map(([title, text], i) => (
              <li key={title}>
                <Reveal delay={(i % 2) * 90} className="h-full">
                  <div className="h-full rounded-[28px] border border-white/10 p-xl">
                    <h3 className="font-display text-title-sm font-semibold">{title}</h3>
                    <p className="mt-sm text-body-sm leading-relaxed text-site-muted">{text}</p>
                  </div>
                </Reveal>
              </li>
            ))}
          </ul>
          <p className="mt-xl text-body-sm">
            <Link className="font-semibold underline underline-offset-4 hover:text-site-muted" href="/privacidade">
              Leia o aviso de privacidade completo
            </Link>
          </p>
        </section>

        <section aria-labelledby="perguntas-title" id="perguntas" className="mx-auto max-w-6xl px-lg pb-[7rem] sm:px-xl">
          <SectionTitle id="perguntas-title" eyebrow="Perguntas" title="Perguntas frequentes" />
          <div className="mt-3xl divide-y divide-white/10 border-y border-white/10">
            {faq.map((item) => (
              <details key={item.question} className="site-faq group py-lg">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-lg font-display text-title-sm font-semibold">
                  {item.question}
                  <span aria-hidden="true" className="text-site-muted transition-transform group-open:rotate-45">
                    +
                  </span>
                </summary>
                <p className="mt-md max-w-[48rem] text-body-sm leading-relaxed text-site-muted">
                  {item.answer}
                </p>
              </details>
            ))}
          </div>
        </section>

        <section aria-labelledby="fim-title" className="relative isolate overflow-hidden border-t border-white/10">
          <div
            aria-hidden="true"
            className="absolute inset-0 -z-10 opacity-40 blur-3xl"
            style={{ background: "radial-gradient(circle at 50% 120%, #3D7BFF 0%, transparent 55%)" }}
          />
          <div className="mx-auto max-w-6xl px-lg py-[7rem] sm:px-xl">
            <Reveal className="text-center">
              <h2
                id="fim-title"
                className="mx-auto max-w-4xl font-display text-[2.5rem] leading-[1] font-bold tracking-[-0.045em] text-balance sm:text-[4.5rem]"
              >
                Ninguém evolui no que{" "}
                <span className="bg-clip-text text-transparent" style={{ backgroundImage: STIMULUS }}>
                  não mede.
                </span>
              </h2>
              <p className="mx-auto mt-lg max-w-[36rem] text-body leading-relaxed text-site-muted">
                O {site.name} é um Trabalho de Conclusão de Curso em desenvolvimento, com o app
                Android funcionando contra a API real.
              </p>
            </Reveal>
            <div className="mx-auto mt-3xl grid max-w-4xl gap-lg md:grid-cols-2">
              <div className="rounded-[28px] border border-white/10 p-xl">
                <h3 className="font-display text-title-sm font-semibold">O que já funciona</h3>
                <ul className="mt-md space-y-sm text-body-sm text-site-muted">
                  {working.map((item) => (
                    <li key={item} className="flex gap-sm">
                      <span aria-hidden="true">✓</span>
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
              <div className="rounded-[28px] border border-white/10 p-xl">
                <h3 className="font-display text-title-sm font-semibold">Próximos passos</h3>
                <ul className="mt-md space-y-sm text-body-sm text-site-muted">
                  {next.map((item) => (
                    <li key={item} className="flex gap-sm">
                      <span aria-hidden="true">→</span>
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          </div>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}
