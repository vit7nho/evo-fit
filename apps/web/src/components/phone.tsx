import type { ReactNode } from "react";

import { cn } from "@/lib/cn";

/** O que o mockup avisa, na imagem e no leitor de tela: não são dados de verdade. */
export const EXAMPLE_NOTE = "Tela ilustrativa, com dados de exemplo.";

/**
 * Moldura de celular com uma tela do app recriada em HTML (as cores e a tipografia
 * do app, que é claro e monocromático). Para o leitor de tela, a tela inteira é uma
 * imagem com descrição: os textos de dentro são decorativos. Toda tela leva o rótulo
 * "Dados de exemplo" (5.5): os números não são de uma pessoa real.
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
      aria-label={`${label} ${EXAMPLE_NOTE}`}
      className={cn("w-[260px] shrink-0", className)}
    >
      {/* No fluxo, acima da moldura: posicionado por fora, o cartão que inclina o cortava. */}
      <span
        aria-hidden="true"
        className="mx-auto mb-[6px] block h-[18px] w-fit rounded-pill border border-white/20 px-sm text-[0.625rem] leading-[16px] font-semibold tracking-wide whitespace-nowrap text-site-muted uppercase"
      >
        Dados de exemplo
      </span>
      <div className="relative rounded-[42px] border border-white/15 bg-[#111114] p-[10px] shadow-[0_40px_120px_-30px_rgba(61,123,255,0.45)]">
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

function Chips({ items, selected }: { items: string[]; selected: string }) {
  return (
    <div className="flex gap-1.5 px-4">
      {items.map((item) => (
        <span
          key={item}
          className={cn(
            "rounded-pill border px-2 py-0.5 text-[9px] font-semibold",
            item === selected ? "border-accent bg-accent text-on-accent" : "border-border-subtle",
          )}
        >
          {item}
        </span>
      ))}
    </div>
  );
}

/** Meu Corpo: o mapa da frente pelas faixas de estímulo e a lista por músculo. */
export function BodyScreen() {
  // Silhueta simplificada: cada região na cor da faixa (nada, pouco, médio, muito).
  const parts: Array<[string, string]> = [
    ["M88 30a12 12 0 1 0 24 0a12 12 0 1 0 -24 0", "var(--color-stimulus-none)"],
    ["M70 52h60l-6 46H76z", "var(--color-stimulus-high)"],
    ["M52 56l16-4 4 40-14 4z", "var(--color-stimulus-mid)"],
    ["M148 56l-16-4-4 40 14 4z", "var(--color-stimulus-mid)"],
    ["M76 100h48l-4 26H80z", "var(--color-stimulus-low)"],
    ["M80 128h18l-2 60H82z", "var(--color-stimulus-mid)"],
    ["M102 128h18l-2 60h-14z", "var(--color-stimulus-mid)"],
  ];
  const rows: Array<[string, string, string, string]> = [
    ["Peito", "11,5", "var(--color-stimulus-high)", "Alta"],
    ["Ombros", "7", "var(--color-stimulus-mid)", "Moderada"],
    ["Abdômen", "3", "var(--color-stimulus-low)", "Baixa"],
    ["Panturrilhas", "0", "var(--color-stimulus-none)", "Nenhuma"],
  ];
  return (
    <>
      <AppBar title="Meu Corpo" />
      <Chips items={["7 dias", "30 dias", "90 dias"]} selected="30 dias" />
      <div className="flex justify-center py-2">
        <svg viewBox="40 14 120 180" className="h-[190px]">
          {parts.map(([d, fill]) => (
            <path key={d} d={d} fill={fill} />
          ))}
        </svg>
      </div>
      <div className="mx-3 space-y-1.5 rounded-[18px] bg-bg-surface p-3">
        <div className="flex gap-2 text-[8px] font-semibold text-text-secondary">
          <span className="flex-1">Músculo</span>
          <span>Séries/semana</span>
          <span className="w-[46px] text-right">Faixa</span>
        </div>
        {rows.map(([name, sets, color, band]) => (
          <div key={name} className="flex items-center gap-2 text-[10px]">
            <span className="size-2.5 rounded-pill" style={{ background: color }} />
            <span className="min-w-0 flex-1 truncate font-semibold">{name}</span>
            <span className="whitespace-nowrap text-text-secondary">{sets}</span>
            <span className="w-[46px] text-right whitespace-nowrap text-text-secondary">{band}</span>
          </div>
        ))}
      </div>
      <p className="px-4 pt-2 text-[8px] text-text-secondary">
        Referência pelo volume registrado (metodologia v2), não um diagnóstico.
      </p>
    </>
  );
}

/** Peso e medidas: o último valor, a variação, o ritmo e a linha das pesagens. */
export function WeightScreen() {
  const points = [80, 79.4, 78.9, 78.1, 77.6];
  const x = (i: number) => 12 + i * 52;
  const y = (v: number) => 14 + (80.5 - v) * 34;
  const line = points.map((v, i) => `${i ? "L" : "M"}${x(i)} ${y(v)}`).join(" ");
  return (
    <>
      <AppBar title="Peso e medidas" />
      <Chips items={["Peso", "Cintura"]} selected="Peso" />
      <div className="m-3 rounded-[18px] bg-bg-surface p-3">
        <p className="text-[9px] font-semibold">Peso</p>
        <p className="font-display text-[26px] leading-tight font-bold">77,6 kg</p>
        <p className="text-[9px] text-text-secondary">em seg., 23 de nov.</p>
        <p className="mt-2 text-[10px] font-semibold">−2,4 kg desde 26 de out.</p>
        <p className="text-[9px] text-text-secondary">Ritmo: −0,6 kg por semana</p>
        <svg viewBox="0 0 230 110" className="mt-2 w-full">
          {[y(80), y(78.5)].map((v) => (
            <line key={v} x1="0" x2="230" y1={v} y2={v} stroke="var(--color-border-subtle)" />
          ))}
          <path d={line} fill="none" stroke="var(--color-accent)" strokeWidth="2.5" />
          {points.map((v, i) => (
            <circle key={i} cx={x(i)} cy={y(v)} r="3.5" fill="var(--color-accent)" />
          ))}
        </svg>
        <div className="flex justify-between text-[8px] text-text-secondary">
          {["26/10", "2/11", "9/11", "16/11", "23/11"].map((d) => (
            <span key={d}>{d}</span>
          ))}
        </div>
      </div>
      <div className="mx-3 rounded-[18px] border border-border-subtle bg-bg-surface p-3 text-[10px]">
        <p className="font-semibold">seg., 23 de nov. · 07:00</p>
        <p className="text-text-secondary">Peso 77,6 kg · Cintura 87 cm</p>
      </div>
    </>
  );
}

/** Nutrição: o total do dia contra as metas e uma refeição. */
export function NutritionScreen() {
  const macros: Array<[string, string, string, number]> = [
    ["Proteína", "53 g", "de 120 g", 0.44],
    ["Carboidratos", "156 g", "de 200 g", 0.78],
    ["Gordura", "38 g", "de 60 g", 0.63],
  ];
  return (
    <>
      <AppBar title="Nutrição" />
      <p className="text-center font-display text-[13px] font-semibold">Hoje</p>
      <div className="m-3 rounded-[18px] bg-bg-surface p-3">
        <p className="text-center">
          <span className="font-display text-[24px] font-bold">1.240 kcal</span>
          <span className="text-[11px] text-text-secondary"> de 1.800</span>
        </p>
        <div className="mt-1.5 h-1.5 rounded-pill bg-bg-elevated">
          <div className="h-full w-[69%] rounded-pill bg-accent" />
        </div>
        <p className="mt-1 text-center text-[9px] text-text-secondary">
          Faltam 560 kcal para a meta
        </p>
        <div className="mt-3 grid grid-cols-3 gap-2 text-center">
          {macros.map(([label, value, target, ratio]) => (
            <div key={label}>
              <p className="font-display text-[13px] font-bold">{value}</p>
              <p className="text-[8px] text-text-secondary">{target}</p>
              <div className="mx-1 mt-1 h-1 rounded-pill bg-bg-elevated">
                <div
                  className="h-full rounded-pill bg-accent"
                  style={{ width: `${Math.round(ratio * 100)}%` }}
                />
              </div>
              <p className="mt-1 text-[8px] text-text-secondary">{label}</p>
            </div>
          ))}
        </div>
      </div>
      <div className="mx-3 rounded-[18px] bg-bg-surface p-3">
        <div className="flex justify-between font-display text-[12px] font-semibold">
          <span>Almoço · 12:30</span>
          <span>495 kcal</span>
        </div>
        <p className="mt-1 text-[10px] text-text-secondary">Arroz branco cozido · 200 g · 256 kcal</p>
        <p className="text-[10px] text-text-secondary">Frango grelhado · 150 g · 239 kcal</p>
        <p className="mt-1 text-[8px] text-text-secondary">P 53 g · C 56,2 g · G 4,2 g</p>
      </div>
    </>
  );
}

/** Assistente: pergunta, resposta com os números dos registros, o que foi consultado
 * e uma proposta que só vale depois de confirmada. */
export function CoachScreen() {
  return (
    <>
      <AppBar title="Conversa geral" />
      <p className="px-4 text-[8px] text-text-secondary">
        As respostas usam só os seus registros e podem conter erros. Não substituem
        orientação de um profissional de saúde.
      </p>
      <div className="space-y-2 p-3">
        <p className="ml-auto w-fit max-w-[85%] rounded-[16px] rounded-br-[6px] bg-accent px-3 py-2 text-[10px] text-on-accent">
          Como foi minha semana de treinos?
        </p>
        <div className="max-w-[92%] rounded-[16px] rounded-bl-[6px] border border-border-subtle bg-bg-surface px-3 py-2 text-[10px] leading-relaxed">
          <p>Nesta semana (desde 23/11):</p>
          <p className="mt-1">
            <b>Musculação:</b> 2 treinos
          </p>
          <p>• 24/11, Treino A: 48 min, 14 séries, 3.420 kg</p>
          <p>• 26/11, Treino B: 52 min, 16 séries, 4.110 kg</p>
          <p className="mt-1">
            <b>Atividades:</b> 1
          </p>
          <p>• 25/11, corrida: 35 min, 6 km</p>
          <p className="mt-1.5 text-[8px] font-semibold text-text-secondary">
            Consultou: treinos e atividades
          </p>
        </div>
        <div className="max-w-[92%] rounded-[16px] border border-border-subtle bg-bg-surface p-2.5">
          <p className="text-[8px] font-semibold text-text-secondary">
            Proposta · Aguardando sua resposta
          </p>
          <p className="mt-0.5 text-[10px] font-semibold">Acrescentar Barra fixa à ficha Treino A</p>
          <div className="mt-1.5 flex gap-1.5 text-[9px] font-semibold">
            <span className="rounded-pill bg-accent px-2.5 py-1 text-on-accent">Confirmar</span>
            <span className="rounded-pill border border-border-strong px-2.5 py-1">Recusar</span>
          </div>
        </div>
      </div>
    </>
  );
}
