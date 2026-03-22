/**
 * MCPClient — wrapper for flow-intelligence-mcp server.
 * All yield, price, and routing data comes through here.
 */

import type {
  YieldOpportunity,
  CrossChainYield,
  RouteResult,
  SlippageMatrix,
} from './types/Strategy'

const MCP_URL = 'http://46.62.129.191:3000/mcp'
const MCP_HEADERS = {
  'Content-Type': 'application/json',
  Accept: 'application/json, text/event-stream',
}

interface MCPRequest {
  jsonrpc: '2.0'
  id: number
  method: 'tools/call'
  params: {
    name: string
    arguments: Record<string, unknown>
  }
}

interface MCPResponse<T = unknown> {
  jsonrpc: '2.0'
  id: number
  result?: {
    content: Array<{ type: string; text: string }>
    isError?: boolean
  }
  error?: { code: number; message: string }
}

let _reqId = 1

export class MCPClient {
  private readonly url: string
  private readonly headers: Record<string, string>

  constructor(url = MCP_URL, headers: Record<string, string> = MCP_HEADERS) {
    this.url = url
    this.headers = headers
  }

  /**
   * Generic MCP tool call.
   * Returns the parsed JSON result from the first text content block.
   */
  async callTool(
    toolName: string,
    args: Record<string, unknown> = {},
  ): Promise<unknown> {
    const body: MCPRequest = {
      jsonrpc: '2.0',
      id: _reqId++,
      method: 'tools/call',
      params: { name: toolName, arguments: args },
    }

    const res = await fetch(this.url, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify(body),
    })

    if (!res.ok) {
      throw new Error(`MCPClient HTTP error ${res.status}: ${await res.text()}`)
    }

    // The MCP server may return application/json or text/event-stream
    const contentType = res.headers.get('content-type') ?? ''
    let raw: string

    if (contentType.includes('text/event-stream')) {
      // Read SSE stream to completion, pick last "data:" line
      raw = await res.text()
      const lines = raw.split('\n').filter((l) => l.startsWith('data:'))
      if (lines.length === 0) throw new Error('MCPClient: empty SSE stream')
      raw = lines[lines.length - 1].replace(/^data:\s*/, '')
    } else {
      raw = await res.text()
    }

    const json = JSON.parse(raw) as MCPResponse
    if (json.error) {
      throw new Error(
        `MCPClient tool error (${json.error.code}): ${json.error.message}`,
      )
    }
    if (!json.result) throw new Error('MCPClient: no result in response')

    const textBlock = json.result.content.find((c) => c.type === 'text')
    if (!textBlock) throw new Error('MCPClient: no text block in result')

    return JSON.parse(textBlock.text)
  }

  // ---- Typed convenience methods ----

  /** more__yield_opportunities — current yield pools on Flow */
  async getYieldOpportunities(): Promise<YieldOpportunity[]> {
    const data = await this.callTool('more__yield_opportunities', {})

    // MCP returns: { opportunities: [{ symbol, supplyAPY, utilizationRate, ... }], ... }
    // Normalize to YieldOpportunity[]
    const raw = data as {
      opportunities?: Array<{
        symbol: string
        supplyAPY: number
        utilizationRate?: number
        totalSupplyUSD?: number
      }>
    }

    if (raw && Array.isArray(raw.opportunities)) {
      return raw.opportunities.map((o) => ({
        protocol: 'MORE Finance',
        asset: o.symbol,
        apy: o.supplyAPY,
        tvl: o.totalSupplyUSD,
        utilizationRate: o.utilizationRate,
        chain: 'flow',
      }))
    }

    // Fallback: data is already YieldOpportunity[]
    return data as YieldOpportunity[]
  }

  /** defi__cross_chain_yields — yields on Ethereum / Base / Arbitrum */
  async getCrossChainYields(): Promise<CrossChainYield[]> {
    const data = await this.callTool('defi__cross_chain_yields', {})
    return data as CrossChainYield[]
  }

  /**
   * dex__simulate_best_route — simulate best swap route for a given amount.
   * @param from  token symbol or address, e.g. "USDC"
   * @param to    token symbol or address, e.g. "FLOW"
   * @param amount  amount as decimal string, e.g. "1000.00"
   */
  async simulateBestRoute(
    from: string,
    to: string,
    amount: string,
  ): Promise<RouteResult> {
    const data = await this.callTool('dex__simulate_best_route', {
      from,
      to,
      amount,
    })
    return data as RouteResult
  }

  /** flow__get_prices — current token prices in USD */
  async getPrices(): Promise<Record<string, number>> {
    const data = await this.callTool('flow__get_prices', {})
    return data as Record<string, number>
  }

  /** dex__slippage_matrix — slippage estimates per pair in basis points */
  async getSlippageMatrix(): Promise<SlippageMatrix> {
    const data = await this.callTool('dex__slippage_matrix', {})
    return data as SlippageMatrix
  }
}
