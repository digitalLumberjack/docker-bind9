#!/bin/bash
BIND9_TTL_REFRESH=${BIND9_TTL_REFRESH:-604800}
BIND9_TTL_RETRY=${BIND9_TTL_RETRY:-86400}
BIND9_TTL_EXPIRE=${BIND9_TTL_EXPIRE:-2419200}
BIND9_TTL_MINIMUM=${BIND9_TTL_MINIMUM:-604800}

if [[ ! -f /var/run/.stamp_installed ]]; then
  BIND9_KEY_ALGORITHM=${BIND9_KEY_ALGORITHM-"hmac-sha512"} # other options are in manpage for named.conf - hmac-md5, hmac-sha1, hmac-sha512
  if [[ -z "${BIND9_ROOTDOMAIN}" ]];then
    echo "The variable BIND9_ROOTDOMAIN must be set"
    exit 1
  fi
  if [[ -z "${BIND9_KEYNAME}" ]];then
    echo "The variable BIND9_KEYNAME must be set"
    exit 1
  fi
  if [[ -z "${BIND9_KEY}" ]];then
    echo "The variable BIND9_KEY must be set"
    exit 1
  fi
  if [[ -z "${BIND9_IP}" ]];then
    if [[ "${RANCHER_ENV}" == "true" ]]; then
      BIND9_IP=`curl rancher-metadata/latest/self/host/agent_ip`
      if [[ "$?" != "0" ]] || [[ "$BIND9_IP" == "" ]]; then
        echo "Unable to get host ip" && exit 1
      fi
    else
      echo "The variable BIND9_IP must be set" && exit 1
    fi
  fi
  echo "Creating key configuration"
  cat <<EOF > /etc/bind/tsig.key
key "${BIND9_KEYNAME}" {
  algorithm "${BIND9_KEY_ALGORITHM}";
  secret "${BIND9_KEY}";
};
EOF
  echo "Creating named configuration"
  cat <<EOF > /etc/bind/named.conf.local
include "/etc/bind/tsig.key";
zone "${BIND9_ROOTDOMAIN}" {
       type master;
       file "/etc/bind/zones/db.${BIND9_ROOTDOMAIN}";
       allow-update { key "${BIND9_KEYNAME}"; } ;
};
EOF
  echo "Creating ${BIND9_ROOTDOMAIN} configuration"
  cat <<EOF >> "/etc/bind/zones/db.${BIND9_ROOTDOMAIN}" 
@		IN SOA	ns.${BIND9_ROOTDOMAIN}. root.${BIND9_ROOTDOMAIN}. (
				20041125   ; serial
				${BIND9_TTL_REFRESH}     ; refresh (1 week)
				${BIND9_TTL_RETRY}      ; retry (1 day)
				${BIND9_TTL_EXPIRE}    ; expire (4 weeks)
				${BIND9_TTL_MINIMUM}     ; minimum (1 week)
				)
			NS	ns.${BIND9_ROOTDOMAIN}.
ns			A	${BIND9_IP}
${BIND9_STATIC_ENTRIES}
EOF
  echo "Creating named.conf.options configuration"
  if [[ -z "${BIND9_FORWARDERS}" ]];then
    forwarders=""
  else
    fowarders="forwarders {$BIND9_FORWARDERS};"
  fi

  cat <<EOF > "/etc/bind/named.conf.options"
options {
	directory "/var/cache/bind";
        allow-recursion {${BIND9_RECURSION_ACCEPT}};
        allow-query-cache {${BIND9_QUERY_CACHE_ACCEPT}};
        allow-query {any;};
        recursion yes;
	${fowarders}
	dnssec-enable yes;
	dnssec-validation yes;

	auth-nxdomain no;    # conform to RFC1035
	//listen-on-v6 { any; };
};
EOF
  chown -R bind:bind /etc/bind/zones/
  touch /var/run/named/.stamp_installed
fi

ipv4=""
if [[ ! -z "${BIND9_IPV4ONLY}" ]];then
  ipv4="-4"
fi

named $ipv4 -g -c /etc/bind/named.conf -u bind
