"use client";

import { useScaffoldReadContract } from "~~/hooks/scaffold-stark/useScaffoldReadContract";
import { Address } from "~~/components/scaffold-stark/Address";
import { formatUnits } from "ethers";
import { useEffect, useState } from "react";

interface AuctionCardProps {
    auctionId: number;
}

// Map Cairo enum to TS
enum AuctionState {
    Open = 0,
    Revealing = 1,
    Settled = 2,
    Cancelled = 3,
}

export const AuctionCard = ({ auctionId }: AuctionCardProps) => {
    // Read Auction Info
    // function get_auction(self: @ContractState, auction_id: u256) -> AuctionInfo
    const { data: auctionInfo, isLoading, error } = useScaffoldReadContract({
        contractName: "ShadowBid",
        functionName: "get_auction",
        args: [auctionId],
    });

    const [timeLeft, setTimeLeft] = useState<string>("");

    // Helper to format BigInt/u256
    const formatToken = (val: any) => {
        if (!val) return "0";
        // Check if val is {low, high} struct (standard Cairo u256 in JS)
        // Or if it's already a BigInt (some providers auto-convert)
        let amount = val;
        if (typeof val === 'object' && 'low' in val) {
            // Simple reconstruction for display (assuming low/high are BigInts or hex strings)
            // For strict correctness we should use uint256 lib, but standard JS BigInt works if 
            // environment supports it (ES2020)
            const low = BigInt(val.low);
            const high = BigInt(val.high);
            amount = (high << 64n) + (high << 64n) + low; // Wait, shifting logic.
            // Actually, let's trust standard parsing if it returns BigInt.
            // If it returns object, we need proper uint256 lib.
            // scaffold-stark usually returns BigInt for u256 if configured correctly types-wise?
            // Let's assume it returns object {low, high} based on common patterns.
            amount = (BigInt(val.high) << 128n) + BigInt(val.low);
        }
        return formatUnits(amount.toString(), 18); // Assuming ETH/ERC20 with 18 decimals
    };

    const getStatusBadge = (state: number) => {
        switch (state) {
            case AuctionState.Open: return <div className="badge badge-success">OPEN</div>;
            case AuctionState.Revealing: return <div className="badge badge-warning">REVEAL PERIOD</div>;
            case AuctionState.Settled: return <div className="badge badge-neutral">SETTLED</div>;
            case AuctionState.Cancelled: return <div className="badge badge-error">CANCELLED</div>;
            default: return <div className="badge badge-ghost">UNKNOWN</div>;
        }
    };

    const formatDeadline = (timestamp: any) => {
        if (!timestamp) return "-";
        const date = new Date(Number(timestamp) * 1000);
        return date.toLocaleString();
    };

    if (isLoading) return <div className="skeleton w-full h-64 rounded-xl"></div>;
    if (error || !auctionInfo) {
        // Don't render card if fetching failed (e.g., auction doesn't exist yet)
        return null;
    }

    // Destructure with safety
    // The structure returned matches the AuctionInfo ABI struct
    // Note: key names from ABI usually preserved.
    // Properties: seller, item_hash, min_price, bid_deadline, reveal_deadline, state, ...
    const info = auctionInfo as any;

    return (
        <div className="card w-96 bg-base-100 shadow-xl border border-base-300">
            <div className="card-body">
                <div className="flex justify-between items-start">
                    <h2 className="card-title">Auction #{auctionId}</h2>
                    {getStatusBadge(info.state.variant ? Object.keys(info.state.variant)[0] : info.state)}
                    {/* Cairo enums in JS sometimes come as object { Variant: value } or just index number depending on provider */}
                </div>

                <div className="divider my-1"></div>

                <div className="space-y-2">
                    <div className="flex justify-between">
                        <span className="font-bold">Seller:</span>
                        <Address address={info.seller} size="xs" />
                    </div>

                    <div className="flex justify-between">
                        <span className="font-bold">Min Price:</span>
                        <span>{formatToken(info.min_price)} ETH</span>
                    </div>

                    <div className="flex justify-between">
                        <span className="font-bold">Highest Bid:</span>
                        <span>{formatToken(info.highest_bid)} ETH</span>
                    </div>

                    <div className="flex justify-between">
                        <span className="font-bold">Bid Deadline:</span>
                        <span className="text-sm">{formatDeadline(info.bid_deadline)}</span>
                    </div>

                    <div className="flex justify-between">
                        <span className="font-bold">Reveal Deadline:</span>
                        <span className="text-sm">{formatDeadline(info.reveal_deadline)}</span>
                    </div>
                </div>

                <div className="card-actions justify-end mt-4">
                    <button className="btn btn-primary btn-sm">Place Bid</button>
                    <button className="btn btn-secondary btn-sm">Reveal</button>
                </div>
            </div>
        </div>
    );
};
