import Link from "next/link";
import { Fragment, type CSSProperties, type ReactNode } from "react";

import { Reveal } from "@/components/motion";
import { HistoryScreen, RecordsScreen, SessionScreen } from "@/components/phone";
import { ZoomablePhone } from "@/components/phone-zoom";
import AnimatedGradient from "@/components/spell/animated-gradient";
import { site } from "@/lib/site";

/** Cores do mapa de estímulo do app (pouco, médio, muito): a paleta do site. */
const STIMULUS = "linear-gradient(90deg, #3D7BFF 0%, #F28C28 55%, #E5484D 100%)";

const techniques = [
  "Bi-set",
  "Supersérie",
  "Drop set",
  "Rest-pause",
  "Até a falha",
  "Aquecimento",
  "Recordes pessoais",
  "1RM estimado",
  "Descanso automático",
  "Histórico por exercício",
];

/** Marca: monograma com a seta de evolução (mesma arte do ícone do app). */
function Logo() {
  return (
    <span className="inline-flex items-center gap-sm">
      <span className="grid size-9 place-items-center rounded-[11px] bg-white text-black">
        <svg aria-hidden="true" viewBox="0 0 24 24" className="size-5" fill="currentColor">
          <path d="M9 5v2h6.59L4 18.59 5.41 20 17 8.41V15h2V5z" />
        </svg>
      </span>
      <span className="font-display text-title-sm font-bold tracking-tight">{site.name}</span>
    </span>
  );
}

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

function Soon() {
  return (
    <span className="rounded-pill border border-white/15 px-sm py-[2px] text-[0.6875rem] font-semibold text-site-muted">
      Em breve
    </span>
  );
}

/** Cartão de recurso: a demonstração em cima, o texto embaixo. */
function Feature({
  eyebrow,
  title,
  description,
  soon = false,
  delay = 0,
  children,
}: {
  eyebrow: string;
  title: string;
  description: string;
  soon?: boolean;
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
          <div className="flex flex-wrap items-center gap-sm">
            <Eyebrow>{eyebrow}</Eyebrow>
            {soon && <Soon />}
          </div>
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

/** Ritmo de uma corrida (linha) — recurso das próximas fases. */
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
        5 km · 5:42 /km
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

/** Conversa com a IA a partir dos dados do treino. */
function AiDemo() {
  return (
    <div className="w-full max-w-[20rem] space-y-sm text-body-sm">
      <p className="ml-auto w-fit rounded-[18px] rounded-br-[6px] bg-white px-md py-sm text-black">
        Como foi meu supino este mês?
      </p>
      <p className="w-fit rounded-[18px] rounded-bl-[6px] bg-white/[0.08] px-md py-sm">
        Sua carga subiu de 60 para 62,5 kg em 8 repetições — um recorde no dia 3. O volume
        semanal ficou estável.
      </p>
      <p className="text-caption text-site-muted">Baseado nos seus registros · fatos, não palpites</p>
    </div>
  );
}

export default function Home() {
  return (
    <div className="site overflow-x-clip">
      <a
        href="#conteudo"
        className="sr-only focus:not-sr-only focus:fixed focus:top-md focus:left-md focus:z-50 focus:rounded-pill focus:bg-white focus:px-lg focus:py-sm focus:text-black"
      >
        Pular para o conteúdo
      </a>

      <header className="fixed inset-x-0 top-0 z-40 border-b border-white/[0.06] bg-black/40 backdrop-blur-xl">
        <nav
          aria-label="Principal"
          className="mx-auto flex max-w-6xl items-center justify-between gap-lg px-lg py-md sm:px-xl"
        >
          <Link href="/" aria-label={`${site.name}, início`}>
            <Logo />
          </Link>
          <ul className="hidden items-center gap-xl text-body-sm text-site-muted md:flex">
            <li>
              <a className="transition-colors hover:text-white" href="#app">
                O app
              </a>
            </li>
            <li>
              <a className="transition-colors hover:text-white" href="#recursos">
                Recursos
              </a>
            </li>
          </ul>
          <span className="rounded-pill border border-white/15 px-md py-xs text-caption text-site-muted">
            Projeto de TCC em desenvolvimento
          </span>
        </nav>
      </header>

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
                a trilha anda exatamente uma cópia (−50%) e a volta não pula. Cada cópia
                repete a lista duas vezes para ser mais larga que qualquer tela (senão
                sobra um vão no fim). */}
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

        <section
          aria-labelledby="app-title"
          id="app"
          className="mx-auto max-w-6xl px-lg py-[7rem] sm:px-xl"
        >
          <Reveal className="max-w-[48rem]">
            <Eyebrow>O app</Eyebrow>
            <h2
              id="app-title"
              className="mt-md font-display text-[2.25rem] leading-[1.02] font-bold tracking-[-0.035em] sm:text-[3.5rem]"
            >
              Feito para a academia, não para a planilha.
            </h2>
            <p className="mt-lg max-w-[42rem] text-body leading-relaxed text-site-muted">
              Cada série com a última vez ao lado, um toque para confirmar, o tipo da série no
              próprio número e o descanso começando sozinho. Depois, o histórico mostra o que
              evoluiu.
            </p>
          </Reveal>
          <div className="mt-3xl flex flex-wrap items-start justify-center gap-2xl lg:justify-between">
            {[
              {
                title: "Registro em tabela",
                text: "A, 1, F, D, RP: aquecimento, válida, falha, drop e rest-pause no número da série.",
                screen: <SessionScreen />,
                label: "Tela do treino com a tabela de séries.",
              },
              {
                title: "Histórico",
                text: "Cada treino com duração, séries, volume e os recordes que caíram.",
                screen: <HistoryScreen />,
                label: "Tela do histórico com treinos concluídos e selo de recordes.",
              },
              {
                title: "Recordes",
                text: "Maior carga, 1RM estimado e a melhor carga para cada número de repetições.",
                screen: <RecordsScreen />,
                label: "Tela de recordes de um exercício com a melhor carga por repetições.",
              },
            ].map((item, i) => (
              <Reveal key={item.title} delay={i * 120}>
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

        <section
          aria-labelledby="recursos-title"
          id="recursos"
          className="mx-auto max-w-6xl px-lg pb-[7rem] sm:px-xl"
        >
          <Reveal className="max-w-[48rem]">
            <Eyebrow>Recursos</Eyebrow>
            <h2
              id="recursos-title"
              className="mt-md font-display text-[2.25rem] leading-[1.02] font-bold tracking-[-0.035em] sm:text-[3.5rem]"
            >
              O que o {site.name} reúne
            </h2>
          </Reveal>
          <div className="mt-3xl grid gap-lg md:grid-cols-2">
            <Feature
              eyebrow="Musculação"
              title="Fichas com técnicas de verdade"
              description="Bi-sets, superséries, tri-sets, drop set, rest-pause e aquecimento planejados na ficha e registrados no treino, com histórico e recordes por exercício."
            >
              <BisetDemo />
            </Feature>
            <Feature
              eyebrow="Cardio"
              title="Corrida, caminhada e mais"
              description="Distância, duração, ritmo e esforço percebido, com planos progressivos para quem está começando ou buscando os primeiros 5 km."
              soon
              delay={90}
            >
              <PaceDemo />
            </Feature>
            <Feature
              eyebrow="Evolução"
              title="Meu Corpo"
              description="Um mapa muscular que mostra como o estímulo registrado se distribuiu no período, com uma metodologia transparente e configurável."
              soon
            >
              <BodyDemo />
            </Feature>
            <Feature
              eyebrow="IA contextual"
              title="Respostas a partir dos seus dados"
              description="Pergunte sobre o seu treino, a sua corrida ou a sua alimentação. A IA consulta seus registros, separa fatos de hipóteses e pede confirmação antes de alterar algo."
              soon
              delay={90}
            >
              <AiDemo />
            </Feature>
          </div>
        </section>

        <section
          aria-labelledby="fim-title"
          className="relative isolate overflow-hidden border-t border-white/10"
        >
          <div
            aria-hidden="true"
            className="absolute inset-0 -z-10 opacity-40 blur-3xl"
            style={{ background: "radial-gradient(circle at 50% 120%, #3D7BFF 0%, transparent 55%)" }}
          />
          <div className="mx-auto max-w-6xl px-lg py-[7rem] text-center sm:px-xl">
            <Reveal>
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
                O {site.name} está em desenvolvimento como Trabalho de Conclusão de Curso: o
                registro de treinos já funciona no app Android; cardio, Meu Corpo, nutrição e IA
                vêm nas próximas fases.
              </p>
            </Reveal>
          </div>
        </section>
      </main>

      <footer className="border-t border-white/10">
        <div className="mx-auto flex max-w-6xl flex-col gap-md px-lg py-xl text-caption text-site-muted sm:flex-row sm:items-center sm:justify-between sm:px-xl">
          <Logo />
          <p>
            O {site.name} não substitui o acompanhamento de profissionais de saúde, Educação
            Física ou Nutrição.
          </p>
        </div>
      </footer>
    </div>
  );
}
