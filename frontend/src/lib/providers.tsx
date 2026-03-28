"use client";

import React, { useEffect, useState } from "react";
import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { wagmiConfig } from "@/config/wagmi";
import { WalletProvider } from "./wallet-context";
import { configureFCL } from "@/config/fcl";

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());

  useEffect(() => {
    configureFCL();
  }, []);

  return (
    <QueryClientProvider client={queryClient}>
      <WagmiProvider config={wagmiConfig}>
        <WalletProvider>
          {children}
        </WalletProvider>
      </WagmiProvider>
    </QueryClientProvider>
  );
}
