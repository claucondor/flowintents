import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/lib/providers";
import { Navbar } from "@/components/ui/navbar";
import { ThemeProvider } from "@/components/ui/theme-provider";

export const metadata: Metadata = {
  title: "FlowIntents — The Intent Layer for Flow",
  description:
    "Express what you want. Solvers compete to get it. Intent-based DeFi on Flow blockchain.",
  keywords: ["Flow", "DeFi", "intents", "blockchain", "swap", "yield"],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="min-h-screen antialiased" style={{ background: "var(--bg-base)" }}>
        <ThemeProvider>
          <Providers>
            <Navbar />
            <main className="pt-16">{children}</main>
          </Providers>
        </ThemeProvider>
      </body>
    </html>
  );
}
