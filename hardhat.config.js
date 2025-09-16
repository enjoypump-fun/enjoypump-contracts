require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
let secret = require("./secret");
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    hardhat: {
      // chainId: 10143//56//56//8453//137//8453//137//8453//56 
      chainId: 97//56//56//8453//137//8453//137//8453//56 
    },
    bscTestnet: {
      url: 'https://bsc-testnet.therpc.io',
      accounts: [secret.key],
      chainId: 97
    },
    // monadTestnet: {
    //   url: 'https://testnet-rpc.monad.xyz',
    //   accounts: [secret.key],
    //   chainId: 10143
    // }
    // bscMainnet: {
    //   url: 'https://bnb-mainnet.g.alchemy.com/v2/BI5XlYByNdQfh3hcluwetuwR9KzTSn01',
    //   accounts: [secret.key]
    // },
    // polygonTestnet: {
    //   url: 'https://polygon-mumbai-bor-rpc.publicnode.com/',
    //   accounts: [secret.key]
    // },
    // polygonMainnet: {
    //   url: 'https://polygon-rpc.com/',//'https://polygon-bor-rpc.publicnode.com',
    //   accounts: [secret.key],
    //   // chainId: 137
    // },
    // baseMainnet: {
    //   url: 'https://base-mainnet.g.alchemy.com/v2/BI5XlYByNdQfh3hcluwetuwR9KzTSn01',
    //   accounts: [secret.key],
    //   chainId: 8453
    // },
    // infinaeonMainnet: {
    //   url: 'https://rpc.infinaeon.com/',
    //   accounts: [secret.key],
    //   chainId: 420000
    // }
  },
  etherscan: {
    enabled: false,
    apiKey: {
      bscTestnet: '3C4SCAT1FSE73MXVZ1WHPM7R1VJEYJDIZZ'
    }
    // apiKey: secret.bscscanAPI,//polygonAPI,//basescanAPI,//polygonAPI//bscscanAPI
    // customChains: [
      // {
      //   network: "base",
      //   chainId: 8453,
      //   urls: {
      //     apiURL: "https://api.basescan.org/api",
      //     browserURL: "https://basescan.org/"
      //   }
      // }
      // {
      //   network: "infinaeon",
      //   chainId: 420000,
      //   urls: {
      //     apiURL: "https://explorer.infinaeon.com/api",
      //     browserURL: "https://explorer.infinaeon.com/"
      //   }
      // }
    // ]
  },
  // sourcify: {
  //   apiUrl: "https://sourcify-api-monad.blockvision.org",
  //   browserUrl: "https://testnet.monadexplorer.com",
  //   enabled: true,
  // },
  sourcify: {
    apiUrl: "https://api.etherscan.io/v2/api",
    browserUrl: "https://testnet.bscscan.com/",
    enabled: true,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.30",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yul: false
            }
          }
        }
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yul: false
            }
          }
        }
      }
    ]
  }
};
