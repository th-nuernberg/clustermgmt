#!/bin/bash

# fail on warn/error
set -eu

# user that we're trying to authenticate
cn=$1

# load secret: $ldap_bind, $ldap_pass, $ldap_base
source /usr/local/etc/userkeys.secret

# retrieve any public key stored for that user
keys=$(ldapsearch -D ${ldap_bind} -x -w ${ldap_pass} -b ${ldap_base} -o ldif-wrap=no -s sub "(&(objectClass=posixAccount)(uid=$cn))" | sed -n 's/^[ \t]*sshPublicKey:[ \t]*\(.*\)/\1/p')

# check for base64 encoding (eg. multiple keys), remove any empty lines
if [[ "$keys" =~ ^:[[:space:]]* ]]; then
  echo "base64 detected, decoding"
  keys=$(echo $keys | sed 's/^:[ \t]*//' | base64 -d | sed -r '/^\s*$/d')
fi

# print those keys; must have quotes to retain newlines
echo "$keys"

exit 0
