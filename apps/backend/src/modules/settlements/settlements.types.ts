import type { PayoutRequest, TechnicianStatus } from '@prisma/client';

export interface PayoutRequestDto {
  id: string;
  status: PayoutRequest['status'];
  amountPaise: number;
  requestedAt: string;
  reviewedAt: string | null;
  reviewNote: string | null;
  /** Amount of the PAYOUT ledger entry when PAID (what was actually transferred); null otherwise. */
  paidPaise: number | null;
}

export function toPayoutRequestDto(r: PayoutRequest, paidPaise: number | null = null): PayoutRequestDto {
  return {
    id: r.id, status: r.status, amountPaise: r.amountPaise, requestedAt: r.createdAt.toISOString(),
    reviewedAt: r.reviewedAt?.toISOString() ?? null, reviewNote: r.reviewNote, paidPaise,
  };
}

export interface PendingReleaseDto {
  bookingId: string;
  bookingNumber: string;
  serviceName: string;
  amountPaise: number;
  /** When the settlement sweep may release it (paidAt + dispute window); null when on hold or unpaid. */
  releasesAt: string | null;
  /** The booking is DISPUTED — the amount is the full expected share, released only after resolution. */
  onHold: boolean;
}

export interface EarningsSummaryDto {
  owedPaise: number;
  netPayoutPaise: number;
  pendingPaise: number;
  cashDebtPaise: number;
  cashDebtLimitPaise: number;
  acceptBlocked: boolean;
  payoutMinPaise: number;
  pending: PendingReleaseDto[];
  latestPayoutRequest: PayoutRequestDto | null;
}

export interface LedgerEntryDto {
  id: string;
  type: string;
  amountPaise: number;
  bookingNumber: string | null;
  serviceName: string | null;
  /** Commission rate (basis points) the sweep / dispute resolve applied — COMMISSION / EARNING_CREDIT rows only. */
  rateBps: number | null;
  createdAt: string;
}
export interface LedgerPageDto { entries: LedgerEntryDto[]; nextCursor: string | null; }

export interface AdminPayoutRequestDto extends PayoutRequestDto {
  technicianId: string;
  technicianName: string;
  maskedPhone: string;
  currentOwedPaise: number;
  currentCashDebtPaise: number;
  /** max(0, owed − cash debt): the exact figure ops must transfer and send to pay. */
  currentNetPaise: number;
  /** The technician's current status — ops reviews a SUSPENDED technician before paying. */
  technicianStatus: TechnicianStatus;
  /** Bank/UPI reference ops recorded when marking PAID; null otherwise. Admin-only. */
  transferReference: string | null;
}
