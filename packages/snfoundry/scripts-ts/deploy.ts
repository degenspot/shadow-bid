import {
  deployContract,
  executeDeployCalls,
  exportDeployments,
  deployer,
  assertDeployerDefined,
  assertRpcNetworkActive,
  assertDeployerSignable,
} from "./deploy-contract";
import { green, red } from "./helpers/colorize-log";

/**
 * Deploy script for ShadowBid and Mocks
 */
const deployScript = async (): Promise<void> => {
  // 1. Deploy Mock Verifier
  const verifierDeployment = await deployContract({
    contract: "MockVerifier",
    contractName: "MockVerifier",
  });

  // 2. Deploy Mock Token
  const tokenDeployment = await deployContract({
    contract: "MockToken",
    contractName: "MockToken",
  });

  // Calculate addresses or get from return?
  // deployContract returns { address: string } usually?
  // Let's check deploy-contract.ts if needed, but usually it returns deployment info.
  // scaffold-stark deployContract returns { address: string, classHash: string, ... }

  const verifierAddress = verifierDeployment.address;
  const tokenAddress = tokenDeployment.address;

  // 3. Deploy ShadowBid
  await deployContract({
    contract: "ShadowBid",
    contractName: "ShadowBid",
    constructorArgs: {
      verifier_address: verifierAddress,
      payment_token: tokenAddress
    }
  });
};

const main = async (): Promise<void> => {
  try {
    assertDeployerDefined();

    await Promise.all([assertRpcNetworkActive(), assertDeployerSignable()]);

    await deployScript();
    await executeDeployCalls();
    exportDeployments();

    console.log(green("All Setup Done!"));
  } catch (err) {
    if (err instanceof Error) {
      console.error(red(err.message));
    } else {
      console.error(err);
    }
    process.exit(1);
  }
};

main();
