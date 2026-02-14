import Link from "next/link";
import Image from "next/image";
import { ConnectedAddress } from "~~/components/ConnectedAddress";
import { AuctionList } from "~~/components/ShadowBid/AuctionList";

const Home = () => {
  return (
    <div className="flex items-center flex-col grow pt-10">
      <div className="px-5 w-full max-w-7xl">
        <h1 className="text-center mb-10">
          <span className="block text-2xl mb-2">Welcome to</span>
          <span className="block text-4xl font-bold">ShadowBid</span>
        </h1>

        <div className="flex justify-center mb-10">
          <ConnectedAddress />
        </div>

        <div className="bg-base-200 rounded-3xl p-8">
          <div className="flex justify-between items-center mb-6">
            <h2 className="text-2xl font-bold">Active Auctions</h2>
            <Link href="/create" className="btn btn-primary">
              Create Auction
            </Link>
          </div>

          <AuctionList />
        </div>
      </div>
    </div>
  );
};

export default Home;
