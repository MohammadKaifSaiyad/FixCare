import type { PayoutRequest } from '@prisma/client';

export interface PayoutRequestDto {
  id: string;
  status: PayoutRequest['status'];
  amountPaise: number;
  requestedAt: string;
  reviewedAt: string | null;
  reviewNote: string | null;
}

export function toPayoutRequestDto(r: PayoutRequest): PayoutRequestDto {
  return {
    id: r.id, status: r.status, amountPaise: r.amountPaise, requestedAt: r.createdAt.toISOString(),
    reviewedAt: r.reviewedAt?.toISOString() ?? null, reviewNote: r.reviewNote,
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
