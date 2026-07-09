#!/bin/bash

#################################################################
# This script is used to create a self signed root CA and 
# certificate.  It is as automatic as possible gathering your
# internal and external ip addresses.  In addition, it uses a
# ip to location service to get your country, state and locality.
#
# The script creates 3 files that Analog_Reflector needs to 
# create secure websockets between hUC and the reflector.
#################################################################


# Initialize some variables with default values
COUNTRY=US
STATE=Georgia
LOCALITY=Atlanta

# And some more generic DVSwitch names
CERTNAME=dvswitch
ORG_NAME=DVSwitch
ORG_UNIT=Server

#################################################################
# Run through the ifconfig output looking for ip addresses
# Returns any non-loopback one for a network interface
#################################################################
function getMyIP() {
    declare _ip _line
    while IFS=$': \t' read -a _line ;do
        [ -z "${_line%inet}" ] &&
           _ip=${_line[${#_line[1]}>4?1:2]} &&
           [ "${_ip#127.0.0.1}" ] && echo $_ip && return 0
      done< <(LANG=C /sbin/ifconfig)
}

function verifyCertificate() {
    # Verify the certificate
    echo "**************************************************************************************"
    echo "Summary:"
    echo "**************************************************************************************"
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep Version
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep Serial
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep Issuer
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep Validity
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep "Not Before"
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep "Not After"
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep "Subject:"
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep -A3 "X509v3"
    openssl x509 -in ${CERTNAME}.crt -text -noout | grep DNS
    #openssl x509 -in ${CERTNAME}.crt -text -noout
    echo "**************************************************************************************"
}

if [ ! -z $1 ] && [ $1 == -show ]; then
    verifyCertificate
    exit 0
fi

# Get the CN and test to make sure it seems valid
CN=$(hostname -f)
if [ $CN == localhost ]; then
    CN=$(hostname)
fi

# Get a internal and external (public) ip address for this machine
declare localip=`getMyIP`
declare ip=$(curl -s ifconfig.me)
declare ipfromhost=$(host $CN 8.8.8.8 | awk '/has address/ { print $4 ; exit }')


# Use the public ip address to get a counrty, state and city name
declare json=$(curl -s -L https://ipapi.co/$ip/json | tr -d '\n')

# Use python to parse the json into values
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
    echo "Can not get country, state and locality, using placeholders."
fi

# Now, prepare the ip address entries of the CNF file
if [ $ip == $localip ]; then
    ips="\
IP.1 = 127.0.0.1
IP.2 = $localip"
else
    ips="\
IP.1 = 127.0.0.1
IP.2 = $localip
IP.3 = $ip"
fi

# Create the CNF file with all of the information gathered so far
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
$ips
" > ${CERTNAME}.cnf

#############################################################################
# Now for the real work, use all of the above to generate the 
# key, root CA and certificate.
#############################################################################

echo Generating self signed certificate, please wait.....

# Generate CA key
openssl genrsa -out ${CERTNAME}-ca.key 4096 2> /dev/null

# Generate CA certificate
openssl req -x509 -new -nodes -key ${CERTNAME}-ca.key -sha256 -days 365 -out ${CERTNAME}-ca.crt -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORG_NAME}/OU=${ORG_UNIT}/CN=${CN}" 2> /dev/null

# Generate server key
openssl genrsa -out ${CERTNAME}.key 4096 2> /dev/null

# Generate server certificate request
openssl req -new -key ${CERTNAME}.key -config ${CERTNAME}.cnf -out ${CERTNAME}.csr 2> /dev/null

# Verify the CSR
#openssl req -in ${CERTNAME}.csr -noout -text

# Issue the certificate
openssl x509 -req -in ${CERTNAME}.csr -CA ${CERTNAME}-ca.crt -CAkey ${CERTNAME}-ca.key -CAcreateserial -out ${CERTNAME}.crt -days 365 -sha256 -extfile ${CERTNAME}.cnf -extensions req_ext 2> /dev/null

verifyCertificate

if [ -z $ipfromhost ]; then
    echo "Your hostname \"$CN\" was not found" 
    echo "in a public DNS.  This means that you should access"
    echo "Analog_Reflector by using your public IP address \"$ip\" or"  
    echo "your internal IP \"$localip\"."     
else
    echo "Looks like your hostname \"$CN\"" 
    echo "is found in a public DNS.  This means that you should access"
    echo "Analog_Reflector by using your domain."     
fi
echo -e "\nYour certificate is now ready for use"
