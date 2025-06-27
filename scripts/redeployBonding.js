/* eslint-disable */
const {ethers} = require('hardhat');

async function verify(address, args, contractPath) {
  try {
    // verify the token contract code
    await hre.run('verify:verify', {
      address: address,
      constructorArguments: args,
      contract: contractPath
    });
  } catch (e) {
    console.log('error verifying contract', e);
  }
  await sleep(1000);
}

function getNonce() {
  return baseNonce + nonceOffset++;
}

async function deployContract(name = 'Contract', path, args) {
  const Contract = await ethers.getContractFactory(path);

  const Deployed = await Contract.deploy(...args, {nonce: getNonce()});
  console.log(name, ': ', Deployed.address);
  await sleep(5000);

  return Deployed;
}

async function fetchContract(path, address) {
  // Fetch Deployed Factory
  const Contract = await ethers.getContractAt(path, address);
  console.log('Fetched ', path, ': ', Contract.address, '  Verify Against: ', address, '\n');
  await sleep(100)
  return Contract;
}

async function sleep(ms) {
  return new Promise(resolve => {
    setTimeout(() => {
      return resolve();
    }, ms);
  });
}

async function main() {
    console.log('Starting Deploy');

    // addresses
    [owner] = await ethers.getSigners();

    // fetch data on deployer
    console.log('Deploying contracts with the account:', owner.address);
    console.log('Account balance:', (await owner.getBalance()).toString());

    // manage nonce
    baseNonce = await ethers.provider.getTransactionCount(owner.address);
    nonceOffset = 0;
    console.log('Account nonce: ', baseNonce);

    // const EnjoyPumpDatabase = await deployContract('EnjoyPumpDatabase', 'contracts/EnjoyPumpDatabase.sol:EnjoyPumpDatabase', []);
    // const EnjoyPumpDatabase = await fetchContract('contracts/EnjoyPumpDatabase.sol:EnjoyPumpDatabase', '0xc48556Da0E6a7af9b175e907c7Be8e8CB6070e3D');
    // await sleep(5_000);


    // const SupplyFetcher = await deployContract('SupplyFetcher', 'contracts/SupplyFetcher.sol:SupplyFetcher', []);
    // await sleep(10_000);

    // await verify(SupplyFetcher.address, [], 'contracts/SupplyFetcher.sol:SupplyFetcher');

    // await EnjoyPumpDatabase.setFeeRecipient(FeeReceiver.address, { nonce: getNonce() });
    // console.log('Set Fee receiver');

    const EnjoyPumpDatabase = await fetchContract('contracts/EnjoyPumpDatabase.sol:EnjoyPumpDatabase', '0x0c073F76B8e4a8FF8D338258e22De4Af8E0c194F');
    await sleep(5_000);

    const INFFeeReceiver = await deployContract('INFFeeReceiver', 'contracts/INFFeeReceiver.sol:INFFeeReceiver', []);
    await sleep(10_000);

    const feeArgs = [
      INFFeeReceiver.address,
      EnjoyPumpDatabase.address
    ]

    const FeeReceiver = await deployContract('FeeReceiver', 'contracts/FeeReceiver.sol:FeeReceiver', feeArgs);
    await sleep(12_000);

    await EnjoyPumpDatabase.setFeeRecipient(FeeReceiver.address, { nonce: getNonce() });
    await sleep(5000);
    console.log('Set Fee receiver');

    await verify(FeeReceiver.address, feeArgs, 'contracts/FeeReceiver.sol:FeeReceiver');
    await verify(INFFeeReceiver.address, [], 'contracts/INFFeeReceiver.sol:INFFeeReceiver');

    // const BondingCurve = await deployContract('BondingCurve', 'contracts/BondingCurve.sol:BondingCurve', []);
    // await sleep(5_000);

    // await verify(BondingCurve.address, [], 'contracts/BondingCurve.sol:BondingCurve');

    // set master copies
    // await EnjoyPumpDatabase.setEnjoyPumpBondingCurveMasterCopy(BondingCurve.address, { nonce: getNonce() });
    // await sleep(5000);
    // console.log('Set Bonding Curve Master Copy');

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
