# seamless-static-route-cni

A static route CNI that is all-in-one tool for setting a static route in a pod based on a gateway address calculated from the host's IP address.

You call this... seamless!? Yup, because you don't need to cut up a bunch of other things in order to use it.

## Specification

The "hosts IP address" is the IPv4 address of the hosts' primary interface, the interface is determined by the default route. A gateway address is calculated as taking the container's IP address and running `ipcalc --minaddr` to calculate a gateway address. Then a route is added to the container to route the host IP address (as a /32) via the calculated gateway address on the eth0 device.

## Requirements

This assumes the use of the `ipcalc` command, which is available on RHCOS nodes in OpenShift.

## Installation

Clone this repository and start the daemonset with the included yaml:

```
git clone https://github.com/dougbtv/seamless-static-route-cni.git
kubectl create -f seamless-static-route-cni/daemonset.yml
```

## Usage

Create a network attachment definition:

```
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: static-route-default-conf
  namespace: kube-system
spec:
  config: '{
  "name": "static-route-default-conf",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "name":"ovn-kubernetes",
      "type":"ovn-k8s-cni-overlay",
      "ipam":{},
      "dns":{},
      "logFile":"/var/log/ovn-kubernetes/ovn-k8s-cni-overlay.log",
      "logLevel":"4",
      "logfile-maxsize":100,
      "logfile-maxbackups":5,
      "logfile-maxage":5
    },
    {
      "cniVersion": "0.3.0",
      "name": "example-seamless-static-route",
      "type": "seamless-static-route"
    }
  ]
}'
```

Now create a pod that references it, note that this uses the **v1.multus-cni.io/default-network** -- which is for the overridden Multus.

```
apiVersion: v1
kind: Pod
metadata:
  name: sampleseamless
  annotations:
    v1.multus-cni.io/default-network: static-route-default-conf
spec:
  containers:
  - name: sampleseamless
    command: ["/bin/ash", "-c", "trap : TERM INT; sleep infinity & wait"]
    image: alpine
```

Now execute `ip route` in the pod, and you'll see an additional route, `seamless-static-route` has added this route:

```
10.0.32.2 via 10.131.0.1 dev eth0 
```

## Debugging

**TODO**: Add JSON parsing and make this parameterizable.

`DEBUG=true` and `LOGFILE=/var/log/seamless.log` in the script.

## Development notes

Because I kept copy/pasta'ing these.

```
export CNI_PATH=/opt/cni/bin/
export NETCONFPATH=/home/centos/cniconf/
```

```
cat ~/cniconf/10-seamless.conf
{
    "cniVersion": "0.2.0",
    "name": "seamless-static-route-example",
    "type": "seamless-static-route"
}
```

