import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import Home from "./page";

afterEach(cleanup);

describe("página inicial", () => {
  it("tem exatamente um h1 e as seções nomeadas", () => {
    render(<Home />);

    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    expect(screen.getByRole("region", { name: /sua evolução/i })).toBeTruthy();
    expect(screen.getByRole("region", { name: /feito para a academia/i })).toBeTruthy();
    expect(screen.getByRole("region", { name: /o que o evofit reúne/i })).toBeTruthy();
  });

  it("apresenta os quatro recursos, marcando o que ainda não existe", () => {
    render(<Home />);

    const features = within(screen.getByRole("region", { name: /reúne/i })).getAllByRole(
      "article",
    );
    expect(features).toHaveLength(4);
    for (const feature of features) {
      expect(within(feature).getByRole("heading", { level: 3 })).toBeTruthy();
    }
    // Cardio, Meu Corpo e IA são das próximas fases; musculação já funciona.
    expect(within(features[0]).queryByText("Em breve")).toBeNull();
    expect(screen.getAllByText("Em breve")).toHaveLength(3);
  });

  it("mostra as telas do app com descrição para o leitor de tela", () => {
    render(<Home />);

    const screens = screen.getAllByRole("img", { name: /tela/i });
    expect(screens.length).toBeGreaterThanOrEqual(4);
    expect(screen.getByRole("img", { name: /tela do histórico/i })).toBeTruthy();
  });

  it("deixa claro que é um projeto em desenvolvimento e não substitui profissionais", () => {
    render(<Home />);

    expect(screen.getByText(/projeto de tcc em desenvolvimento/i)).toBeTruthy();
    expect(screen.getByText(/não substitui o acompanhamento/i)).toBeTruthy();
  });

  it("os links levam a um destino real (página ou seção que existe)", () => {
    const { container } = render(<Home />);

    // Botões só para ampliar as telas do celular, cada um com nome.
    for (const button of screen.getAllByRole("button")) {
      expect(button.getAttribute("aria-label")).toMatch(/^Ampliar a tela: /);
    }
    for (const link of screen.getAllByRole("link")) {
      const href = link.getAttribute("href") ?? "";
      expect(href).toMatch(/^(\/|https?:|#)/);
      if (href.startsWith("#")) {
        expect(container.querySelector(href)).not.toBeNull();
      }
    }
  });

  it("clicar no celular abre a tela ampliada, e o X fecha", () => {
    render(<Home />);

    fireEvent.click(screen.getByRole("button", { name: "Ampliar a tela: Histórico" }));
    const dialog = screen.getByRole("dialog", { name: "Histórico" });
    expect(dialog.hasAttribute("open")).toBe(true);
    expect(within(dialog).getByRole("img", { name: /tela do histórico/i })).toBeTruthy();

    fireEvent.click(within(dialog).getByRole("button", { name: "Fechar" }));
    expect(dialog.hasAttribute("open")).toBe(false);
  });
});
