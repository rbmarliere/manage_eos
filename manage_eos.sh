#!/bin/sh

EOS_CONTRACTS_DIR=~/git/eos/build/contracts
KEYS_FILE=$(dirname "$0")/keys
WALLET_PASSWORD=$(cat ~/eosio-wallet/default.passwd)

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

eosio_unlock_wallet()
{
    if [ $# -gt 0 ]; then
        WALLET_PASSWORD=$(cat $1) ; shift
    fi
    if [ "$(cleos wallet list | grep '*')" = "" ]; then
        cleos wallet unlock --password=${WALLET_PASSWORD} || return 1
    fi
}

eosio_init_accounts()
{
    imported=$(cleos wallet keys)
    while read line ; do
        name=$(echo ${line} | cut -d ' ' -f 1)
        pubkey=$(echo ${line} | cut -d ' ' -f 2)
        privkey=$(echo ${line} | cut -d ' ' -f 3)
        if [ "$(echo ${imported} | grep ${pubkey})" = "" ]; then
            cleos wallet import ${privkey} || return 1
        fi
        if [ "${name}" != "eosio" ]; then
            cleos get account ${name} || cleos create account eosio ${name} ${pubkey} ${pubkey} || return 1
        fi
    done < ${KEYS_FILE}
}

eosio_init_chain()
{
    eosio_unlock_wallet || { printf "error: could not unlock wallet\n"; return 1 }
    eosio_init_accounts || { printf "error: coult not import accounts\n"; return 1 }

    cleos set contract eosio ${EOS_CONTRACTS_DIR}/eosio.bios -p eosio

    eosio=$(cat ${KEYS_FILE} | grep 'eosio ' | cut -d ' ' -f 2)
    zaratustra=$(cat ${KEYS_FILE} | grep zaratustra | cut -d ' ' -f 2)
    cleos push action eosio setprods '{"schedule":[{"producer_name":"eosio","block_signing_key":"'${eosio}'"},{"producer_name":"zaratustra","block_signing_key":"'${zaratustra}'"}]}' -p eosio

    cleos set contract eosio.token ${EOS_CONTRACTS_DIR}/eosio.token -p eosio.token
    cleos push action eosio.token create '{"issuer":"eosio", "maximum_supply":"1000000000.0000 EOS", "can_freeze":0, "can_recall":0, "can_whitelist":0}' -p eosio.token

    while read line; do
        name=$(echo ${line} | cut -d ' ' -f 1)
        if [ "${name}" != "eosio" ]; then
            cleos push action eosio.token issue '{"to":"'${name}'","quantity":"100000.0000 EOS","memo":"memo"}' -p eosio
        fi
    done < ${KEYS_FILE}
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

