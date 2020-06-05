#!/bin/bash -x

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Copyright 2020 Joyent, Inc.

# If the redis-sentinel service is already exists, everything should be ok.
svcs -H redis-sentinel && exit 0

export PATH=/opt/local/bin:/opt/local/sbin:$PATH

if [[ -n "$TRACE" ]]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

function stack_trace
{
    set +o xtrace

    (( cnt = ${#FUNCNAME[@]} ))
    (( i = 0 ))
    while (( i < cnt )); do
        printf '  [%3d] %s\n' "${i}" "${FUNCNAME[i]}"
        if (( i > 0 )); then
            line="${BASH_LINENO[$((i - 1))]}"
        else
            line="${LINENO}"
        fi
        printf '        (file "%s" line %d)\n' "${BASH_SOURCE[i]}" "${line}"
        (( i++ ))
    done
}

function fatal
{
    # Disable error traps from here on:
    set +o xtrace
    set +o errexit
    set +o errtrace
    trap '' ERR

    echo "$(basename "$0"): fatal error: $*" >&2
    stack_trace
    exit 1
}

function trap_err
{
    st=$?
    fatal "exit status ${st} at line ${BASH_LINENO[0]}"
}


# We set errexit (a.k.a. "set -e") to force an exit on error conditions, but
# there are many important error conditions that this does not capture --
# first among them failures within a pipeline (only the exit status of the
# final stage is propagated).  To exit on these failures, we also set
# "pipefail" (a very useful option introduced to bash as of version 3 that
# propagates any non-zero exit values in a pipeline).
#
set -o errexit
set -o pipefail

shopt -s extglob

#
# Install our error handling trap, so that we can have stack traces on
# failures.  We set "errtrace" so that the ERR trap handler is inherited
# by each function call.
#
trap trap_err ERR
set -o errtrace

token=$(mdata-get redis_token)

svc_name="$(mdata-get svc_name)"
network_name="$(mdata-get network_name)"
dns_domain=$(mdata-get sdc:dns_domain)
svc_domain="${dns_domain/inst/svc}"

peers=()
while IFS='' read -r line; do peers+=("$line"); done < <(
    dig +short "${network_name}.${svc_name}.${svc_domain}"
)
self=$(mdata-get sdc:nics | json -ac 'this.nic_tag.match(/sdc_overlay/)' ip)

mkdir -p /opt/custom/smf

init_patch="--- redis.conf.orig     2020-06-05 00:06:18.624559468 +0000
+++ redis.conf  2020-06-05 00:06:19.907257042 +0000
@@ -66,7 +66,6 @@
 # IF YOU ARE SURE YOU WANT YOUR INSTANCE TO LISTEN TO ALL THE INTERFACES
 # JUST COMMENT THE FOLLOWING LINE.
 # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-bind 127.0.0.1

 # Protected mode is a layer of security protection, in order to avoid that
 # Redis instances left open on the internet are accessed and exploited.
@@ -290,7 +289,7 @@
 # starting the replication synchronization process, otherwise the master will
 # refuse the replica request.
 #
-# masterauth <master-password>
+masterauth $token

 # When a replica loses its connection with the master, or when the replication
 # is still in progress, the replica can act in two different ways:
@@ -504,7 +503,7 @@
 # 150k passwords per second against a good box. This means that you should
 # use a very strong password otherwise it will be very easy to break.
 #
-# requirepass foobared
+requirepass $token

 # Command renaming.
 #"

# shellcheck disable=2140
join_patch="
--- redis.conf.orig     2020-06-05 00:29:19.579442594 +0000
+++ redis.conf  2020-06-05 00:31:20.794894837 +0000
@@ -66,7 +66,6 @@
 # IF YOU ARE SURE YOU WANT YOUR INSTANCE TO LISTEN TO ALL THE INTERFACES
 # JUST COMMENT THE FOLLOWING LINE.
 # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-bind 127.0.0.1

 # Protected mode is a layer of security protection, in order to avoid that
 # Redis instances left open on the internet are accessed and exploited.
@@ -284,6 +283,7 @@
 #    and resynchronize with them.
 #
 # replicaof <masterip> <masterport>
+replicaof ${peers[0]} 6379

 # If the master is password protected (using the "requirepass" configuration
 # directive below) it is possible to tell the replica to authenticate before
@@ -291,6 +291,7 @@
 # refuse the replica request.
 #
 # masterauth <master-password>
+masterauth $token

 # When a replica loses its connection with the master, or when the replication
 # is still in progress, the replica can act in two different ways:
@@ -505,6 +506,7 @@
 # use a very strong password otherwise it will be very easy to break.
 #
 # requirepass foobared
+requirepass $token

 # Command renaming.
 #"

if (( ${#peers[@]} == 0 )); then
	primary="$self"
	patch="$init_patch"
else
	primary="${peers[0]}"
	patch="$join_patch"
fi

pkgin -y install redis tmux

patch /opt/local/etc/redis.conf <<< "$patch"

cat > /opt/local/etc/sentinel.conf << EOF
bind $self
port 26379
daemonize yes
dir /var/db/redis
pidfile /var/db/redis/sentinel.pid
logfile /var/log/redis/sentinel.log

sentinel monitor $svc_name $primary 6379 2
sentinel auth-pass $svc_name $token
sentinel down-after-milliseconds $svc_name 10000
sentinel parallel-syncs $svc_name 1
EOF

cat > /opt/custom/smf/redis-sentinel.xml << EOF
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<!-- This Source Code Form is subject to the terms of the Mozilla Public
   - License, v. 2.0. If a copy of the MPL was not distributed with this
   - file, You can obtain one at https://mozilla.org/MPL/2.0/. -->
<service_bundle type="manifest" name="export">
  <service name="pkgsrc/redis-sentinel" type="service" version="1">
    <create_default_instance enabled="false" />
    <single_instance />
    <dependency name="network" grouping="require_all" restart_on="error" type="service">
      <service_fmri value="svc:/milestone/network:default" />
    </dependency>
    <dependency name="filesystem" grouping="require_all" restart_on="error" type="service">
      <service_fmri value="svc:/system/filesystem/local" />
    </dependency>
    <method_context working_directory="/var/db/redis">
      <method_credential user="redis" group="redis" />
    </method_context>
    <exec_method type="method" name="start" exec="/opt/local/bin/redis-server %{config_file} --sentinel" timeout_seconds="60" />
    <exec_method type="method" name="stop" exec=":kill" timeout_seconds="60" />
    <property_group name="startd" type="framework">
      <propval name="duration" type="astring" value="contract" />
      <propval name="ignore_error" type="astring" value="core,signal" />
    </property_group>
    <property_group name="application" type="application">
      <propval name="config_file" type="astring" value="/opt/local/etc/sentinel.conf" />
    </property_group>
    <template>
      <common_name>
        <loctext xml:lang="C">Redis server</loctext>
      </common_name>
    </template>
  </service>
</service_bundle>
EOF

chown redis:redis /opt/local/etc/{redis,sentinel}.conf

svccfg import /opt/custom/smf/redis-sentinel.xml
svcadm enable redis-sentinel
sleep 2
svcadm enable redis
mdata-delete triton.cns.status
