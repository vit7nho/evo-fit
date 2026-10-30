import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import Home from "./page";

afterEach(cleanup);

describe("página inicial", () => {
  it("tem exatamente um h1 e seções nomeadas", () => {
    render(<Home />);

    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    expect(screen.getByRole("region", { name: /sua evolução/i })).toBeTruthy();
    expect(screen.getByRole("region", { name: /o que o evofit reúne/i })).toBeTruthy();
  });

  it("apresenta os quatro pilares como artigos com título", () => {
    render(<Home />);

    const pillars = within(screen.getByRole("region", { name: /reúne/i })).getAllByRole("article");
    expect(pillars).toHaveLength(4);
    for (const pillar of pillars) {
      expect(within(pillar).getByRole("heading", { level: 3 })).toBeTruthy();
    }
  });

  it("deixa claro que é um projeto em desenvolvimento e não substitui profissionais", () => {
    render(<Home />);

    expect(screen.getByText(/projeto de tcc em desenvolvimento/i)).toBeTruthy();
    expect(screen.getByText(/não substitui o acompanhamento/i)).toBeTruthy();
  });

  it("não exibe links ou botões sem destino nesta fase", () => {
    render(<Home />);

    expect(screen.queryAllByRole("button")).toHaveLength(0);
    for (const link of screen.queryAllByRole("link")) {
      expect(link.getAttribute("href")).toMatch(/^(\/|https?:)/);
    }
  });
});
