<!-- This Source Code Form is subject to the terms of the Mozilla Public
   - License, v. 2.0. If a copy of the MPL was not distributed with this
   - file, You can obtain one at https://mozilla.org/MPL/2.0/. -->

# Redis Cluster Creator

The scripts in this repo will spawn redis instances in a cluster on Triton as
a tenant. This is not part of [Triton][triton] itself.

This depends on [`node-triton`][node-triton]. If you don't already have
`node-triton` installed you can run `make` to install it as a dependency.

[triton]: https://github.com/joyent/triton
[node-triton]: https://github.com/joyent/node-triton

## How to create a cluster

To create a new cluster, use the `spawn_redis_instance.sh` script to spawn
only **one** new instance. The `account` and `profile` parameters will default
to your current `triton` profile. All other parameters are required.

```shell
./spawn_redis_instance.sh -p profile -a account -n network -P prefix -t redis_token
    -p profile  A triton cli profile name
    -a account  Triton cli account
    -n network  Network Name
    -b bastion  Bastion instance name
    -P prefix   Prefix name to identify this cluster
    -t token    Secret token to authenticate this cluster
```

The `network` should be a *private* network, (ideally, a fabric network). The
`bastion` will be used to `ProxyJump` automatically when using `triton ssh`.
The bastion is a separate instance that needs to have a link on an external
network that you can ssh to, and a link on the network specified by the
`network` parameter.

After creating the first instance, verify it has bootstrapped properly
by `triton ssh`ing to it. If it looks good (there should be both redis and
sentinel SMF services running), then you can create additional instances.

The recomended minimum is 3 instances. Create as many as necessary to handle
the expected load but you should always have an odd number to guarantee that
a qorum can be established in the event of a network split.
