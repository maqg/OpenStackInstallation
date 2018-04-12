# OpenStackInstallation
Installation for CentOS 7 of OpenStack Pike and Queens

if Got Error "Peer reports incompatible or unsupported protocol version."
Just yum update -y nss curl libcurl

## How to install?
- Modify configure.sh.
- With controller.sh to install base controller env.
- With keystone.sh to install identfy service in controller node.
- With glance.sh to install image service int controller node.
- With nova.sh to install nova install controller node.
- With compute.sh to install base env in COMPUTE node.
- With nova_compute.sh to install compute env in COMPUTE node.
- With neutron.sh to install networking service.
- With neutron_compute.sh to install networking service in compute node.
- With horizon.sh to install dashboard service in controller node.
- With cinder.sh to install black storage service in controller node.
