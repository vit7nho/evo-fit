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

export default function Home() {
  return (
    <main className="mx-auto w-full max-w-5xl px-lg py-3xl sm:px-xl">
      <section aria-labelledby="hero-title" className="max-w-3xl">
        <p className="inline-flex rounded-pill border border-border-subtle px-md py-xs text-caption text-text-secondary">
          Projeto de TCC em desenvolvimento
        </p>
        <h1
          id="hero-title"
          className="mt-xl font-display text-display-sm leading-tight font-bold tracking-tight sm:text-display"
        >
          Sua evolução, entendida pelos seus próprios dados.
        </h1>
        <p className="mt-lg text-body leading-relaxed text-text-secondary">{site.description}</p>
      </section>

      <section aria-labelledby="pillars-title" className="mt-3xl">
        <h2 id="pillars-title" className="font-display text-title font-semibold">
          O que o {site.name} reúne
        </h2>
        <div className="mt-xl grid gap-lg sm:grid-cols-2">
          {pillars.map((pillar) => (
            <FeatureCard key={pillar.title} {...pillar} />
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
