"use client";

import React, { createContext, useContext, useEffect, useState, useCallback } from "react";
import * as fcl from "@onflow/fcl";

interface FlowUser {
  addr: string | null;
  loggedIn: boolean;
}

interface WalletContextType {
  flowUser: FlowUser;
  connectFlow: () => void;
  disconnectFlow: () => void;
  isFlowConnected: boolean;
}

const WalletContext = createContext<WalletContextType>({
  flowUser: { addr: null, loggedIn: false },
  connectFlow: () => {},
  disconnectFlow: () => {},
  isFlowConnected: false,
});

export function WalletProvider({ children }: { children: React.ReactNode }) {
  const [flowUser, setFlowUser] = useState<FlowUser>({ addr: null, loggedIn: false });

  useEffect(() => {
    const unsubscribe = fcl.currentUser.subscribe((user: FlowUser) => {
      setFlowUser(user);
    });
    return () => unsubscribe();
  }, []);

  const connectFlow = useCallback(() => {
    fcl.authenticate();
  }, []);

  const disconnectFlow = useCallback(() => {
    fcl.unauthenticate();
  }, []);

  return (
    <WalletContext.Provider
      value={{
        flowUser,
        connectFlow,
        disconnectFlow,
        isFlowConnected: !!flowUser.loggedIn,
      }}
    >
      {children}
    </WalletContext.Provider>
  );
}

export function useWallet() {
  return useContext(WalletContext);
}
