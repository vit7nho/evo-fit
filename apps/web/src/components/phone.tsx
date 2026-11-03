import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

/**
 * Moldura de celular com uma tela do app recriada em HTML (as cores e a tipografia
 * do app, que é claro e monocromático). Para o leitor de tela, a tela inteira é uma
 * imagem com descrição: os textos de dentro são decorativos.
 */
export function Phone({
  label,
  children,
  className,
}: {
  label: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      role="img"
      aria-label={label}
      className={cn(
        "relative w-[260px] shrink-0 rounded-[42px] border border-white/15 bg-[#111114] p-[10px] shadow-[0_40px_120px_-30px_rgba(61,123,255,0.45)]",
        className,
      )}
    >
      <div
        aria-hidden="true"
        className="relative h-[540px] overflow-hidden rounded-[32px] bg-bg-base text-text-primary"
      >
        <div className="flex items-center justify-between px-5 pt-3 text-[10px] font-semibold">
          <span>9:41</span>
          <span className="h-[18px] w-[72px] rounded-pill bg-[#111114]" />
          <span>100%</span>
        </div>
        {children}
      </div>
    </div>
  );
}

function AppBar({ title }: { title: string }) {
  return (
    <div className="flex items-center gap-3 px-4 pt-3 pb-2">
      <span className="text-lg leading-none">←</span>
      <span className="truncate font-display text-[17px] font-bold tracking-tight">{title}</span>
    </div>
  );
}

function Badge({ text, done }: { text: string; done?: boolean }) {
  const letter = Number.isNaN(Number(text));
  return (
    <span
      className={cn(
        "grid size-[26px] shrink-0 place-items-center rounded-pill text-[11px] font-bold",
        letter
          ? "border border-border-strong bg-bg-surface text-text-primary"
          : "bg-accent text-on-accent",
        done && !letter && "bg-accent",
      )}
    >
      {text}
    </span>
  );
}

const sessionRows: Array<{ badge: string; before: string; kg: string; reps: string; done: boolean }> =
  [
    { badge: "A", before: "20 × 15", kg: "20", reps: "15", done: true },
    { badge: "1", before: "60 × 10", kg: "60", reps: "10", done: true },
    { badge: "F", before: "60 × 8", kg: "62,5", reps: "8", done: true },
    { badge: "D", before: "45 × 6", kg: "50", reps: "6", done: true },
    { badge: "3", before: "60 × 8", kg: "60", reps: "8", done: false },
  ];

/** Tela do treino em andamento: resumo, tabela de séries, descanso. */
export function SessionScreen() {
  return (
    <>
      <AppBar title="Treino A" />
      <div className="mx-0 grid grid-cols-3 gap-2 bg-bg-elevated px-4 py-2">
        {[
          ["Duração", "32:14"],
          ["Volume", "3.420 kg"],
          ["Séries", "9"],
        ].map(([label, value]) => (
          <div key={label}>
            <p className="text-[9px] text-text-secondary">{label}</p>
            <p className="font-display text-[13px] font-bold">{value}</p>
          </div>
        ))}
      </div>
      <div className="m-3 rounded-[18px] bg-bg-surface p-3">
        <p className="font-display text-[13px] font-semibold">Supino reto com barra</p>
        <div className="mt-2 flex gap-1.5">
          <span className="rounded-pill border border-border-subtle px-2 py-0.5 text-[9px]">
            ⏱ Descanso: 1 min 30 s
          </span>
          <span className="rounded-pill border border-border-subtle px-2 py-0.5 text-[9px]">
            ✎ Nota
          </span>
        </div>
        <div className="mt-3 grid grid-cols-[30px_1fr_44px_40px_26px] items-center gap-1 text-[8px] font-semibold text-text-secondary">
          <span>SÉRIE</span>
          <span className="text-center">ANTERIOR</span>
          <span className="text-center">KG</span>
          <span className="text-center">REPS</span>
          <span className="text-center">✓</span>
        </div>
        {sessionRows.map((row) => (
          <div
            key={row.badge}
            className={cn(
              "mt-1 grid grid-cols-[30px_1fr_44px_40px_26px] items-center gap-1 rounded-[10px] py-1",
              row.done && "bg-bg-elevated",
            )}
          >
            <Badge text={row.badge} done={row.done} />
            <span className="text-center text-[10px] text-text-secondary">{row.before}</span>
            <span
              className={cn(
                "rounded-[8px] py-1 text-center text-[11px]",
                row.done ? "bg-bg-surface" : "bg-bg-elevated text-text-secondary",
              )}
            >
              {row.kg}
            </span>
            <span
              className={cn(
                "rounded-[8px] py-1 text-center text-[11px]",
                row.done ? "bg-bg-surface" : "bg-bg-elevated text-text-secondary",
              )}
            >
              {row.reps}
            </span>
            <span
              className={cn(
                "grid size-[22px] place-items-center rounded-pill text-[11px]",
                row.done ? "bg-success text-white" : "border border-text-primary",
              )}
            >
              ✓
            </span>
          </div>
        ))}
        <div className="mt-2 rounded-pill border border-border-strong py-1.5 text-center text-[10px] font-semibold">
          + Adicionar série
        </div>
      </div>
      <div className="absolute inset-x-0 bottom-0">
        <div className="flex items-center justify-between bg-accent px-4 py-2.5 text-on-accent">
          <span className="font-display text-[13px] font-bold">Descanso 01:12</span>
          <span className="text-[10px] font-semibold">−15 · +15 · Pular</span>
        </div>
        <div className="bg-bg-base px-4 py-3">
          <div className="rounded-pill bg-accent py-2.5 text-center text-[11px] font-semibold text-on-accent">
            ⚑ Finalizar treino
          </div>
        </div>
      </div>
    </>
  );
}

/** Tela do histórico: treinos concluídos com resumo e selo de recordes. */
export function HistoryScreen() {
  const items = [
    {
      date: "seg., 3 de nov.",
      name: "Treino A — Peito",
      details: "48 min · 14 séries · 3.420 kg",
      records: 2,
    },
    { date: "sáb., 1 de nov.", name: "Treino B — Costas", details: "52 min · 16 séries · 4.110 kg", records: 0 },
    { date: "qui., 30 de out.", name: "Treino C — Pernas", details: "61 min · 18 séries · 6.780 kg", records: 1 },
  ];
  return (
    <>
      <AppBar title="Histórico" />
      <div className="flex border-b border-border-subtle text-[11px] font-semibold">
        <span className="flex-1 border-b-2 border-text-primary py-2 text-center">Treinos</span>
        <span className="flex-1 py-2 text-center text-text-secondary">Recordes</span>
      </div>
      <div className="space-y-2.5 p-3">
        {items.map((item) => (
          <div key={item.name} className="rounded-[18px] border border-border-subtle bg-bg-surface p-3">
            <p className="text-[9px] text-text-secondary">{item.date}</p>
            <p className="mt-0.5 font-display text-[13px] font-semibold">{item.name}</p>
            <p className="mt-0.5 text-[10px] text-text-secondary">{item.details}</p>
            {item.records > 0 && (
              <span className="mt-2 inline-flex items-center gap-1 rounded-pill bg-accent px-2 py-0.5 text-[9px] text-on-accent">
                🏆 {item.records === 1 ? "1 recorde" : `${item.records} recordes`}
              </span>
            )}
          </div>
        ))}
      </div>
    </>
  );
}

/** Tela do histórico de um exercício: recordes e melhor carga por repetições. */
export function RecordsScreen() {
  return (
    <>
      <AppBar title="Supino reto com barra" />
      <div className="px-4 pt-1">
        <p className="font-display text-[13px] font-semibold">Recordes</p>
        <div className="mt-2 grid grid-cols-2 gap-3">
          {[
            ["Maior carga", "62,5 kg × 8"],
            ["1RM estimado", "80 kg"],
            ["Maior volume num treino", "1.080 kg"],
          ].map(([label, value]) => (
            <div key={label}>
              <p className="text-[9px] text-text-secondary">{label}</p>
              <p className="font-display text-[13px] font-bold">{value}</p>
            </div>
          ))}
        </div>
        <p className="mt-2 text-[8px] text-text-secondary">
          O 1RM é uma estimativa (fórmula de Epley).
        </p>
        <p className="mt-4 font-display text-[13px] font-semibold">Melhor carga por repetições</p>
        {[
          ["1 rep.", "75 kg"],
          ["5 rep.", "67,5 kg"],
          ["8 rep.", "62,5 kg"],
          ["10 rep.", "60 kg"],
          ["12 rep.", "55 kg"],
        ].map(([reps, load]) => (
          <div key={reps} className="mt-1.5 flex justify-between border-b border-border-subtle pb-1.5 text-[11px]">
            <span className="text-text-secondary">{reps}</span>
            <span className="font-semibold">{load}</span>
          </div>
        ))}
        <div className="mt-4 rounded-[18px] border border-border-subtle bg-bg-surface p-3">
          <p className="text-[9px] text-text-secondary">seg., 3 de nov. · Treino A</p>
          <div className="mt-1.5 flex items-center gap-2 text-[11px]">
            <Badge text="F" /> 62,5 kg × 8
          </div>
          <div className="mt-1 flex items-center gap-2 pl-5 text-[11px]">
            <Badge text="D" /> 50 kg × 6
          </div>
          <span className="mt-2 inline-flex rounded-pill bg-accent px-2 py-0.5 text-[9px] text-on-accent">
            🏆 Maior carga
          </span>
        </div>
      </div>
    </>
  );
}
