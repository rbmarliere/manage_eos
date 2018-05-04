#!/bin/sh

EOS_CONTRACTS_DIR=~/git/eos/build/contracts
WALLET_PASSWORD=$(cat ~/eos_xbl_dawn3/wallet/default.passwd)
KEYS_FILE=~/git/manage_eos/keys

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

eos_unlock_wallet()
{
    if [ "$(eosc wallet list | grep '*')" = "" ]; then
        eosc wallet unlock --password=${WALLET_PASSWORD}
    fi
}

eos_init_accounts()
{
    imported=$(eosc wallet keys)
    while read line ; do
        name=$(echo ${line} | cut -d ' ' -f 1)
        pubkey=$(echo ${line} | cut -d '"' -f 2)
        privkey=$(echo ${line} | cut -d '"' -f 4)
        if [ "$(echo ${imported} | grep ${privkey})" = "" ]; then
            eosc wallet import ${privkey}
        fi
        if [ "${name}" != "eosio" ]; then
            if [ "$(eosc get account ${name} | grep '"permissions": \[\]')" != "" ]; then
                eosc create account eosio ${name} ${pubkey} ${pubkey}
            fi
        fi
    done < ${KEYS_FILE}
}

eos_init_chain()
{
    eos_unlock_wallet
    eos_init_accounts

    eosc set contract eosio ${EOS_CONTRACTS_DIR}/eosio.bios -p eosio@active

    eosio=$(cat ${KEYS_FILE} | grep 'eosio ' | cut -d '"' -f 2)
    zaratustra=$(cat ${KEYS_FILE} | grep zaratustra | cut -d '"' -f 2)
    eosc push action eosio setprods '{"version":"1","producers":[{"producer_name":"eosio","block_signing_key":"'${eosio}'"},{"producer_name":"zaratustra","block_signing_key":"'${zaratustra}'"}]}' -p eosio@active

    eosc set contract eosio.token ${EOS_CONTRACTS_DIR}/eosio.token -p eosio.token@active
    eosc push action eosio.token create '{"issuer":"eosio", "maximum_supply":"1000000000.0000 EOS", "can_freeze":0, "can_recall":0, "can_whitelist":0}' -p eosio.token@active

    while read line; do
        name=$(echo ${line} | cut -d ' ' -f 1)
        if [ "${name}" != "eosio" ]; then
            eosc push action eosio.token issue '{"to":"'${name}'","quantity":"100000.0000 EOS","memo":"memo"}' -p eosio@active
        fi
    done < ${KEYS_FILE}
}

eos_init_contract()
{
    CONTRACT=$1 ; shift

    PWD=$(pwd)
    cd ~/git/${CONTRACT}

    if prompt_input_yN "generate abi"; then
        eoscpp -g ${CONTRACT}.abi ${CONTRACT}.cpp || return 1
    fi
    if prompt_input_yN "build contract"; then
        eoscpp -o ${CONTRACT}.wast ${CONTRACT}.cpp || return 1
    fi
    if prompt_input_yN "deploy contract"; then
        eos_unlock_wallet
        eosc set contract ${CONTRACT} . ${CONTRACT}.wast ${CONTRACT}.abi -p ${CONTRACT}@active
    fi

    cd ${PWD}
}

