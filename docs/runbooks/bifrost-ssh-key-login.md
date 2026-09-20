# Bifrost SSH public-key enrollment

## Scope

I use a dedicated client key for unattended switch administration. This runbook
records the reviewed enrollment procedure, not evidence that deployment has
completed. Initial enrollment is operator-assisted through an existing trusted
session. This file is not connected to ArgoCD or an automatic switch deployer.

I retain password authentication. I do not change AAA, VTY lines, account
privileges, the SSH server key, interfaces, VLANs or firmware as part of this
change. The existing retired desktop key is removed only after the replacement
works and its removal is authorized.

## Private inputs and prerequisites

Keep all rendered commands, device addresses, actual key fingerprints, key
material and configuration snapshots outside this public repository. Angle-bracket
values below are placeholders, not executable configuration.

Required private inputs:

- Switch endpoint, existing account, independently verified host-key fingerprint.
- Existing public-key-chain stanza and its startup counterpart for rollback.
- Dedicated client RSA key in a client-compatible format and its public half.
- New public-key hash, existing retired key hash and existing key label.
- A trusted operator session kept open throughout enrollment and testing.

Check the exact image's command help for `ip ssh pubkey-chain` and inspect existing
entries before writing. Do not generate over an existing client key. Store the
private key outside Git with owner-only access. An unencrypted unattended key
makes protection of its local OS account part of the access boundary.

For classic IOS `key-hash`, derive the uppercase MD5 hexadecimal digest of the
base64-decoded SSH public-key blob. Do not substitute the SHA256 display
fingerprint or hash the textual public-key line. Independently check the key's
fingerprint and that the public half corresponds to the selected private key.
MD5 here is the legacy IOS public-key identifier, not a password hash.

## Enroll without first deleting the old key

After review and approval, enter each command on its own line from privileged
EXEC mode. Substitute private values locally:

```text
configure terminal
ip ssh pubkey-chain
username <EXISTING_ACCOUNT>
key-hash ssh-rsa <NEW_KEY_MD5_HEX> astra-bifrost
end
show running-config | section ^ip ssh pubkey-chain
```

Stop on errors or unexpected replacement of an existing entry. Read back the
exact stanza: the new hash must be present and the pre-existing key retained.
Do not save startup configuration yet.

## Verify a fresh non-interactive session

Use the dedicated key, batch mode, no agent fallback and the expected host key.
For reliable automation, prefer a prompt-synchronized PTY shell:

```bash
plink -batch -noagent -t -hostkey '<EXPECTED_HOSTKEY_SHA256>' \
  -i '<PRIVATE_PPK_PATH>' '<EXISTING_ACCOUNT>@<SWITCH_HOST>'
```

Drive this with a bounded expect-style client: wait for the exact device prompt,
send `terminal length 0`, wait for the prompt again, and send each inspection
command separately. Wait for the final prompt before sending `exit`, then wait
for EOF and check the client exit status. Keep raw session logging disabled.
A one-shot exec command or a batch piped all at once may return output and then
report an unexpected disconnect. Never globally suppress that error or treat
partial output as success; use the paced shell and explicit readbacks instead.

Test `show version`, `show privilege` and the targeted public-key stanza, including
checks through separate fresh sessions. Success requires the expected switch identity, no password or local
confirmation prompt, correct privilege for the requested work, and the intended
key entry. Verify a separate operator password login still works. Do not print
raw running configuration or any passwords/private keys to logs.

If this image rejects a second key, stop and use the separately reviewed
replacement procedure with the trusted session retained; do not improvise AAA
changes or silently delete an entry to make room.

## Retire the old entry and persist

Only after the replacement login succeeds and retirement is authorized:

```text
configure terminal
ip ssh pubkey-chain
username <EXISTING_ACCOUNT>
no key-hash ssh-rsa <RETIRED_KEY_MD5_HEX>
end
show running-config | section ^ip ssh pubkey-chain
```

Verify the new key remains, the retired entry is absent, and a fresh key-authenticated
session still succeeds. Never remove the entire username or public-key chain.

Saving copies the entire running configuration, not only this change. First
review unrelated running/startup differences privately and obtain approval to
persist their effects. Then, within that approved scope:

```text
copy running-config startup-config
show startup-config | section ^ip ssh pubkey-chain
```

Read back the exact saved stanza and test another new connection. Report running
and startup verification separately; do not reload the switch to test persistence.

## Rollback

Keep the original public-key stanza privately before making changes. In the
retained trusted session, restore the exact retired hash and original label if
it was removed, then remove only the new hash. Read back the result and verify
the original login path. Do not restore the whole running configuration by
merging startup into running, do not disable host-key validation and do not
reload. If the change was saved, persistence of rollback needs the same
whole-configuration review as enrollment.

## References

- [Cisco IOS SSH command reference: ip ssh pubkey-chain](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/security/d1/sec-d1-cr-book/sec-cr-i3.html)
- [Cisco SSH public-key authentication procedure](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/sec_usr_ssh/configuration/xe-16/sec-usr-ssh-xe-16-book/sec-secure-shell-v2.html)
- [Cisco explanation of the traditional IOS key-hash format](https://cisco.com/c/en/us/td/docs/routers/sdwan/26x-later/user-mgmt/user-mgmt-guide/authenticate/ssh-authent.html)

The latter references cover other software trains; validate this switch's own
help and live behavior rather than assuming all documented features apply.
