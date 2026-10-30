import type { CSSProperties } from "react";

type FeatureCardProps = {
  title: string;
  description: string;
  /** Rótulo curto exibido acima do título (ex.: "Musculação"). */
  eyebrow: string;
  /** Posição na grade; define o atraso da entrada em cascata. */
  index?: number;
};

export function FeatureCard({ title, description, eyebrow, index = 0 }: FeatureCardProps) {
  const style = { animationDelay: `${240 + index * 70}ms` } satisfies CSSProperties;
  return (
    <article
      style={style}
      className="animate-enter rounded-card border border-border-subtle bg-bg-surface p-xl transition-[transform,border-color,box-shadow] duration-(--duration-base) ease-emphasized hover:-translate-y-1 hover:border-border-strong hover:shadow-[0_12px_32px_-16px_rgb(12_12_13/0.25)]"
    >
      <p className="text-caption font-semibold tracking-wider text-text-secondary uppercase">
        {eyebrow}
      </p>
      <h3 className="mt-sm font-display text-title-sm font-semibold tracking-tight">{title}</h3>
      <p className="mt-sm text-body-sm leading-relaxed text-text-secondary">{description}</p>
    </article>
  );
}
