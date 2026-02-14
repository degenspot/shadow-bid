"use client";

import { useScaffoldWriteContract } from "~~/hooks/scaffold-stark/useScaffoldWriteContract";
import { useState } from "react";
import { parseUnits } from "ethers";

export const CreateAuctionForm = () => {
    const [itemHash, setItemHash] = useState<string>("");
    const [minPrice, setMinPrice] = useState<string>("");
    const [bidDuration, setBidDuration] = useState<string>("");
    const [revealDuration, setRevealDuration] = useState<string>("");

    const { sendAsync: createAuction, isPending } = useScaffoldWriteContract({
        contractName: "ShadowBid",
        functionName: "create_auction",
        args: [
            itemHash, // felt252
            minPrice ? parseUnits(minPrice, 18) : 0n, // u256
            bidDuration ? Number(bidDuration) : 0, // u64 -- simplistic, maybe convert to seconds? Assuming input is seconds.
            revealDuration ? Number(revealDuration) : 0, // u64
        ],
    });

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        try {
            await createAuction();
            // Reset form or redirect?
        } catch (e) {
            console.error("Error creating auction:", e);
        }
    };

    return (
        <form onSubmit={handleSubmit} className="card w-96 bg-base-100 shadow-xl border border-base-300">
            <div className="card-body">
                <h2 className="card-title justify-center mb-4">Create New Auction</h2>

                <div className="form-control w-full">
                    <label className="label">
                        <span className="label-text">Item Hash (felt252)</span>
                    </label>
                    <input
                        type="text"
                        placeholder="0x..."
                        className="input input-bordered w-full"
                        value={itemHash}
                        onChange={(e) => setItemHash(e.target.value)}
                    />
                </div>

                <div className="form-control w-full">
                    <label className="label">
                        <span className="label-text">Min Price (ETH)</span>
                    </label>
                    <input
                        type="number"
                        placeholder="0.1"
                        step="0.000000000000000001"
                        className="input input-bordered w-full"
                        value={minPrice}
                        onChange={(e) => setMinPrice(e.target.value)}
                    />
                </div>

                <div className="form-control w-full">
                    <label className="label">
                        <span className="label-text">Bid Duration (seconds)</span>
                    </label>
                    <input
                        type="number"
                        placeholder="300"
                        className="input input-bordered w-full"
                        value={bidDuration}
                        onChange={(e) => setBidDuration(e.target.value)}
                    />
                </div>

                <div className="form-control w-full">
                    <label className="label">
                        <span className="label-text">Reveal Duration (seconds)</span>
                    </label>
                    <input
                        type="number"
                        placeholder="300"
                        className="input input-bordered w-full"
                        value={revealDuration}
                        onChange={(e) => setRevealDuration(e.target.value)}
                    />
                </div>

                <div className="card-actions justify-end mt-6">
                    <button
                        type="submit"
                        className={`btn btn-primary w-full ${isPending ? "loading" : ""}`}
                        disabled={isPending || !itemHash || !minPrice || !bidDuration || !revealDuration}
                    >
                        {isPending ? "Creating..." : "Create Auction"}
                    </button>
                </div>
            </div>
        </form>
    );
};
