#!/bin/sh
LISTEN=${1:-8443}
DEST=${2:-8080}
SVC=${3:-stunnel}

echo > ${SVC}.conf "
foreground = yes
syslog = no

[https]
accept = $LISTEN
connect = $DEST
cert = ${SVC}.pem
"

if [ ! -f ${SVC}.pem ]; then
	touch ${SVC}.key ${SVC}.crt ${SVC}.pem
	chmod 600 ${SVC}.key ${SVC}.crt ${SVC}.pem

	# openssl genrsa -out isn't playing nice ... wth?
	# FIXME: use genpkey
	openssl genrsa 4096 > ${SVC}.key
	# params on cmdline?
	yes '' | openssl req -new -key ${SVC}.key -x509 -days 90 -out ${SVC}.crt
	cat ${SVC}.key ${SVC}.crt > ${SVC}.pem
	rm ${SVC}.key ${SVC}.crt
	trap "rm ${SVC}.pem" EXIT
fi

stunnel ${SVC}.conf
