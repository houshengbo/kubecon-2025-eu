#!/bin/bash
# https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver/blob/master/docs/kubernetes/user-guides/driver-install.md

set -eui pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cp "${DIR}/../service-account.json" "${DIR}/cloud-sa.json"

export GCE_PD_SA_DIR="${DIR}"

pushd ${DIR}
[ ! -d ./gcp-compute-persistent-disk-csi-driver ] &&  {
  git clone git@github.com:kubernetes-sigs/gcp-compute-persistent-disk-csi-driver.git
  git checkout v1.15.4
}
pushd ./gcp-compute-persistent-disk-csi-driver/deploy/kubernetes/
cp ${DIR}/deploy-driver.sh .
k config use-context "${CLUSTER_NAME}"
VERBOSITY=1 KUBECTL="kubectl --context ${CLUSTER_NAME}" ./deploy-driver.sh --skip-sa-check
cp csi-manifests.yaml ${DIR}
popd ; popd
kubectl --context ${CLUSTER_NAME} apply -f csi-manifests.yaml


cat <<EOF | kubectl --context ${CLUSTER_NAME} apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-gce-pd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard
volumeBindingMode: WaitForFirstConsumer
EOF
