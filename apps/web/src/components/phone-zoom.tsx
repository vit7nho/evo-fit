"use client";

import { useRef, useState, type ReactNode } from "react";

import { Phone } from "./phone";
import { TiltCard } from "./spell/tilt-card";

/** Altura da moldura do celular (tela de 540px + borda). */
const PHONE_HEIGHT = 562;

/**
 * Celular que, ao ser clicado, abre a tela ampliada numa janela por cima do site.
 * Usa o `<dialog>` do navegador: o foco fica dentro dela, Esc fecha e o leitor de
 * tela anuncia. Fecha também pelo X ou clicando fora do celular. A ampliação se
 * ajusta à altura da tela (até 1,7×).
 */
export function ZoomablePhone({
  label,
  title,
  tiltLimit = 8,
  children,
}: {
  /** Descrição da tela para o leitor de tela. */
  label: string;
  /** Nome curto da tela ("Registro em tabela"), para o botão e a janela. */
  title: string;
  tiltLimit?: number;
  children: ReactNode;
}) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [scale, setScale] = useState(1.5);

  const open = () => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    setScale(Math.max(1, Math.min(1.7, (window.innerHeight - 96) / PHONE_HEIGHT)));
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
  };

  const close = () => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (typeof dialog.close === "function") dialog.close();
    else dialog.removeAttribute("open");
  };

  return (
    <>
      <button
        type="button"
        aria-haspopup="dialog"
        aria-label={`Ampliar a tela: ${title}`}
        onClick={open}
        className="group block cursor-zoom-in rounded-[42px] text-left"
      >
        <TiltCard tiltLimit={tiltLimit} scale={1.02} effect="gravitate" className="rounded-[42px]">
          <Phone label={label}>{children}</Phone>
        </TiltCard>
        <span
          aria-hidden="true"
          className="pointer-events-none mt-sm block text-center text-caption text-site-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
        >
          Clique para ampliar
        </span>
      </button>

      <dialog
        ref={dialogRef}
        aria-label={title}
        onClick={(event) => {
          // Clique no fundo (fora do celular) fecha.
          if (event.target === event.currentTarget) close();
        }}
        className="phone-dialog fixed inset-0 m-0 h-full max-h-none w-full max-w-none bg-transparent p-0 text-white backdrop:bg-black/80 backdrop:backdrop-blur-md"
      >
        <div className="pointer-events-none flex h-full w-full items-center justify-center">
          <div
            className="pointer-events-auto"
            style={{ width: 260 * scale, height: PHONE_HEIGHT * scale }}
          >
            <div className="origin-top-left" style={{ transform: `scale(${scale})` }}>
              <Phone label={label}>{children}</Phone>
            </div>
          </div>
        </div>
        <button
          type="button"
          onClick={close}
          aria-label="Fechar"
          className="fixed top-lg right-lg grid size-11 place-items-center rounded-pill border border-white/20 bg-black/60 text-title-sm backdrop-blur transition-colors hover:bg-white/15"
        >
          ×
        </button>
        <p className="fixed inset-x-0 bottom-lg text-center text-caption text-site-muted">
          {title} · Esc ou clique fora para fechar
        </p>
      </dialog>
    </>
  );
}
