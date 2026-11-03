"use client";

import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";

import { cn } from "@/lib/cn";

/**
 * Aparece ao entrar na tela (uma vez). Usa IntersectionObserver em vez da animação
 * ligada à rolagem do CSS: assim funciona até no fim da página (onde a rolagem não
 * alcança o ponto de disparo) e o atraso em cascata (`delay`) vale de verdade.
 * Com "reduzir movimento", o conteúdo já aparece (CSS).
 */
export function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry?.isIntersecting) {
          setShown(true);
          observer.disconnect();
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.12 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      data-shown={shown}
      className={cn("reveal", className)}
      style={{ transitionDelay: `${delay}ms` } satisfies CSSProperties}
    >
      {children}
    </div>
  );
}
