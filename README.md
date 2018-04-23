# manage_eos

This tool is intended to make it easier to configure and bootstrap an eosio blockchain.

It is recommended to use zrts/run_eos so that the "eosc" command used in the script will be properly interpreted.

You should also configure a wallet and optionally you can store its password (assuming this is a local test network) in the file defined by the variable ${WALLET_PASSWORD}, so that it gets unlocked automatically.

Proceed to launching your nodeos with a clean state and running `eos_init_chain`.

After that you can use `eos_init_contract contract_name` to easily build and deploy the contract inside ~/git/contract_name.

Make sure you also customize both functions and the keys file to your needs.

