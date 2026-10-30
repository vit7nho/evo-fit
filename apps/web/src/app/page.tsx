import { FeatureCard } from "@/components/feature-card";
import { site } from "@/lib/site";

const pillars = [
  {
    eyebrow: "Musculação",
    title: "Registro rápido, técnicas reais",
    description:
      "Fichas, séries, cargas, drop sets, bi-sets e rest-pause registrados sem trocar de tela, com histórico e recordes por exercício.",
  },
  {
    eyebrow: "Cardio",
    title: "Corrida, caminhada e mais",
    description:
      "Distância, duração, ritmo e esforço percebido, com planos progressivos para quem está começando ou buscando os primeiros 5 km.",
  },
  {
    eyebrow: "Evolução",
    title: "Meu Corpo",
    description:
      "Um mapa muscular que mostra como o estímulo registrado se distribuiu no período, com uma metodologia transparente e configurável.",
  },
  {
    eyebrow: "IA contextual",
    title: "Respostas a partir dos seus dados",
    description:
      "Pergunte sobre o seu treino, a sua corrida ou a sua alimentação. A IA consulta seus registros, separa fatos de hipóteses e pede confirmação antes de alterar algo.",
  },
] as const;

/** Marca: monograma preto com a seta de evolução (mesma arte do ícone do app). */
function Logo() {
  return (
    <span className="inline-flex items-center gap-sm">
      <span className="grid size-9 place-items-center rounded-[11px] bg-accent text-on-accent">
        <svg aria-hidden="true" viewBox="0 0 24 24" className="size-5" fill="currentColor">
          <path d="M9 5v2h6.59L4 18.59 5.41 20 17 8.41V15h2V5z" />
        </svg>
      </span>
      <span className="font-display text-title-sm font-bold tracking-tight">{site.name}</span>
    </span>
  );
}

export default function Home() {
  return (
    <main className="mx-auto w-full max-w-5xl px-lg py-2xl sm:px-xl">
      <header className="animate-enter">
        <Logo />
      </header>

      <section aria-labelledby="hero-title" className="mt-3xl max-w-[48rem] sm:mt-[6rem]">
        <p
          className="inline-flex animate-enter items-center gap-sm rounded-pill border border-border-subtle bg-bg-surface px-md py-xs text-caption text-text-secondary"
          style={{ animationDelay: "60ms" }}
        >
          <span aria-hidden="true" className="size-1.5 rounded-pill bg-success" />
          Projeto de TCC em desenvolvimento
        </p>
        <h1
          id="hero-title"
          className="mt-xl animate-enter font-display text-display-sm leading-[1.05] font-bold tracking-[-0.03em] text-balance sm:text-[3.75rem]"
          style={{ animationDelay: "120ms" }}
        >
          Sua evolução, entendida pelos seus próprios dados.
        </h1>
        <p
          className="mt-lg max-w-[40rem] animate-enter text-body leading-relaxed text-text-secondary sm:text-title-sm sm:leading-relaxed"
          style={{ animationDelay: "180ms" }}
        >
          {site.description}
        </p>
      </section>

      <section aria-labelledby="pillars-title" className="mt-3xl sm:mt-[6rem]">
        <h2 id="pillars-title" className="font-display text-title font-semibold tracking-tight">
          O que o {site.name} reúne
        </h2>
        <div className="mt-xl grid gap-lg sm:grid-cols-2">
          {pillars.map((pillar, index) => (
            <FeatureCard key={pillar.title} index={index} {...pillar} />
          ))}
        </div>
      </section>

      <footer className="mt-3xl border-t border-border-subtle pt-xl text-caption text-text-secondary">
        O {site.name} não substitui o acompanhamento de profissionais de saúde, Educação Física
        ou Nutrição.
      </footer>
    </main>
  );
}
