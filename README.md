# ldap-sshkp

LDAP-backed OpenSSH key provider written in Haskell.
Intended to be a replacement for [goklp](https://github.com/AppliedTrust/goklp).

## Usage

```
$ ldap-sshkp--help
ldap-sshkp v0.1.0.0, (C) Carl Richard Theodor Schneider

ldap-sshkp [OPTIONS] USER
  Fetches SSH public keys for USER from the specified LDAP

LDAP settings:
  -h --host=ITEM        LDAP Hostname (Default: localhost)
  -p --port=NAT         LDAP port (Default: 368)
     --usetls           Uses TLS for LDAP connection
     --useinsecuretls   Do not verify TLS certificates
     --binddn=ITEM      DN used to bind against LDAP
     --bindpass=ITEM    Password used for binding
Search Settings:
     --basedn=ITEM      DN used as base for searching
  -s --searchattr=ITEM  Attribute for matching (Default: uid)
  -v --valueattr=ITEM   Attribute containing public keys (Default:
                        sshPublicKey)
  -t --timeout=INT      Timeout for LDAP search
Search Scopes (Only one possible):
     --single-level     Constrain search to immediate subordinates of baseDN
                        (Default)
     --base-object      Constrain search to the baseDN
     --whole-subtree    Constrain search to all subordinates of baseDN
  -? --help             Display help message
  -V --version          Print version information
     --numeric-version  Print just the version number

ldap-sshkp fetches SSH public keys from LDAP.
```

## Use in OpenSSH

The intended use of this helper utility is with the `AuthorizedKeysCommand` 
setting for `sshd` from OpenSSH.

Wrapping one or multiple calls to `ldap-sshkp` in a script with appropriate 
permissions allows OpenSSH to fetch the SSH public keys from LDAP, while keeping
the password used for binding against LDAP in a separate file (which needs to be
accessible only for `AuthorizedKeysCommandUser`).

### `sshd_config`

```
AuthorizedKeysCommandUser nobody
AuthorizedKeysCommand /etc/ssh/openssh-authorized-keys
```

### `/etc/ssh/openssh-authorized-keys`
```sh
#!/usr/bin/bash
set -o errexit
set -o nounset
set -o pipefail

ldap-sshkp \
  --host=localhost \
  --port=389 \
  --binddn="cn=openssh,dc=example,dc=org" \
  --bindpass="$(cat /path/to/passwordfile/accessible/for/nobody)" \
  --basedn="ou=posix,dc=example,dc=org" \
  --searchattr="uid" \
  --valueattr="sshPublicKey" \
  --timeout=10 \
  --single-level \
  "$1";
```
