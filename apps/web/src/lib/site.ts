/** Dados de marca do site. O nome é provisório e configurável (docs/VISION.md). */
export const site = {
  name: process.env.NEXT_PUBLIC_SITE_NAME ?? "EvoFit",
  url: process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000",
  description:
    "Treino, corrida, caminhada e nutrição em um só lugar, com uma IA que analisa a sua evolução a partir dos seus próprios registros.",
} as const;
