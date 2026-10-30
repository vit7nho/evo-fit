type FeatureCardProps = {
  title: string;
  description: string;
  /** Rótulo curto exibido acima do título (ex.: "Musculação"). */
  eyebrow: string;
};

export function FeatureCard({ title, description, eyebrow }: FeatureCardProps) {
  return (
    <article className="rounded-card border border-border-subtle bg-bg-surface p-xl">
      <p className="text-caption font-medium tracking-wide text-accent uppercase">{eyebrow}</p>
      <h3 className="mt-sm font-display text-title-sm font-semibold">{title}</h3>
      <p className="mt-sm text-body-sm leading-relaxed text-text-secondary">{description}</p>
    </article>
  );
}
