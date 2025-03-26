#!/bin/bash
set -euo pipefail
source .secret
source .env

function setup_bootstrap_cluster() {
  # setup a bootstrap kind cluster w/ CluterAPI controllers
  kind create cluster --image kindest/node:"${KUBERNETES_VERSION}"
  clusterctl init --infrastructure gcp --addon helm
  k rollout status deploy/capg-controller-manager -ncapg-system
  k rollout status deploy/capi-kubeadm-bootstrap-controller-manager -ncapi-kubeadm-bootstrap-system
  k rollout status deploy/capi-kubeadm-control-plane-controller-manager -ncapi-kubeadm-control-plane-system
  k rollout status deploy/capi-controller-manager -ncapi-system
  k rollout status deploy/caaph-controller-manager -ncaaph-system
  capg-with-gpus
}

function capg-with-gpus() {
  k8s_context=${1:-"kind-kind"}
  arch=${2:-"arm64"}
  echo -e "context: ${k8s_context}\narch: ${arch}"
  [ ! -d ./cluster-api-provider-gcp ] && {
    git clone git@github.com:kubernetes-sigs/cluster-api-provider-gcp.git
    pushd cluster-api-provider-gcp && { git fetch origin pull/1341/head:pr1341 && git checkout pr1341 ; } ; popd
  }

  pushd cluster-api-provider-gcp
  # git fetch origin pull/1341/head:pr1341 && git checkout pr1341 && \
  k --context=${k8s_context} apply -f config/crd/bases/ && \
  # REGISTRY=docker.io/jkremser TAG=gpu ARCH=arm64 make docker-build && \
  # docker push docker.io/jkremser/cluster-api-gcp-controller-arm64:gpu && \
  # REGISTRY=docker.io/jkremser TAG=gpu ARCH=amd64 make docker-build && \
  # docker push docker.io/jkremser/cluster-api-gcp-controller-amd64:gpu && \
  k --context=${k8s_context} set image deploy -ncapg-system capg-controller-manager manager=docker.io/jkremser/cluster-api-gcp-controller-${arch}:gpu && \
  k --context=${k8s_context} rollout status deploy/capg-controller-manager -ncapg-system
  popd
}

function create_cluster() {
  # create cluster ${CLUSTER_NAME}
  cat gcp.yaml | envsubst | k apply -f - && cat ccm.yaml | envsubst | k apply -f -
  sleep 1 && {
    date
    kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=InfrastructureReady && date
    kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=ControlPlaneReady && date
    kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=Ready && date
    kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=ControlPlaneInitialized && date
  }
  k get machinedeployments
  clusterctl get kubeconfig ${CLUSTER_NAME} > ${CLUSTER_NAME}.kubeconfig
  k kc delete ${CLUSTER_NAME} &> /dev/null || true ; k kc add -c --context-name ${CLUSTER_NAME} -f <(clusterctl get kubeconfig ${CLUSTER_NAME}) &> /dev/null
}

function make_self_managed() {
  # make self-managed cluster
  clusterctl --kubeconfig-context=${CLUSTER_NAME} init --infrastructure gcp --addon helm
  capg-with-gpus ${CLUSTER_NAME} amd64
  clusterctl --kubeconfig-context=kind-kind get kubeconfig ${CLUSTER_NAME} > kc.tmp ; clusterctl --kubeconfig-context=kind-kind move --to-kubeconfig=./kc.tmp ; rm ./kc.tmp
}

function main() {
  k config use-context kind-kind
  create_cluster
  make_self_managed
}

main $@
