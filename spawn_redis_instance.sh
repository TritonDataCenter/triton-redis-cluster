#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Copyright 2020 Joyent, Inc.

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

top="$(dirname "$0")"
export PATH=${top}/node_modules/.bin:$PATH

function usage () {
    printf '%s -p profile -a account -n network -P prefix -t redis_token\n' "$0"
    printf '\t-p profile\tA triton cli profile name\n'
    printf '\t-a account\tTriton cli account\n'
    printf '\t-n network\tNetwork Name\n'
    printf '\t-b bastion\tBastion instance name\n'
    printf '\t-P prefix\tPrefix name to identify this cluster\n'
    printf '\t-t token\tSecret token to authenticate this cluster\n'
    exit "$1"
}

while getopts "a:b:n:P:p:t:h" options; do
   case $options in
      a ) account=(-a "${OPTARG}");;
      b ) bastion="${OPTARG}";;
      n ) network="${OPTARG}";;
      P ) prefix="${OPTARG}";;
      p ) profile=(-p "${OPTARG}");;
      t ) token="${OPTARG}";;
      h ) usage 0 ;;
      * ) usage 1 ;;
   esac
done

network_name=$( tr '_A-Z' '-a-z' <<< "${network:?}" )
svc_name="${prefix:?}-redis"

triton "${profile[@]}" "${account[@]}" inst create \
  base-64-lts@19.4.0 g4-highcpu-4G \
  --name="${prefix:?}-redis-{{shortId}}" --network="${network:?}" \
  -m redis_token="${token:?}" \
  -m network_name="${network_name}" \
  -m svc_name="${svc_name:?}" \
  -m triton.cns.status=down \
  -t tritoncli.ssh.proxy="${bastion:?}" \
  -t triton.cns.services="${svc_name:?}" \
  -w --script=redis_user-script.sh
