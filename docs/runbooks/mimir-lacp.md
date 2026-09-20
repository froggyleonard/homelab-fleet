# Mimir LACP migration

## Scope and authority

I intend to aggregate the two Mimir cables on GigabitEthernet0/2 and
GigabitEthernet0/4 with LACP, keeping the existing untagged access VLAN 100.
This is not a VLAN-trunking change. The OPNsense bundle and all other physical
ports are out of scope. Port changes require operator approval; any host-side
network migration needs its own reviewed configuration and recovery path.

No addresses, MACs, raw device state, credentials or rendered Talos machine
configuration belong in this public repository. Keep evidence and private
inventory outside Git. This procedure is manually applied from reviewed source;
there is no automatic switch reconciler attached to these files.

## Stage 1: recover one link

Before applying `network/bifrost/mimir-recovery.cfg`:

1. Confirm the expected switch identity, privilege and current interface state.
2. Privately capture complete running/startup configuration, interface state,
   VLAN and aggregation state. Preserve unrelated pending changes.
3. Confirm VLAN 100 exists and is forwarding on the upstream bundle.
4. Confirm the target interface is not a member of another aggregation.

Apply the recovery commands one at a time and inspect every response. They
change only Gi0/2 to explicit access mode and VLAN 100. They do not enable
PortFast, remove a channel group, shut a port, create a trunk or save the entire
running configuration. Do not modify Gi0/4 in this first stage.

Read back the exact interface, operational VLAN and link state. Verify the
other target port and protected uplinks are unchanged. Test the expected node's
Kubernetes and Talos endpoints from the management seat. Allow for normal STP
convergence; do not bounce a port to hurry recovery.

If the intended host does not respond, stop and investigate. Confirm the first
port is forwarding VLAN 100 and there are no unexpected bundles or host bridges.
When both cables are confirmed to belong to Mimir and approval covers both
ports, `network/bifrost/mimir-recovery-secondary.cfg` can restore the second link
to standalone access VLAN 100 to discover which NIC carries the configured host
address. Capture a new baseline, preserve the first port and all unrelated
configuration, then repeat API/link checks. This is conditional recovery, not
LACP enrollment. Do not invent host NIC names or continue to an aggregate while
the host remains unreachable.

### Recovery-stage rollback

Only if the captured pre-change interface was completely default, restore it
using `no switchport access vlan` and `no switchport mode` within that interface.
Otherwise reverse the exact approved delta to the captured prior state. Read
back and compare the full configuration outside the target stanza. Do not use
`default interface`, reload, or change the upstream bundle. Leave startup alone
until a scoped save is reviewed and approved.

## Stage 2: inspect the host and prepare the bond

After recovery, use authenticated read-only Talos queries to identify the node,
actual NIC names, permanent MACs, physical link state, driver/speed and existing
network configuration. Correlate these with both switch ports. Do not assume
that both connectors are the same type of NIC or that the second connector is
an enabled Ethernet interface.

Prepare a release-appropriate native Talos BondConfig in 802.3ad mode, moving
the existing address and default route from the physical interface to the bond.
Preserve every unrelated machine configuration document and all credential
material. Check per-link DHCP/static configuration so an obsolete physical-link
address cannot remain active alongside the bond. Keep the desired address and
other deployment-specific values in private inventory.

Choose an unused Cisco channel-group/port-channel ID. Both member ports and
the resulting logical interface must agree on Layer-2 access mode and VLAN 100.
Use LACP rather than static `on` or PAgP. Do not copy settings from the unrelated
firewall trunk. Do not change the switch-wide load-balancing policy as part of
this task.

Validate the exact host schema with the installed release-matched Talos client.
Review the host-side application mode and interruption risk; do not assume
rollback after a network change is automatic. Require independent recovery or
a verified supported timed rollback before the coordinated cutover. Do not
apply the full host configuration blindly if it could introduce unrelated drift.

## Stage 3: coordinated cutover and acceptance

The host-side bond and switch member configuration must be coordinated. Do not
leave the primary link suspended waiting for a host bond that has not been
applied. Work out the exact sequencing from observed platform behavior before
applying the final configuration.

Required acceptance checks:

- Both physical members are bundled in the intended LACP port-channel.
- Both peers report the same active aggregate and collecting/distributing links.
- The logical interface remains an access port in VLAN 100, not a trunk.
- The existing node address, Kubernetes/Talos APIs and intended workloads recover.
- Protected uplinks and unrelated ports/configuration are unchanged.
- Running and startup configuration contain the intended switch configuration;
  review unrelated running/startup differences before saving.
- Host configuration persistence is verified without an unapproved reboot.

Cable-pull or interface-shutdown failover tests are disruptive and need explicit
approval. Distinguish a successfully configured bond from verified failover.
If anything fails, report exactly which side changed, what remains reachable,
and whether it was saved. Restore only the reviewed delta via the recovery path.
