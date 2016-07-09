#!/bin/sh
SVC=stunnel
LISTEN=8443
DEST=8080

echo > ${SVC}.conf "
foreground = yes
syslog = no

[https]
accept = $LISTEN
connect = $DEST
cert = ${SVC}.pem
"

touch ${SVC}.key ${SVC}.crt ${SVC}.pem
chmod 600 ${SVC}.key ${SVC}.crt ${SVC}.pem

# openssl genrsa -out isn't playing nice ... wth?
# FIXME: use genpkey
openssl genrsa 4096 > ${SVC}.key
# params on cmdline?
yes '' | openssl req -new -key ${SVC}.key -x509 -days 90 -out ${SVC}.crt
cat ${SVC}.key ${SVC}.crt > ${SVC}.pem

stunnel ${SVC}.conf
