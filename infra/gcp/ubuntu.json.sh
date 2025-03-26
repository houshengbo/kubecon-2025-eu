#!/bin/bash
# seed:
# k get po,daemonset -A -oyaml | grep 'image:' | sed 's/ //g' | sed 's/@sha.*//' | sed 's/image://' | sort | uniq

IMGS=$(cat <<EOF | tr '\n' ',' | rev | cut -c2- | rev
kserve/huggingfaceserver:v0.15.0-rc1-gpu
nginx:1.14.2
nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.2
nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.7.0
nvcr.io/nvidia/cloud-native/k8s-mig-manager:v0.10.0-ubuntu20.04
nvcr.io/nvidia/driver:550.144.03-ubuntu24.04
nvcr.io/nvidia/k8s-device-plugin:v0.17.0
nvcr.io/nvidia/k8s/container-toolkit:v1.17.4-ubuntu20.04
nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.1-ubuntu22.04
quay.io/brancz/kube-rbac-proxy:v0.18.0
quay.io/cilium/cilium-envoy:v1.31.5-1741765102-efed3defcc70ab5b263a0fc44c93d316b846a211
quay.io/cilium/cilium:v1.17.2
registry.k8s.io/cloud-provider-gcp/gcp-compute-persistent-disk-csi-driver:v1.13.2
registry.k8s.io/kube-proxy:v1.31.4
registry.k8s.io/nfd/node-feature-discovery:v0.16.6
registry.k8s.io/sig-storage/csi-attacher:v4.4.3
registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.9.3
registry.k8s.io/sig-storage/csi-provisioner:v5.1.0
registry.k8s.io/sig-storage/csi-resizer:v1.11.1
registry.k8s.io/sig-storage/csi-snapshotter:v6.3.3
EOF
)

for f in ubuntu.json ubuntu-drivers.json; do
  # uncomment if sponge isn't installed (formatting is lost though)
  #cat <<< $(jq '.additional_registry_images_list="'$IMGS'"' "${f}") > "${f}"
  jq '.additional_registry_images_list="'$IMGS'"' "${f}" | sponge "${f}"
done
