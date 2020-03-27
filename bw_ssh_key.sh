#!/bin/bash

set -e

key_prefix="bw_ssh_"
ttl="1h"
error=0
red='\033[0;31m'
yellow='\033[0;33m'
nc='\033[0m'

function help() {
  echo "Usage: $0 <list|generate|get_key|get_public_key> [-k key_name] [-t ttl] [-e encryption_type]"
  echo -e "\tlist\t\tList keys in vault"
  echo -e "\tsearch\t\tSearch for key name, useful if there are more than one matches"
  echo -e "\tgenerate\tGenerate new key to vault"
  echo -e "\tget_key\t\tGet private key to ssh-agent"
  echo -e "\tget_public_key\tget public key for the specified key"
  echo -e "\t-k|--key-name\tName for key, required for generating key or getting the key"
  echo -e "\t-i|--id\t\tUse key ID to fetch the key"
  echo -e "\t-n|--no-prefix\tDo not add key prefix"
  echo -e "\t-t|--ttl\tHow long private key should exist in agent, uses ssh-agent ttl syntax"
  echo -e "\t-e|--key-enc\tKey type, accepts rsa or ed25519"
  echo -e "\tAll required parameters will be asked unless specified with switch"
}

function generate_key() {
  tempdir=$(mktemp -d)
  mkfifo ${tempdir}/key

  while true
  do
    if [ -z "${key_type}" ]; then
      echo "Please provide key type, allowed values are rsa and ed25519:"
      read key_type
    fi

    if [ "${key_type}" == "rsa" ] || [ "${key_type}" == "ed25519" ]; then
      break
    else
      unset key_type
    fi
  done
  if [ "${key_type}" == "rsa" ]; then
    ssh-keygen -t rsa -b 4096 -f ${tempdir}/key -N ''>/dev/null 2>&1 <<< y > /dev/null&
  else
    ssh-keygen -t ed25519 -f ${tempdir}/key -N ''>/dev/null 2>&1 <<< y > /dev/null&
  fi
  private_key=''
  while read line; do
    if [ "$line" ]; then
      private_key+="$line\n"
    else
      break
    fi
  done < ${tempdir}/key
  public_key=$(cat ${tempdir}/key.pub)
  if [ -z "${key_name}" ]; then
    echo -n "Enter name for the key: "
    read key_name
  fi
  key_name=${key_name#"$key_prefix"}
  key_name="${key_prefix}${key_name}"
  payload="${private_key}\n${public_key}"
  rm -f ${tempdir}/key
  rm -f ${tempdir}/key.pub
  rmdir ${tempdir}
  response=$(echo "{\"organizationId\":null,\"folderId\":null,\"type\":2,\"name\":\"${key_name}\",\"notes\":\"${payload}\",\"favorite\":false,\"login\":null,\"secureNote\":{\"type\":0},\"card\":null,\"identity\":null}"|bw encode|bw create item)
  if [ $? == 0 ]; then
    echo -n "Created new item: "
    echo ${response}|jq .id
    echo -n "Item name: "
    echo ${response}|jq .name
    echo "Public key: ${public_key}"
  fi
}

function list_keys() {
  bw list items --search ${key_prefix}|jq '[.[] | "\(.name) (\(.id))"]'
}

function search() {
  if [ -n "${key_id}" ]; then
    key_name="${key_id}"
  elif [ -z "${key_name}" ]; then
    echo -n "Enter searched key name: "
    read key_name
  fi
  bw list items --search "${key_name}"|jq '[.[] | "\(.name) (\(.id))"]'
}

function get_item() {
  if [ -n "${key_id}" ]; then
    key_name="${key_id}"
  elif [ -z "${key_name}" ]; then
    echo -n "Enter searched key name: "
    read key_name
  fi
  if [ -z "${no_prefix}" ]; then
    key_name=${key_name#"$key_prefix"}
    key_name="${key_prefix}${key_name}"
  fi
  result=$(bw get item "${key_name}")
  if [ $? == 0 ]; then
    return
  else
    echo "You need to be more specific on the key name, the key you entered matches this list:"
    bw list items --search "${key_name}"|jq .[].name
  fi

}

command -v bw >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}bitwarden cli${nc} is required, but not installed";error=1; }
command -v jq >/dev/null 2>&1 || { echo -e >&2 "${red}ERROR: ${yellow}jq${nc} is required, but not installed";error=1; }
if [ "${error}" == 1 ]; then
  echo "Please fix errors above, aborting"
  exit 1
fi

if [ $# -eq 0 ]; then
  help
  exit 1
fi

while [[ $# -gt 0 ]]
  do
    opt="$1"
    case $opt in
      -k|--key-name)
        key_name="$2"
        shift
        shift
      ;;
      -i|-id)
        key_id="$2"
        no_prefix=true
        shift
        shift
      ;;
      -n|--no-prefix)
        no_prefix=true
        shift
      ;;
      -t|--ttl)
        ttl="$2"
        shift
        shift
      ;;
      -e|--key-enc)
        key_type="$2"
        shift
        shift
      ;;
      -h|--help)
        help
        exit 0
      ;;
      get_public_key)
        get_public_key=true
        shift
      ;;
      get_key)
        get_key=true
        shift
      ;;
      list)
        list=true
        shift
      ;;
      generate)
        generate=true
        shift
      ;;
      search)
        search=true
        shift
      ;;
      *)
        echo "Unrecognized param: $1"
        shift
      ;;
  esac
done

## Check login status
bw login --check >/dev/null 2>&1
if [ $? != 0 ]; then
  bw login
fi

## Check for session variable
if [ -z "${BW_SESSION}" ]; then
  export BW_SESSION=$(bw unlock --raw)
fi

## Sync vault
bw sync

if [ "${generate}" == "true" ]; then
  generate_key
elif [ "${list}" == "true" ]; then
  list_keys
elif [ "${get_key}" == "true" ]; then
  get_item
  echo ${result}|jq -r '.notes'|grep -Ev "ssh-(rsa|ed25519)"|ssh-add -t ${ttl} -
elif [ "${get_public_key}" == "true" ]; then
  get_item
  echo ${result}|jq -r '.notes'|grep -E "ssh-(rsa|ed25519)"
elif [ "${search}" == "true" ]; then
  search
fi
