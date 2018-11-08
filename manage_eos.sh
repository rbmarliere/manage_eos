#!/bin/bash

EOS_CONTRACTS_DIR=${USER_GIT_ROOT}/eosio.contracts/build
KEYS_PRODUCERS=$(dirname "$0")/keys.producers
KEYS_SYSTEM=$(dirname "$0")/keys.system
KEYS_USERS=$(dirname "$0")/keys.users

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

eosio_unlock_wallet()
{
    WALLET=${WALLET:-local}
    WALLET_PASSWORD=$(cat ~/eosio-wallet/${WALLET}.passwd)
    if [ "$(cleos wallet list | grep ${WALLET}' \*')" = "" ]; then
        cleos wallet unlock -n ${WALLET} --password=${WALLET_PASSWORD} || return 1
    fi
}

eosio_init_accounts()
{
    if ! prompt_input_yN "create accounts"; then
        return 0
    fi

    if ! eosio_unlock_wallet; then
        printf "error: could not unlock wallet\n"
        return 1
    fi

    WALLET=${WALLET:-local}
    keys=${1:-${KEYS_SYSTEM}}
    use_system_contract=${2:-"no"}
    amount=${3:-"1.0000 EOS"}
    reg_producer=${4:-"no"}
    issue_amount=${5:-"no"}

    imported=$(cleos wallet keys)

    while read line; do
        name=$(echo ${line} | cut -d ' ' -f 1)
        pubkey=$(echo ${line} | cut -d ' ' -f 2)
        privkey=$(echo ${line} | cut -d ' ' -f 3)

        if [ "$(echo ${imported} | grep ${pubkey})" = "" ]; then
            cleos wallet import -n ${WALLET} --private-key ${privkey} || return 1
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

        if [ "${issue_amount}" != "no" ]; then
            cleos push action eosio.token issue '["'${name}'", "'${issue_amount}'", "memo"]' -p eosio
        fi
    done < ${keys}
}

eosio_init_chain()
{
    if ! eosio_init_accounts; then
        printf "error: could not create system accounts\n"
        return 1
    fi

    cleos set contract eosio.token ${EOS_CONTRACTS_DIR}/eosio.token
    cleos set contract eosio.msig ${EOS_CONTRACTS_DIR}/eosio.msig
    cleos push action eosio.token create '["eosio", "10000000000.0000 EOS"]' -p eosio.token
    cleos push action eosio.token issue '["eosio", "1000000000.0000 EOS", "memo"]' -p eosio
    cleos set contract eosio ${EOS_CONTRACTS_DIR}/eosio.system
    cleos push action eosio init '[0,"4,EOS"]' -p eosio
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
        producers=$(tail -n 30 ${KEYS_PRODUCERS} | cut -d ' ' -f 1 | tr '\n' ' ')
        eval cleos system voteproducer prods ${voter} ${producers} || break
    done < ${KEYS_USERS}

    # resign eosio
    cleos push action eosio updateauth '{"account": "eosio", "permission": "owner", "parent": "", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio.prods", "permission": "active"}}]}}' -p eosio@owner
    cleos push action eosio updateauth '{"account": "eosio", "permission": "active", "parent": "owner", "auth": {"threshold": 1, "keys": [], "waits": [], "accounts": [{"weight": 1, "permission": {"actor": "eosio.prods", "permission": "active"}}]}}' -p eosio@active
}

eosio_deploy_contract()
{
    ACCOUNT=$1 ; shift
    CONTRACT_DIR=$1 ; shift

    pushd ${CONTRACT_DIR}

    if ! eosio_unlock_wallet; then
        printf "error: could not unlock wallet\n"
        return 1
    fi

    wasm=$(find . -name *.wasm | egrep "*" || echo not_found)
    abi=$(find . -name *.abi | egrep "*" || echo not_found)
    if [ "${wasm}" = "not_found" ] || [ "${abi}" = "not_found" ]; then
        printf "error: could not find wasm or abi.\n"
        return 1
    fi

    if ! cleos set contract ${ACCOUNT} . ${wasm} ${abi} -p ${ACCOUNT}; then
        printf "error: could not set contract.\n"
        if ! prompt_input_yN "continue"; then
            popd
            return 1
        fi
    fi

    popd
}

eosio_set_code_permission()
{
    # https://eosio.stackexchange.com/questions/1621/require-inline-action-be-sent-by-contract-and-not-account

    ACCOUNT=$1 ; shift
    PUBKEY=$1 ; shift

    cleos set account permission $ACCOUNT active '{"threshold": 1,"keys": [{"key": "'$PUBKEY'","weight": 1}],"accounts": [{"permission":{"actor":"'$ACCOUNT'","permission":"eosio.code"},"weight":1}]}' owner -p $ACCOUNT
}

