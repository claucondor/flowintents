import React from "react";
import { cn } from "@/lib/utils";

interface CardProps {
  children: React.ReactNode;
  className?: string;
  glow?: "cyan" | "purple" | "green" | "none";
  hover?: boolean;
}

export function Card({ children, className, hover = false }: CardProps) {
  return (
    <div
      style={{ background: "var(--bg-card)", borderColor: "var(--border)" }}
      className={cn(
        "rounded-none p-6 transition-all duration-200 border",
        hover && "hover:border-[#0047FF]/30 cursor-pointer",
        className
      )}
    >
      {children}
    </div>
  );
}

export function CardHeader({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex items-center justify-between mb-4", className)}>{children}</div>
  );
}

export function CardTitle({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <h3 className={cn("font-semibold text-lg", className)} style={{ color: "var(--text-primary)" }}>{children}</h3>
  );
}
