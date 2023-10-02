const HDWalletProvider = require('@truffle/hdwallet-provider');

const { privateKeys, BSCSCANAPIKEY} = require('./secrets.json');

module.exports = {
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
    bscscan: BSCSCANAPIKEY
  },
  networks: {
    development: {
     host: "127.0.0.1",     
     port: 7545,            
     network_id: "*",       
    },
    testnet: {
      provider: () => {
        return new HDWalletProvider({
          privateKeys: privateKeys,
          providerOrUrl: `https://data-seed-prebsc-1-s2.binance.org:8545/`,
        });
      },
      network_id: 97,
      confirmations: 5,
      timeoutBlocks: 200,
      skipDryRun: true
    },
    bsc: {
      provider: () => {
        return new HDWalletProvider({
          privateKeys: privateKeys,
          providerOrUrl: `wss://bsc-ws-node.nariox.org:443`,
      });
    },  
    network_id: 56,
      confirmations: 5,
      timeoutBlocks: 200,
      skipDryRun: true
    },  
  },

  compilers: {
    solc: {
      version: "0.8.18",      
      settings: {          
       optimizer: {
         enabled: false,
         runs: 200
       },
       evmVersion: "byzantium"
      }
    }
  },
};
