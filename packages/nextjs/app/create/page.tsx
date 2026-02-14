import type { NextPage } from "next";
import { CreateAuctionForm } from "~~/components/ShadowBid/CreateAuctionForm";

const CreateAuction: NextPage = () => {
    return (
        <div className="flex items-center flex-col grow pt-10">
            <h1 className="text-center text-3xl font-bold mb-8">Launch Sealed-Bid Auction</h1>
            <div className="transform scale-100">
                <CreateAuctionForm />
            </div>
        </div>
    );
};

export default CreateAuction;
