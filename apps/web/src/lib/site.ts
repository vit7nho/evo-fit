/** Dados de marca do site. O nome é provisório e configurável (docs/VISION.md). */
export const site = {
  name: process.env.NEXT_PUBLIC_SITE_NAME ?? "EvoFit",
  url: process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000",
  description:
    "Musculação, corrida, caminhada, alimentação e peso em um só lugar, com uma IA que responde a partir dos seus próprios registros.",
} as const;
