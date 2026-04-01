"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { Menu, X, Sun, Moon } from "lucide-react";
import { WalletButton } from "@/components/wallet/wallet-button";
import { useTheme } from "@/components/ui/theme-provider";
import { cn } from "@/lib/utils";

const navLinks = [
  { href: "/", label: "Home" },
  { href: "/app", label: "Create Intent" },
  { href: "/live", label: "Live" },
  { href: "/docs", label: "Docs" },
  { href: "/solver", label: "Solver" },
];

export function Navbar() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const { theme, toggleTheme } = useTheme();

  useEffect(() => {
    const handler = () => setScrolled(window.scrollY > 10);
    window.addEventListener("scroll", handler);
    return () => window.removeEventListener("scroll", handler);
  }, []);

  return (
    <nav
      className={cn(
        "fixed top-0 left-0 right-0 z-50 transition-all duration-300 border-b",
        scrolled
          ? "border-[var(--border)] backdrop-blur-sm"
          : "border-transparent"
      )}
      style={{ background: "rgba(var(--bg-base-rgb, 5,5,9),0.92)", backgroundColor: "color-mix(in srgb, var(--bg-base) 92%, transparent)" }}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-3 group">
            <span
              className="text-sm font-bold tracking-widest transition-colors"
              style={{ fontFamily: "'Space Mono', monospace", color: "var(--text-primary)" }}
            >
              FLOWINTENTS
            </span>
          </Link>

          {/* Desktop Nav */}
          <div className="hidden md:flex items-center gap-1">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={cn(
                  "px-4 py-2 text-sm font-medium transition-all duration-200 flex items-center gap-2"
                )}
                style={{
                  fontFamily: "'Space Grotesk', sans-serif",
                  color: pathname === link.href ? "var(--text-primary)" : "var(--text-muted)",
                }}
              >
                {link.label}
                {link.href === "/live" && (
                  <span className="w-1.5 h-1.5 bg-[#00C566] rounded-full animate-pulse" />
                )}
              </Link>
            ))}
          </div>

          {/* Right side */}
          <div className="flex items-center gap-2">
            {/* Theme toggle */}
            <button
              onClick={toggleTheme}
              className="p-2 transition-colors"
              style={{ color: "var(--text-secondary)" }}
              title={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
            >
              {theme === "dark" ? (
                <Sun className="w-4 h-4" />
              ) : (
                <Moon className="w-4 h-4" />
              )}
            </button>
            <WalletButton />
            <button
              className="md:hidden p-2 transition-colors"
              style={{ color: "var(--text-muted)" }}
              onClick={() => setMobileOpen(!mobileOpen)}
            >
              {mobileOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>
          </div>
        </div>
      </div>

      {/* Mobile menu */}
      <AnimatePresence>
        {mobileOpen && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="md:hidden border-t"
            style={{ borderColor: "var(--border)", background: "var(--bg-base)" }}
          >
            <div className="px-4 py-4 space-y-1">
              {navLinks.map((link) => (
                <Link
                  key={link.href}
                  href={link.href}
                  onClick={() => setMobileOpen(false)}
                  className="flex items-center px-4 py-3 text-sm font-medium transition-colors"
                  style={{
                    color: pathname === link.href ? "var(--text-primary)" : "var(--text-muted)",
                  }}
                >
                  {link.label}
                </Link>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
}
