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

Prepared artifacts:

- `network/mimir/bond.yaml.tmpl`: native BondConfig. Render address and full routes
  from a fresh live LinkConfig into a private candidate; replace that physical
  LinkConfig and preserve every other document and credential semantically.
- `network/bifrost/mimir-lacp-secondary.cfg`: prepare the unused logical bundle
  and only the secondary member. Requires confirmed NIC-to-port mapping.
- `network/bifrost/mimir-lacp-primary.cfg`: add the primary member only after
  the host bond is reachable through the secondary member.

Do not apply the switch fragments as one concatenated batch. First validate the
full private Talos candidate with the release-matched client and perform an
authenticated `apply-config --dry-run --mode no-reboot`. A successful dry-run is
not authorization for a real host network change.

After explicit host-side approval, stage only the secondary switch member and
verify the primary access path still works. If it does not, restore the secondary
port's previous standalone access configuration before proceeding. Apply the
host candidate using supported `try` mode with a bounded five-minute rollback
window; retain an independent management path to the switch. Confirm the host
address, APIs and the secondary bond member, then join the primary switch member.
Check both collecting/distributing members and the APIs again. Commit the host
candidate using `no-reboot` only after successful checks, before the trial expires.
Read back the actual host machine configuration and network state afterward.

If the trial fails or its deadline is approaching without conclusive verification,
restore both switch members to the captured standalone access state and allow
Talos to revert. Do not leave the old physical-interface host configuration facing
an LACP-only switch bundle. Record actual trial timing locally; never assume
that issuing a command means it was accepted or that a disconnect proves rollback.

The host-side bond and switch member configuration must be coordinated. Do not
leave the primary link suspended waiting for a host bond that has not been
applied. Reconfirm live configuration has not drifted from the private candidate's
baseline immediately before each stage.

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
