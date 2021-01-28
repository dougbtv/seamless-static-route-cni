# seamless-static-route-cni

A static route CNI that is all-in-one tool for setting a static route based on a rule.

## Specification

The rule on which the static route is created is as follows.

**(TODO)**

## Installation

Copy `seamless-static-route.sh` to `/opt/cni/bin/seamless-static-route` (or whatever your CNI binary directory is) and `chmod +x` it, on every node.

This assumes the use of the `ipcalc` command, which is available on RHCOS nodes in OpenShift.

**TODO**: This will be a daemonset install.

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

Line 1: It routes the pod's IP address (as a /32) to a calculated gateway address (**TODO**: This goes in the rules/spec above)

Line 2: It has added the network of the host's primary IP (determined by first address on the network interface that has the default gateway to it)

## Development notes

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
