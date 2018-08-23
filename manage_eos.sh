#!/bin/sh

EOS_CONTRACTS_DIR=${USER_GIT_ROOT}/eosio.contracts
KEYS_PRODUCERS=$(dirname "$0")/keys.producers
KEYS_SYSTEM=$(dirname "$0")/keys.system
KEYS_USERS=$(dirname "$0")/keys.users
WALLET_PASSWORD=$(cat ~/eosio-wallet/default.passwd)

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

eosio_unlock_wallet()
{
    if [ "$(cleos wallet list | grep '*')" = "" ]; then
        cleos wallet unlock --password=${WALLET_PASSWORD} || return 1
    fi
}

eosio_init_accounts()
{
    keys=${1:-${KEYS_SYSTEM}}
    use_system_contract=${2:-"no"}
    amount=${3:-"1.0000 EOS"}
    reg_producer=${4:-"no"}

    imported=$(cleos wallet keys)

    while read line; do
        name=$(echo ${line} | cut -d ' ' -f 1)
        pubkey=$(echo ${line} | cut -d ' ' -f 2)
        privkey=$(echo ${line} | cut -d ' ' -f 3)

        if [ "$(echo ${imported} | grep ${pubkey})" = "" ]; then
            cleos wallet import --private-key ${privkey} || return 1
        fi

        if [ "${name}" = "eosio" ]; then
            continue
        fi
        if cleos get account ${name}; then
            continue
        fi

        if [ "${use_system_contract}" = "no" ]; then
            cleos create account eosio ${name} ${pubkey} ${pubkey} || return 1
        else
            cleos system newaccount eosio --buy-ram-kbytes 8 --transfer ${name} ${pubkey} --stake-net ${amount} --stake-cpu ${amount} || return 1
        fi

        if [ "${reg_producer}" != "no" ]; then
            cleos system regproducer ${name} ${pubkey} || return 1
        fi
    done < ${keys}
}

eosio_init_chain()
{
    if ! eosio_unlock_wallet; then
        printf "error: could not unlock wallet\n"
        return 1
    fi
    if ! eosio_init_accounts; then
        printf "error: could not create system accounts\n"
        return 1
    fi

    cleos set contract eosio.token ${EOS_CONTRACTS_DIR}/eosio.token/bin/eosio.token
    cleos set contract eosio.msig ${EOS_CONTRACTS_DIR}/eosio.msig/bin/eosio.msig
    cleos push action eosio.token create '["eosio", "10000000000.0000 EOS"]' -p eosio.token
    cleos push action eosio.token issue '["eosio", "1000000000.0000 EOS", "memo"]' -p eosio
    cleos set contract eosio ${EOS_CONTRACTS_DIR}/eosio.system/bin/eosio.system
    cleos push action eosio setpriv '["eosio.msig", 1]' -p eosio@active

    if ! eosio_init_accounts ${KEYS_USERS} use_system_contract "16000000.0000 EOS"; then
        printf "error: could not create user accounts\n"
        return 1
    fi
    if ! eosio_init_accounts ${KEYS_PRODUCERS} use_system_contract "100.0000 EOS" reg_producer; then
        printf "error: could not create producer accounts\n"
        return 1
    fi

    while read voter_ln; do
        voter=$(echo ${voter_ln} | cut -d ' ' -f 1)
        while read producer_ln; do
            producer=$(echo ${producer_ln} | cut -d ' ' -f 1)
            cleos system voteproducer approve ${voter} ${producer} || break
        done < ${KEYS_PRODUCERS}
    done < ${KEYS_USERS}

    # resign eosio
    cleos push action eosio updateauth '{"account": "eosio", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio.prods", "permission": "active"}}]}}' -p eosio@owner
    cleos push action eosio updateauth '{"account": "eosio", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio.prods", "permission": "active"}}]}}' -p eosio@active
}

eosio_init_contract()
{
    CONTRACT_DIR=$1 ; shift
    CONTRACT_NAME=$1 ; shift

    PWD=$(pwd)
    cd ${CONTRACT_DIR}

    if prompt_input_yN "generate abi"; then
        eosiocpp -g ${CONTRACT_NAME}.abi ${CONTRACT_NAME}.cpp || return 1
    fi
    if prompt_input_yN "build contract"; then
        eosiocpp -o ${CONTRACT_NAME}.wast ${CONTRACT_NAME}.cpp || return 1
    fi
    if prompt_input_yN "deploy contract"; then
        eosio_unlock_wallet || { printf "error: could not unlock wallet\n"; return 1 }
        cleos set contract ${CONTRACT_NAME} . ${CONTRACT_NAME}.wast ${CONTRACT_NAME}.abi -p ${CONTRACT_NAME}
    fi

    cd ${PWD}
}

