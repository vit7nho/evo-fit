import type { MetadataRoute } from "next";

import { site } from "@/lib/site";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: site.name,
    short_name: site.name,
    description: site.description,
    lang: "pt-BR",
    start_url: "/",
    display: "standalone",
    background_color: "#070709",
    theme_color: "#070709",
    icons: [{ src: "/favicon.ico", sizes: "any", type: "image/x-icon" }],
  };
}
