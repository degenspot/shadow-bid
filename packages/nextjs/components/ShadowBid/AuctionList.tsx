"use client";

import { useScaffoldReadContract } from "~~/hooks/scaffold-stark/useScaffoldReadContract";
import { AuctionCard } from "./AuctionCard";

export const AuctionList = () => {
    const { data: countData, isLoading } = useScaffoldReadContract({
        contractName: "ShadowBid",
        functionName: "get_auction_count",
    });

    // Convert count to number (handling BigInt or u256 object)
    const count = countData ? Number(countData.toString()) : 0;

    if (isLoading) {
        return <div className="text-center p-10"><span className="loading loading-spinner loading-lg"></span></div>;
    }

    if (count === 0) {
        return (
            <div className="text-center p-10 bg-base-200 rounded-xl">
                <h3 className="text-xl font-bold">No Active Auctions</h3>
                <p>Be the first to create a ShadowBid auction!</p>
            </div>
        );
    }

    // Create array of IDs: 1 to count (Contract uses 1-based IDs)
    // Reverse order to show newest first? Or standard 1..N order.
    // Showing newest first (count ... 1) is usually better UI.
    const auctionIds = Array.from({ length: count }, (_, i) => count - i);

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 justify-items-center">
            {auctionIds.map((id) => (
                <AuctionCard key={id} auctionId={id} />
            ))}
        </div>
    );
};
