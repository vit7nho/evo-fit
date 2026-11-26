import { ImageResponse } from "next/og";

import { site } from "@/lib/site";

/** Imagem de compartilhamento (redes sociais e mensageiros), gerada no build. */
export const alt = `${site.name}: sua evolução, série por série — musculação, corrida, alimentação e IA.`;
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: 80,
          background:
            "radial-gradient(circle at 85% 20%, #2F5BFF 0%, transparent 45%), radial-gradient(circle at 95% 95%, #E5484D 0%, transparent 40%), #070709",
          color: "#F4F4F2",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 20, fontSize: 40, fontWeight: 700 }}>
          <div
            style={{
              width: 64,
              height: 64,
              borderRadius: 18,
              background: "#FFFFFF",
              color: "#000000",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 40,
            }}
          >
            ↗
          </div>
          {site.name}
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
          <div style={{ fontSize: 88, fontWeight: 700, letterSpacing: -3, lineHeight: 1 }}>
            Sua evolução, série por série.
          </div>
          <div style={{ fontSize: 32, color: "#A3A3AB" }}>
            Musculação · corrida · alimentação · peso · IA com os seus dados
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
