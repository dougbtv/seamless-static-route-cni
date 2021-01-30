#!/usr/bin/env bash

# DEBUG=true
# LOGFILE=/tmp/seamless.log

# Outputs errors to stderr
errorlog () {
  >&2 echo $1
}

# Logs for debugging.
debuglog () {
  # Set DEBUG to anything to enable debug output.
  if [ -n "$DEBUG" ]; then
    # touch /tmp/seamless_a
    # Set logfile if you want to log to a flat file.
    if [ -n "$LOGFILE" ]; then
      # touch /tmp/seamless_b
      echo $1 >> $LOGFILE.$CNI_CONTAINERID
    else
      # Otherwise, log to stderr.
      >&2 echo $1
    fi
  fi
}

# Outputs an essentially dummy CNI result that's borderline acceptable by the spec.
# https://github.com/containernetworking/cni/blob/master/SPEC.md#result
cniresult () {
    cat << EOF
{
  "cniVersion": "1.0.0",
  "interfaces": [
      {
          "name": "dummy-seamless-static-route"
      }
  ],
  "ips": []
}
EOF
}

# Certain failures we want to exit on.
exit_on_error() {
    exit_code=$1
    last_command=${@:2}
    if [ $exit_code -ne 0 ]; then
        >&2 echo "seamless-static-route: \"${last_command}\" command failed with exit code ${exit_code}."
        cniresult
        exit $exit_code
    fi
}

# Overarching basic parameters.
containerifname=eth0

# --------------------------------------- REFERENCE: Common environment variables.
debuglog "CNI method: $CNI_COMMAND"
debuglog "CNI container id: $CNI_CONTAINERID"
debuglog "CNI netns: $CNI_NETNS"

# --------------------------------------- REFERENCE: Read config.
# debuglog "-------------- Begin config"
# while read line
# do
#   debuglog "$line"
# done < /dev/stdin
# debuglog "-------------- End config"

# We only operate on ADD command.
if [[ "$CNI_COMMAND" == "ADD" ]]; then

  # -------------------------------- Get the IP default host network interface.

  iface=""
  counter=0
  while [ $counter -lt 12 ]; do
    # from: https://github.com/openshift/machine-config-operator/blob/master/templates/common/_base/files/configure-ovs-network.yaml#L34
    # check ipv4
    iface=$(ip route show default | awk '{ if ($4 == "dev") { print $5; exit } }')
    if [[ -n "$iface" ]]; then
      debuglog "IPv4 Default gateway interface found: ${iface}"
      break
    fi
    # check ipv6
    iface=$(ip -6 route show default | awk '{ if ($4 == "dev") { print $5; exit } }')
    if [[ -n "$iface" ]]; then
      errorlog "ERROR seamless-static-route cni: IPv6 not supported"
      cniresult
      exit 1
    fi
    counter=$((counter+1))
    sleep 5
  done

  # Exit if the interface is never found.
  if [ -z "$iface" ]; then
    errorlog "ERROR seamless-static-route cni: interface not found in $counter attempts"
    cniresult
    exit 1
  fi

  # -------------------------------- Process the host IP address.

  # Get the HOST ip address / mask.
  hostipaddr=$(ip -f inet addr show $iface | awk '/inet/ {print $2}' | awk -F "/" '{print $1}')
  debuglog "HOSTIP: $hostipaddr"

  # Try to loop when ctr address is empty...
  counter=0
  while [ $counter -lt 10 ]; do
    ctripaddr=$(nsenter --net=$CNI_NETNS ip -f inet addr show $containerifname | awk '/inet/ {print $2}')
    debuglog "CTRIPADDR: >>$ctripaddr<<"
    # ctrinspect=$(nsenter --net=$CNI_NETNS ip a)
    # debuglog "INSPECT: $ctrinspect"
    if [[ -n "$ctripaddr" ]]; then
      debuglog "ctripaddr found: ${ctripaddr}"
      break
    fi
    counter=$((counter+1))
    sleep 1
  done

  if [ -z "$ctripaddr" ]; then
    errorlog "ERROR seamless-static-route cni: container ip addr not found in $counter attempts"
  fi


  ovngwip=$(ipcalc --minaddr $ctripaddr | awk -F "=" '{print $2}')
  debuglog "OVNGWIP: $ovngwip"
  
  # -------------------------------- Set the static route.
  debuglog "nsenter --net=$CNI_NETNS ip route add $hostipaddr/32 via $ovngwip dev $containerifname"
  output = $(nsenter --net=$CNI_NETNS ip route add $hostipaddr/32 via $ovngwip dev $containerifname)
  debuglog "nsenter route add: $output - exitcode $?"
  # exit_on_error $? !!

  cniresult
  exit 0

else
  # We don't need to operate on DEL (or other CNI commands).
  cniresult
  exit 0
fi