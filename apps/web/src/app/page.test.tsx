import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { sections } from "@/components/site-chrome";
import { faq, homeJsonLd, jsonLdScript } from "@/lib/content";

import manifest from "./manifest";
import NotFound from "./not-found";
import Home from "./page";
import Privacy from "./privacidade/page";
import robots from "./robots";
import sitemap from "./sitemap";

afterEach(cleanup);

describe("página inicial", () => {
  it("tem exatamente um h1 e as seções nomeadas", () => {
    render(<Home />);

    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    for (const name of [
      /sua evolução/i,
      /feito para a academia/i,
      /o que o evofit reúne/i,
      /três passos/i,
      /fatos dos seus registros/i,
      /seus dados de saúde/i,
      /perguntas frequentes/i,
      /não mede/i,
    ]) {
      expect(screen.getByRole("region", { name })).toBeTruthy();
    }
  });

  it("os títulos não pulam níveis (h1 → h2 → h3)", () => {
    const { container } = render(<Home />);

    const levels = [...container.querySelectorAll("h1, h2, h3, h4")].map((h) =>
      Number(h.tagName[1]),
    );
    expect(levels[0]).toBe(1);
    for (let i = 1; i < levels.length; i++) {
      expect(levels[i]! - levels[i - 1]!).toBeLessThanOrEqual(1);
    }
  });

  it("apresenta os seis recursos, todos já funcionando", () => {
    render(<Home />);

    const features = within(screen.getByRole("region", { name: /reúne/i })).getAllByRole(
      "article",
    );
    expect(features).toHaveLength(6);
    for (const feature of features) {
      expect(within(feature).getByRole("heading", { level: 3 })).toBeTruthy();
    }
    // Depois da Fase 5, nada mais é "Em breve".
    expect(screen.queryByText("Em breve")).toBeNull();
  });

  it("mostra as sete telas do app, cada uma rotulada como dados de exemplo", () => {
    render(<Home />);

    const screens = screen.getAllByRole("img", { name: /tela/i });
    // As 7 da galeria e a do topo.
    expect(screens).toHaveLength(8);
    for (const phone of screens) {
      expect(phone.getAttribute("aria-label")).toMatch(/dados de exemplo\.$/);
    }
    for (const name of [/meu corpo/i, /nutrição/i, /peso e medidas/i, /assistente/i]) {
      expect(screen.getByRole("img", { name })).toBeTruthy();
    }
    // O rótulo também aparece na imagem, para quem vê (fora a cópia de cada celular na
    // janela de ampliação, fechada).
    const visible = screen
      .getAllByText("Dados de exemplo")
      .filter((label) => label.closest("dialog") === null);
    expect(visible).toHaveLength(8);
  });

  it("as perguntas frequentes abrem e ficam nos dados estruturados", () => {
    const { container } = render(<Home />);

    const items = container.querySelectorAll("#perguntas details");
    expect(items).toHaveLength(faq.length);
    expect(within(items[0] as HTMLElement).getByText(faq[0]!.question)).toBeTruthy();

    const script = container.querySelector('script[type="application/ld+json"]');
    const data = JSON.parse(script?.innerHTML ?? "{}");
    const types = data["@graph"].map((node: { "@type": string }) => node["@type"]);
    expect(types).toEqual(["SoftwareApplication", "FAQPage"]);
    expect(data["@graph"][1].mainEntity).toHaveLength(faq.length);
  });

  it("o JSON-LD não deixa fechar a tag do script", () => {
    expect(jsonLdScript({ text: "</script><b>" })).not.toContain("</script>");
    expect(jsonLdScript(homeJsonLd())).toContain("FAQPage");
  });

  it("deixa claro que é um projeto em desenvolvimento e não substitui profissionais", () => {
    render(<Home />);

    expect(screen.getByText(/projeto de tcc em desenvolvimento/i)).toBeTruthy();
    expect(screen.getByText(/não substitui o acompanhamento/i)).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Próximos passos" })).toBeTruthy();
  });

  it("o menu tem todas as seções, também no celular", () => {
    render(<Home />);

    const nav = screen.getByRole("navigation", { name: "Principal" });
    for (const s of sections) {
      // Na lista larga e no menu do celular.
      expect(within(nav).getAllByRole("link", { name: s.label })).toHaveLength(2);
    }
    expect(within(nav).getByText("Menu")).toBeTruthy();
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
    expect(screen.getAllByRole("link", { name: /aviso de privacidade/i }).length).toBeGreaterThan(0);
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

describe("outras páginas e SEO", () => {
  it("o aviso de privacidade tem um h1, avisa que não é revisão jurídica e volta ao início", () => {
    render(<Privacy />);

    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    expect(screen.getByText(/revisão jurídica/i)).toBeTruthy();
    expect(screen.getByRole("region", { name: /seus direitos/i })).toBeTruthy();
    // Fora da página inicial, o menu leva às seções dela.
    const nav = screen.getByRole("navigation", { name: "Principal" });
    expect(within(nav).getAllByRole("link", { name: "Recursos" })[0]!.getAttribute("href")).toBe(
      "/#recursos",
    );
    expect(screen.getByRole("link", { name: "Voltar para o início" }).getAttribute("href")).toBe("/");
  });

  it("a página 404 explica e leva ao início", () => {
    render(<NotFound />);

    expect(screen.getByRole("heading", { level: 1, name: /não existe/i })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Ir para o início" }).getAttribute("href")).toBe("/");
  });

  it("sitemap, robots e manifesto", () => {
    expect(sitemap().map((entry) => new URL(entry.url).pathname)).toEqual(["/", "/privacidade"]);
    expect(robots().sitemap).toMatch(/\/sitemap\.xml$/);
    expect(manifest().lang).toBe("pt-BR");
  });
});
