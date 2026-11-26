"use client";

import { useRef, type ReactNode } from "react";

/**
 * Menu do celular num `<details>`: abre e fecha sem JavaScript, com teclado e leitor
 * de tela. Com JavaScript, fecha ao tocar num link (achado no navegador: a âncora
 * levava à seção, mas o menu ficava aberto por cima dela) e com Esc.
 */
export function MobileMenu({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDetailsElement>(null);
  const close = () => {
    if (ref.current) ref.current.open = false;
  };
  return (
    <details
      ref={ref}
      className="site-menu relative lg:hidden"
      onClick={(event) => {
        if ((event.target as HTMLElement).closest("a")) close();
      }}
      onKeyDown={(event) => {
        if (event.key === "Escape" && ref.current?.open) {
          close();
          ref.current.querySelector("summary")?.focus();
        }
      }}
    >
      <summary className="cursor-pointer list-none rounded-pill border border-white/20 px-md py-xs text-body-sm font-semibold">
        Menu
      </summary>
      {children}
    </details>
  );
}
