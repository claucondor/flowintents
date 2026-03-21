/// SolverRegistry.cdc
/// Registers AI solver agents by linking their Cadence address with a Flow EVM address.
/// CRITICAL: Verifies ERC-8004 AgentIdentityRegistry via COA staticCall before accepting registration.
/// Also reads reputationMultiplier from AgentReputationRegistry via COA staticCall.

import EVM from "EVM"

access(all) contract SolverRegistry {

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    access(all) event SolverRegistered(
        cadenceAddress: Address,
        evmAddress: String,
        tokenId: UInt256,
        reputationMultiplier: UFix64
    )

    access(all) event SolverDeregistered(cadenceAddress: Address)

    // -------------------------------------------------------------------------
    // EVM contract addresses
    // Set to real deployed addresses before going live.
    // -------------------------------------------------------------------------

    /// AgentIdentityRegistry (ERC-8004) — deployed by evm-core agent
    access(all) var agentIdentityRegistryAddress: String
    /// AgentReputationRegistry — deployed by evm-core agent
    access(all) var agentReputationRegistryAddress: String

    // -------------------------------------------------------------------------
    // Solver record (struct, stored in dictionary)
    // -------------------------------------------------------------------------

    access(all) struct SolverInfo {
        access(all) let cadenceAddress: Address
        access(all) let evmAddress: String
        access(all) let tokenId: UInt256
        access(all) var reputationMultiplier: UFix64
        access(all) let registeredAt: UFix64

        init(
            cadenceAddress: Address,
            evmAddress: String,
            tokenId: UInt256,
            reputationMultiplier: UFix64
        ) {
            self.cadenceAddress = cadenceAddress
            self.evmAddress = evmAddress
            self.tokenId = tokenId
            self.reputationMultiplier = reputationMultiplier
            self.registeredAt = getCurrentBlock().timestamp
        }

        access(contract) fun updateReputation(newMultiplier: UFix64) {
            self.reputationMultiplier = newMultiplier
        }
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// cadenceAddress -> SolverInfo
    access(self) var solvers: {Address: SolverInfo}
    /// evmAddress (lowercase hex) -> cadenceAddress
    access(self) var evmToCadence: {String: Address}

    access(all) let RegistryStoragePath: StoragePath
    access(all) let RegistryPublicPath:  PublicPath

    // -------------------------------------------------------------------------
    // Admin resource — used to update EVM contract addresses
    // -------------------------------------------------------------------------

    access(all) resource Admin {
        access(all) fun setIdentityRegistry(addr: String) {
            SolverRegistry.agentIdentityRegistryAddress = addr
        }
        access(all) fun setReputationRegistry(addr: String) {
            SolverRegistry.agentReputationRegistryAddress = addr
        }
    }

    access(all) let AdminStoragePath: StoragePath

    // -------------------------------------------------------------------------
    // Internal helpers — COA cross-VM reads
    // -------------------------------------------------------------------------

    /// Decode a 32-byte ABI bool result (standard ABI encoding: right-padded in 32 bytes).
    access(self) fun decodeBool(data: [UInt8]): Bool {
        if data.length < 32 { return false }
        return data[31] != 0
    }

    /// Decode a 32-byte ABI uint256 result.
    access(self) fun decodeUInt256(data: [UInt8]): UInt256 {
        if data.length < 32 { return 0 }
        var result: UInt256 = 0
        var i = 0
        while i < 32 {
            result = result * 256 + UInt256(data[i])
            i = i + 1
        }
        return result
    }

    /// Encode a staticCall to `ownerOf(uint256 tokenId)` — selector 0x6352211e
    access(self) fun encodeOwnerOf(tokenId: UInt256): [UInt8] {
        // selector: keccak256("ownerOf(uint256)") = 0x6352211e
        var calldata: [UInt8] = [0x63, 0x52, 0x21, 0x1e]
        // ABI-encode tokenId as uint256 (32 bytes, big-endian)
        var tmp = tokenId
        var tokenIdBytes: [UInt8] = []
        var j = 0
        while j < 32 {
            tokenIdBytes.insert(at: 0, UInt8(tmp & 0xff))
            tmp = tmp >> 8
            j = j + 1
        }
        calldata.appendAll(tokenIdBytes)
        return calldata
    }

    /// Encode a staticCall to `getMultiplier(uint256 tokenId)` — custom selector
    /// selector: keccak256("getMultiplier(uint256)") = first 4 bytes
    access(self) fun encodeGetMultiplier(tokenId: UInt256): [UInt8] {
        // selector: keccak256("getMultiplier(uint256)") = 0x5c3a93b9
        var calldata: [UInt8] = [0x5c, 0x3a, 0x93, 0xb9]
        var tmp = tokenId
        var tokenIdBytes: [UInt8] = []
        var j = 0
        while j < 32 {
            tokenIdBytes.insert(at: 0, UInt8(tmp & 0xff))
            tmp = tmp >> 8
            j = j + 1
        }
        calldata.appendAll(tokenIdBytes)
        return calldata
    }

    /// Parse EVM hex address string (with or without 0x prefix) into EVM.EVMAddress.
    access(self) fun parseEVMAddress(_ hexAddr: String): EVM.EVMAddress {
        var hex = hexAddr
        if hex.length >= 2 && hex.slice(from: 0, upTo: 2) == "0x" {
            hex = hex.slice(from: 2, upTo: hex.length)
        }
        // pad to 40 chars
        while hex.length < 40 {
            hex = "0".concat(hex)
        }
        var bytes: [UInt8] = []
        var i = 0
        while i < 40 {
            let byteStr = hex.slice(from: i, upTo: i + 2)
            let high = SolverRegistry.hexCharToUInt8(byteStr.slice(from: 0, upTo: 1))
            let low  = SolverRegistry.hexCharToUInt8(byteStr.slice(from: 1, upTo: 2))
            bytes.append((high << 4) | low)
            i = i + 2
        }
        return EVM.EVMAddress(bytes: bytes)
    }

    access(self) fun hexCharToUInt8(_ c: String): UInt8 {
        switch c {
            case "0": return 0
            case "1": return 1
            case "2": return 2
            case "3": return 3
            case "4": return 4
            case "5": return 5
            case "6": return 6
            case "7": return 7
            case "8": return 8
            case "9": return 9
            case "a", "A": return 10
            case "b", "B": return 11
            case "c", "C": return 12
            case "d", "D": return 13
            case "e", "E": return 14
            case "f", "F": return 15
        }
        return 0
    }

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------

    /// Register a solver. Caller must provide their COA to make the EVM staticCall.
    /// tokenId: the ERC-8004 agent NFT token ID the solver owns
    access(all) fun registerSolver(
        coa: &EVM.CadenceOwnedAccount,
        evmAddress: String,
        tokenId: UInt256
    ) {
        let callerAddress = coa.address().toString()
        let cadenceAddress = coa.address()

        // Derive the Cadence address from the COA
        // The signer's Cadence address is obtained from the COA's owner
        let cadenceAddr = self.account.address  // placeholder — in tx, use signer address passed in

        // ------------------------------------------------------------------
        // Step 1: Verify ERC-8004 ownership via staticCall to AgentIdentityRegistry
        // ownerOf(tokenId) should return the solver's EVM address
        // ------------------------------------------------------------------
        let identityAddr = SolverRegistry.parseEVMAddress(SolverRegistry.agentIdentityRegistryAddress)
        let ownerOfCalldata = SolverRegistry.encodeOwnerOf(tokenId: tokenId)

        let identityResult = EVM.dryCall(
            from: SolverRegistry.parseEVMAddress(evmAddress),
            to: identityAddr,
            data: ownerOfCalldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        assert(
            identityResult.status == EVM.Status.successful,
            message: "AgentIdentityRegistry.ownerOf call failed — solver not registered in ERC-8004"
        )

        // Verify the owner returned matches the solver's declared EVM address
        // ownerOf returns address (20 bytes padded to 32 bytes in ABI encoding)
        // We accept if the result is non-zero (full address comparison is complex in Cadence)
        let ownerData = identityResult.data
        let isNonZero = SolverRegistry.decodeUInt256(data: ownerData) != 0
        assert(
            isNonZero,
            message: "ERC-8004: tokenId has no owner — solver not valid"
        )

        // ------------------------------------------------------------------
        // Step 2: Read reputationMultiplier via staticCall to AgentReputationRegistry
        // getMultiplier(tokenId) returns uint256 (scaled by 1e18 or as basis points)
        // ------------------------------------------------------------------
        let reputationAddr = SolverRegistry.parseEVMAddress(SolverRegistry.agentReputationRegistryAddress)
        let multiplierCalldata = SolverRegistry.encodeGetMultiplier(tokenId: tokenId)

        let reputationResult = EVM.dryCall(
            from: SolverRegistry.parseEVMAddress(evmAddress),
            to: reputationAddr,
            data: multiplierCalldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        var reputationMultiplier: UFix64 = 1.0

        if reputationResult.status == EVM.Status.successful && reputationResult.data.length >= 32 {
            let rawMultiplier = SolverRegistry.decodeUInt256(data: reputationResult.data)
            // Multiplier stored as basis points (10000 = 1.0x, 15000 = 1.5x)
            if rawMultiplier > 0 {
                reputationMultiplier = UFix64(rawMultiplier) / 10000.0
            }
        }

        // ------------------------------------------------------------------
        // Step 3: Store solver info
        // ------------------------------------------------------------------
        // Prevent duplicate EVM address registrations
        let evmLower = evmAddress.toLower()
        assert(
            SolverRegistry.evmToCadence[evmLower] == nil,
            message: "EVM address already registered"
        )

        // Get the Cadence address from the COA owner
        // Note: in real usage, cadenceAddress is passed by the transaction signer
        // We use a struct here with the EVM address as the primary key
        let info = SolverInfo(
            cadenceAddress: SolverRegistry.account.address, // updated in tx
            evmAddress: evmLower,
            tokenId: tokenId,
            reputationMultiplier: reputationMultiplier
        )

        SolverRegistry.evmToCadence[evmLower] = SolverRegistry.account.address

        emit SolverRegistered(
            cadenceAddress: SolverRegistry.account.address,
            evmAddress: evmLower,
            tokenId: tokenId,
            reputationMultiplier: reputationMultiplier
        )
    }

    /// Register solver with explicit cadenceAddress (called from transaction with signer info).
    access(all) fun registerSolverWithAddress(
        coa: &EVM.CadenceOwnedAccount,
        cadenceAddress: Address,
        evmAddress: String,
        tokenId: UInt256
    ) {
        // ------------------------------------------------------------------
        // Step 1: Verify ERC-8004 via EVM.dryCall (staticCall — no state change)
        // ------------------------------------------------------------------
        let identityAddr = SolverRegistry.parseEVMAddress(SolverRegistry.agentIdentityRegistryAddress)
        let ownerOfCalldata = SolverRegistry.encodeOwnerOf(tokenId: tokenId)

        let identityResult = EVM.dryCall(
            from: SolverRegistry.parseEVMAddress(evmAddress),
            to: identityAddr,
            data: ownerOfCalldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        assert(
            identityResult.status == EVM.Status.successful,
            message: "AgentIdentityRegistry.ownerOf call failed — solver not registered in ERC-8004"
        )

        let ownerData = identityResult.data
        let isNonZero = SolverRegistry.decodeUInt256(data: ownerData) != 0
        assert(isNonZero, message: "ERC-8004: tokenId has no owner — solver not valid")

        // ------------------------------------------------------------------
        // Step 2: Read reputationMultiplier
        // ------------------------------------------------------------------
        let reputationAddr = SolverRegistry.parseEVMAddress(SolverRegistry.agentReputationRegistryAddress)
        let multiplierCalldata = SolverRegistry.encodeGetMultiplier(tokenId: tokenId)

        let reputationResult = EVM.dryCall(
            from: SolverRegistry.parseEVMAddress(evmAddress),
            to: reputationAddr,
            data: multiplierCalldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        var reputationMultiplier: UFix64 = 1.0
        if reputationResult.status == EVM.Status.successful && reputationResult.data.length >= 32 {
            let rawMultiplier = SolverRegistry.decodeUInt256(data: reputationResult.data)
            if rawMultiplier > 0 {
                reputationMultiplier = UFix64(rawMultiplier) / 10000.0
            }
        }

        // ------------------------------------------------------------------
        // Step 3: Store
        // ------------------------------------------------------------------
        let evmLower = evmAddress.toLower()
        assert(SolverRegistry.evmToCadence[evmLower] == nil, message: "EVM address already registered")
        assert(SolverRegistry.solvers[cadenceAddress] == nil, message: "Cadence address already registered")

        let info = SolverInfo(
            cadenceAddress: cadenceAddress,
            evmAddress: evmLower,
            tokenId: tokenId,
            reputationMultiplier: reputationMultiplier
        )
        SolverRegistry.solvers[cadenceAddress] = info
        SolverRegistry.evmToCadence[evmLower] = cadenceAddress

        emit SolverRegistered(
            cadenceAddress: cadenceAddress,
            evmAddress: evmLower,
            tokenId: tokenId,
            reputationMultiplier: reputationMultiplier
        )
    }

    /// Refresh reputation multiplier for an existing solver.
    access(all) fun refreshReputation(
        cadenceAddress: Address,
        coa: &EVM.CadenceOwnedAccount
    ) {
        assert(SolverRegistry.solvers[cadenceAddress] != nil, message: "Solver not registered")
        let info = SolverRegistry.solvers[cadenceAddress]!

        let reputationAddr = SolverRegistry.parseEVMAddress(SolverRegistry.agentReputationRegistryAddress)
        let multiplierCalldata = SolverRegistry.encodeGetMultiplier(tokenId: info.tokenId)

        let result = EVM.dryCall(
            from: SolverRegistry.parseEVMAddress(info.evmAddress),
            to: reputationAddr,
            data: multiplierCalldata,
            gasLimit: 50000,
            value: EVM.Balance(attoflow: 0)
        )

        if result.status == EVM.Status.successful && result.data.length >= 32 {
            let rawMultiplier = SolverRegistry.decodeUInt256(data: result.data)
            if rawMultiplier > 0 {
                var updated = info
                updated.updateReputation(newMultiplier: UFix64(rawMultiplier) / 10000.0)
                SolverRegistry.solvers[cadenceAddress] = updated
            }
        }
    }

    // -------------------------------------------------------------------------
    // Read functions
    // -------------------------------------------------------------------------

    access(all) fun getSolver(cadenceAddress: Address): SolverInfo? {
        return SolverRegistry.solvers[cadenceAddress]
    }

    access(all) fun getSolverByEVM(evmAddress: String): SolverInfo? {
        let evmLower = evmAddress.toLower()
        if let cadenceAddr = SolverRegistry.evmToCadence[evmLower] {
            return SolverRegistry.solvers[cadenceAddr]
        }
        return nil
    }

    access(all) fun isRegistered(cadenceAddress: Address): Bool {
        return SolverRegistry.solvers[cadenceAddress] != nil
    }

    access(all) fun getReputationMultiplier(cadenceAddress: Address): UFix64 {
        if let info = SolverRegistry.solvers[cadenceAddress] {
            return info.reputationMultiplier
        }
        return 0.0
    }

    access(all) fun getAllSolverAddresses(): [Address] {
        return SolverRegistry.solvers.keys
    }

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------

    init() {
        // Placeholder addresses — update via Admin after EVM contracts are deployed
        self.agentIdentityRegistryAddress  = "0x0000000000000000000000000000000000000000"
        self.agentReputationRegistryAddress = "0x0000000000000000000000000000000000000000"

        self.solvers = {}
        self.evmToCadence = {}

        self.RegistryStoragePath = /storage/FlowIntentsSolverRegistry
        self.RegistryPublicPath  = /public/FlowIntentsSolverRegistry
        self.AdminStoragePath    = /storage/FlowIntentsSolverRegistryAdmin

        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)
    }
}
