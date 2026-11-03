"use client";

/*
 * Tilt Card, do Spell UI (https://spell.sh, licença MIT em ./LICENSE).
 * Adaptado para o EvoFit: `cn` local e, com "reduzir movimento" ligado, o cartão
 * não inclina (o reflexo de luz continua).
 */

import { useCallback, useRef, useState } from "react";

import { cn } from "@/lib/cn";

export interface TiltCardProps {
  /** Ângulo máximo de inclinação, em graus. */
  tiltLimit?: number;
  /** Escala ao passar o mouse. */
  scale?: number;
  /** Distância da perspectiva, em pixels. */
  perspective?: number;
  /** "gravitate" segue o cursor; "evade" inclina para longe. */
  effect?: "gravitate" | "evade";
  /** Reflexo de luz que segue o cursor. */
  spotlight?: boolean;
  className?: string;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}

export function TiltCard({
  tiltLimit = 15,
  scale = 1.05,
  perspective = 1200,
  effect = "evade",
  spotlight = true,
  className,
  style,
  children,
}: TiltCardProps) {
  const cardRef = useRef<HTMLDivElement>(null);
  const [transform, setTransform] = useState(
    `perspective(${perspective}px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)`,
  );
  const [spotlightPos, setSpotlightPos] = useState({ x: 50, y: 50 });
  const [isHovered, setIsHovered] = useState(false);

  const dir = effect === "evade" ? -1 : 1;

  const handlePointerMove = useCallback(
    (e: React.PointerEvent) => {
      const el = cardRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const px = (e.clientX - rect.left) / rect.width;
      const py = (e.clientY - rect.top) / rect.height;
      if (spotlight) setSpotlightPos({ x: px * 100, y: py * 100 });
      if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
      const xRot = (py - 0.5) * (tiltLimit * 2) * dir;
      const yRot = (px - 0.5) * -(tiltLimit * 2) * dir;
      setTransform(
        `perspective(${perspective}px) rotateX(${xRot}deg) rotateY(${yRot}deg) scale3d(${scale}, ${scale}, ${scale})`,
      );
    },
    [tiltLimit, scale, perspective, dir, spotlight],
  );

  const handlePointerEnter = useCallback(() => setIsHovered(true), []);

  const handlePointerLeave = useCallback(() => {
    setTransform(`perspective(${perspective}px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)`);
    setIsHovered(false);
  }, [perspective]);

  return (
    <div
      ref={cardRef}
      onPointerEnter={handlePointerEnter}
      onPointerMove={handlePointerMove}
      onPointerLeave={handlePointerLeave}
      className={cn("relative overflow-hidden will-change-transform", className)}
      style={{
        transform,
        transition: "transform 0.2s ease-out",
        transformStyle: "preserve-3d",
        ...style,
      }}
    >
      {children}
      {spotlight && (
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 z-10 overflow-hidden"
          style={{ opacity: isHovered ? 1 : 0, transition: "opacity 0.3s" }}
        >
          <div
            className="absolute h-[200%] w-[200%] rounded-full opacity-50"
            style={{
              left: `${spotlightPos.x}%`,
              top: `${spotlightPos.y}%`,
              transform: "translate(-50%, -50%)",
              background: "radial-gradient(circle, rgba(255,255,255,0.15) 0%, transparent 40%)",
            }}
          />
        </div>
      )}
    </div>
  );
}
