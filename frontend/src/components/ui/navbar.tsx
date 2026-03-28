"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { motion, AnimatePresence } from "framer-motion";
import { Menu, X } from "lucide-react";
import { WalletButton } from "@/components/wallet/wallet-button";
import { cn } from "@/lib/utils";

const navLinks = [
  { href: "/", label: "Home" },
  { href: "/app", label: "Create Intent" },
  { href: "/live", label: "Live" },
  { href: "/solver", label: "Solver Docs" },
];

export function Navbar() {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);

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
          ? "border-[#1a1a1a] backdrop-blur-sm"
          : "border-transparent"
      )}
      style={{ background: "rgba(5,5,9,0.92)" }}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-3 group">
            <span
              className="text-sm font-bold tracking-widest text-[#F5F5F0] group-hover:text-white transition-colors"
              style={{ fontFamily: "'Space Mono', monospace" }}
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
                  "px-4 py-2 text-sm font-medium transition-all duration-200 flex items-center gap-2",
                  pathname === link.href
                    ? "text-[#F5F5F0]"
                    : "text-[#666660] hover:text-[#F5F5F0]"
                )}
                style={{ fontFamily: "'Space Grotesk', sans-serif" }}
              >
                {link.label}
                {link.href === "/live" && (
                  <span className="w-1.5 h-1.5 bg-[#00C566] rounded-full animate-pulse" />
                )}
              </Link>
            ))}
          </div>

          {/* Right side */}
          <div className="flex items-center gap-3">
            <WalletButton />
            <button
              className="md:hidden p-2 text-[#666660] hover:text-[#F5F5F0] transition-colors"
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
            className="md:hidden border-t border-[#1a1a1a]"
            style={{ background: "rgba(5,5,9,0.98)" }}
          >
            <div className="px-4 py-4 space-y-1">
              {navLinks.map((link) => (
                <Link
                  key={link.href}
                  href={link.href}
                  onClick={() => setMobileOpen(false)}
                  className={cn(
                    "flex items-center px-4 py-3 text-sm font-medium transition-colors",
                    pathname === link.href
                      ? "text-[#F5F5F0]"
                      : "text-[#666660] hover:text-[#F5F5F0]"
                  )}
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
