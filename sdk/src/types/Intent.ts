export interface Intent {
  id: string
  owner: string
  tokenType: string
  principalAmount: string  // UFix64 as string
  targetAPY: number
  durationDays: number
  expiryBlock: number
  status: IntentStatus
  winningBidId?: string
  createdAt: number
}

export type IntentStatus = 'Open' | 'BidSelected' | 'Active' | 'Completed' | 'Cancelled' | 'Expired'
