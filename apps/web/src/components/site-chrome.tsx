import Link from "next/link";

import { site } from "@/lib/site";

import { MobileMenu } from "./mobile-menu";

/** Seções da página inicial, na ordem do menu. */
export const sections = [
  { id: "app", label: "O app" },
  { id: "recursos", label: "Recursos" },
  { id: "como-funciona", label: "Como funciona" },
  { id: "ia", label: "A IA" },
  { id: "privacidade", label: "Privacidade" },
  { id: "perguntas", label: "Perguntas" },
] as const;

/** Marca: monograma com a seta de evolução (mesma arte do ícone do app). */
export function Logo() {
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

/** Links das seções: âncoras na página inicial, `/#id` nas outras páginas. */
function sectionHref(id: string, onHome: boolean) {
  return onHome ? `#${id}` : `/#${id}`;
}

export function SkipLink() {
  return (
    <a
      href="#conteudo"
      className="sr-only focus:not-sr-only focus:fixed focus:top-md focus:left-md focus:z-50 focus:rounded-pill focus:bg-white focus:px-lg focus:py-sm focus:text-black"
    >
      Pular para o conteúdo
    </a>
  );
}

/**
 * Cabeçalho fixo. No celular, o menu abre num `<details>` (MobileMenu): funciona sem JavaScript,
 * com teclado e com leitor de tela (o resumo é um botão nativo).
 */
export function SiteHeader({ onHome = true }: { onHome?: boolean }) {
  return (
    <header className="fixed inset-x-0 top-0 z-40 border-b border-white/[0.06] bg-black/60 backdrop-blur-xl">
      <nav
        aria-label="Principal"
        className="mx-auto flex max-w-6xl items-center justify-between gap-lg px-lg py-md sm:px-xl"
      >
        <Link href="/" aria-label={`${site.name}, início`}>
          <Logo />
        </Link>
        <ul className="hidden items-center gap-lg text-body-sm text-site-muted lg:flex">
          {sections.map((s) => (
            <li key={s.id}>
              <a className="transition-colors hover:text-white" href={sectionHref(s.id, onHome)}>
                {s.label}
              </a>
            </li>
          ))}
        </ul>
        <span className="hidden rounded-pill border border-white/15 px-md py-xs text-caption text-site-muted sm:inline">
          Projeto de TCC em desenvolvimento
        </span>
        <MobileMenu>
          <ul className="absolute right-0 mt-sm w-56 space-y-xs rounded-[20px] border border-white/10 bg-[#0d0d11] p-sm text-body-sm shadow-[0_24px_60px_-20px_rgba(0,0,0,0.9)]">
            {sections.map((s) => (
              <li key={s.id}>
                <a
                  className="block rounded-[12px] px-md py-sm hover:bg-white/10"
                  href={sectionHref(s.id, onHome)}
                >
                  {s.label}
                </a>
              </li>
            ))}
          </ul>
        </MobileMenu>
      </nav>
    </header>
  );
}

export function SiteFooter({ onHome = true }: { onHome?: boolean }) {
  return (
    <footer className="border-t border-white/10">
      <div className="mx-auto grid max-w-6xl gap-xl px-lg py-2xl text-caption text-site-muted sm:px-xl md:grid-cols-[1fr_auto]">
        <div className="space-y-md">
          <Logo />
          <p className="max-w-[36rem]">
            O {site.name} não substitui o acompanhamento de profissionais de saúde, Educação
            Física ou Nutrição. As telas mostradas neste site são ilustrativas, com dados de
            exemplo.
          </p>
          <p>Projeto de Trabalho de Conclusão de Curso, em desenvolvimento.</p>
        </div>
        <nav aria-label="Rodapé">
          <ul className="grid grid-cols-2 gap-x-xl gap-y-sm">
            {sections.map((s) => (
              <li key={s.id}>
                <a className="hover:text-white" href={sectionHref(s.id, onHome)}>
                  {s.label}
                </a>
              </li>
            ))}
            <li>
              <Link className="hover:text-white" href="/privacidade">
                Aviso de privacidade
              </Link>
            </li>
          </ul>
        </nav>
      </div>
    </footer>
  );
}
