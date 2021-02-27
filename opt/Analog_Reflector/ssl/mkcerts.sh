#!/bin/bash

#################################################################
#
#################################################################

CERTNAME=dvswitch

COUNTRY=US
STATE=Georgia
LOCALITY=Atlanta
ORG_NAME=DVSwitch
ORG_UNIT=Server
CN=$(hostname)

function getMyIP() {
    declare _ip _line
    while IFS=$': \t' read -a _line ;do
        [ -z "${_line%inet}" ] &&
           _ip=${_line[${#_line[1]}>4?1:2]} &&
           [ "${_ip#127.0.0.1}" ] && echo $_ip && return 0
      done< <(LANG=C /sbin/ifconfig)
}

declare localip=`getMyIP`
declare ip=$(curl -s ifconfig.me)
declare json=$(curl -s -L https://ipapi.co/$ip/json | tr -d '\n')

values=(`python3 - <<END
#!/usr/bin/env python
try:
    import json, os, sys
    data = '$json'
    json = json.loads(data)
    print(json['country'])
    print(json['region'])
    print(json['city'])
except:
    pass
END
`)
if [ ! -z "$values" ]; then
    COUNTRY=${values[0]}
    STATE=${values[1]}
    LOCALITY=${values[2]}
else
    echo "Can not get country, state and locality, aborting."
    exit 1
fi

echo "
[ req ]
prompt             = no
default_bits       = 4096
distinguished_name = req_distinguished_name
req_extensions     = req_ext
[ req_distinguished_name ]
countryName                = ${COUNTRY}
stateOrProvinceName        = ${STATE}
localityName               = ${LOCALITY}
organizationName           = ${ORG_UNIT}
commonName                 = ${CN}
[ req_ext ]
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
DNS.2 = $CN
IP.1 = $localip
IP.2 = 127.0.0.1
IP.3 = $ip
" > ${CERTNAME}.cnf

# Generate CA key
openssl genrsa -out ${CERTNAME}-ca.key 4096

# Generate CA certificate
openssl req -x509 -new -nodes -key ${CERTNAME}-ca.key -sha256 -days 365 -out ${CERTNAME}-ca.crt -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG_NAME}/OU=${ORG_UNIT}/CN=${CN}"

# Generate server key
openssl genrsa -out ${CERTNAME}.key 4096

# Generate server certificate request
openssl req -new -key ${CERTNAME}.key -config ${CERTNAME}.cnf -out ${CERTNAME}.csr

# Verify the CSR
openssl req -in ${CERTNAME}.csr -noout -text

# Issue the certificate
openssl x509 -req -in ${CERTNAME}.csr -CA ${CERTNAME}-ca.crt -CAkey ${CERTNAME}-ca.key -CAcreateserial -out ${CERTNAME}.crt -days 365 -sha256 -extfile ${CERTNAME}.cnf -extensions req_ext

# Verify the certificate
openssl x509 -in ${CERTNAME}.crt -text -noout
