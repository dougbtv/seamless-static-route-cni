#!/usr/bin/env bash

# Outputs errors to stderr
errorlog () {
  >&2 echo $1
}

# Logs for debugging.
debuglog () {
  # Set DEBUG to anything to enable debug output.
  if [ -n "$DEBUG" ]; then
    # Set logfile if you want to log to a flat file.
    if [ -n "$LOGFILE"]; then
      echo $1 >> $LOGFILE
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
  hostipaddr=$(ip -f inet addr show $iface | awk '/inet/ {print $2}')
  debuglog "IP Address: $hostipaddr"

  # Calculate the gateway address.
  # Use ipcalc to get the masked address.
  gwnetworkaddress=$(ipcalc --network $hostipaddr | sed -E 's|^NETWORK=(.+)$|\1|')
  # Get the slash value from the original IP
  
  # Now calculate the gateway itself. We'll add one to the last byte of the masked address.
  # Save the first three octets.
  gwmaskedfirstthreebytes=$(echo "$gwnetworkaddress" | sed -E 's|^(.+\.)([[:digit:]]+)$|\1|')
  # Save the last octet.
  gwmaskedlastbyte=$(echo "$gwnetworkaddress" | sed -E 's|^(.+\.)([[:digit:]]+)$|\2|')
  # Add one to the last octet.
  lastoctetplusone="$(($gwmaskedlastbyte + 1))"
  # Combine the first three bytes with the last octet + 1.
  gwcalculated=$(printf "$gwmaskedfirstthreebytes$lastoctetplusone")

  # Debug output.
  debuglog "GW Network Address: $gwnetworkaddress"
  debuglog "GW gwmaskedfirstthreebytes: $gwmaskedfirstthreebytes"
  debuglog "GW gwmaskedlastbyte: $gwmaskedlastbyte"
  debuglog "GW lastoctetplusone: $lastoctetplusone"
  debuglog "GW gwcalculated: $gwcalculated"
  
  # -------------------------------- Process the container IP address.

  # Get the ip address inside the container
  ctripaddr=$(nsenter --net=$CNI_NETNS ip -f inet addr show $containerifname | awk '/inet/ {print $2}')
  debuglog "Container IP Address: $ctripaddr"
  # Now we convert that to a slash 32.
  ctripaddrslash32=$(echo "$ctripaddr" | sed -E 's|^(.+)/.+$|\1/32|')
  debuglog "GW ctripaddrslash32: $ctripaddrslash32"

  # -------------------------------- Set the static route.

  debuglog "nsenter --net=$CNI_NETNS ip route add $gwcalculated/32 dev $containerifname"
  debuglog "nsenter --net=$CNI_NETNS ip route add $ctripaddrslash32 via $gwcalculated"

  # First we add a route for the calculated gateway on the primary interface.
  nsenter --net=$CNI_NETNS ip route add $gwcalculated/32 dev $containerifname
  exit_on_error $? !!

  # Then we add the route itself to route the pods ip via the calculated gateway.
  nsenter --net=$CNI_NETNS ip route add $ctripaddrslash32 via $gwcalculated
  exit_on_error $? !!

  cniresult
  exit 0

else
  # We don't need to operate on DEL (or other CNI commands).
  cniresult
  exit 0
fi