import type { Metadata } from "next";
import Link from "next/link";

import { SiteFooter, SiteHeader, SkipLink } from "@/components/site-chrome";

export const metadata: Metadata = {
  title: "Página não encontrada",
  // A 404 não entra nos buscadores.
  robots: { index: false },
};

/** Página não encontrada, no tom do site (e com o caminho de volta). */
export default function NotFound() {
  return (
    <div className="site flex min-h-full flex-col overflow-x-clip">
      <SkipLink />
      <SiteHeader onHome={false} />
      <main
        id="conteudo"
        className="mx-auto flex w-full max-w-[48rem] flex-1 flex-col justify-center px-lg pt-[8rem] pb-[6rem] sm:px-xl"
      >
        <p className="text-caption font-semibold tracking-[0.2em] text-site-muted uppercase">
          Erro 404
        </p>
        <h1 className="mt-md font-display text-[2.5rem] leading-[1.05] font-bold tracking-[-0.035em]">
          Esta página não existe.
        </h1>
        <p className="mt-lg text-body text-site-muted">
          O endereço pode ter mudado. Comece pela página inicial.
        </p>
        <p className="mt-xl">
          <Link
            href="/"
            className="inline-block rounded-pill bg-white px-xl py-md text-body-sm font-semibold text-black"
          >
            Ir para o início
          </Link>
        </p>
      </main>
      <SiteFooter onHome={false} />
    </div>
  );
}
