# seamless-static-route-cni

A static route CNI that is all-in-one tool for setting a static route in a pod based on a gateway address calculated from the host's IP address.

You call this... seamless!? Yup, because you don't need to cut up a bunch of other things in order to use it.

## Specification

The "hosts IP address" is the IPv4 address of the hosts' primary interface, the interface is determined by the default route. A gateway address is calculated as taking the host IP address, masked off, and adding 1. Then, a static route is set in the pod's network namespace, to route the pod's IP address (as a /32) via the calculated gateway address.

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
  name: seamless-conf
spec:
  config: '{
      "cniVersion": "0.3.0",
      "name": "example-seamless-static-route",
      "type": "seamless-static-route"
    }'
```

Now create a pod that references it:

```
apiVersion: v1
kind: Pod
metadata:
  name: sampleseamless
  annotations:
    k8s.v1.cni.cncf.io/networks: seamless-conf
spec:
  containers:
  - name: sampleseamless
    command: ["/bin/ash", "-c", "trap : TERM INT; sleep infinity & wait"]
    image: alpine
```

Now execute `ip route` in the pod, and you'll see a couple added routes:

```
kubectl exec -it sampleseamless -- ip route
default via 10.244.0.1 dev eth0 
10.244.0.0/24 dev eth0 scope link  src 10.244.0.72 
10.244.0.0/16 via 10.244.0.1 dev eth0 
10.244.0.72 via 192.168.122.1 dev eth0 
192.168.122.0/24 dev eth0 scope link 
```

`seamless-static-route` has added these routes:

```
10.244.0.72 via 192.168.122.1 dev eth0 
192.168.122.0/24 dev eth0 scope link 
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
