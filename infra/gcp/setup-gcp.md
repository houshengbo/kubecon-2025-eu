```
source .secret
source .env
```

<!-- https://deployment.properties/posts/k8s-ops/cluster-api/ -->

# Cloud NAT (do only once)
# Ensure if network list contains default network

```
gcloud compute networks list --project="${GCP_PROJECT}"
gcloud compute networks describe "${GCP_NETWORK_NAME}" --project="${GCP_PROJECT}"
```

# Ensure if firewall rules are enabled

```
gcloud compute firewall-rules list --project "$GCP_PROJECT"
```

# Create routers

```
gcloud compute routers create "${CLUSTER_NAME}-myrouter" --project="${GCP_PROJECT}" --region="${GCP_REGION}" --network="default"
```

# Create NAT

```
gcloud compute routers nats create "${CLUSTER_NAME}-mynat" --project="${GCP_PROJECT}" --router-region="${GCP_REGION}" --router="${CLUSTER_NAME}-myrouter" --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips
```

# Clean-up

```
gcloud compute routers nats delete "${CLUSTER_NAME}-mynat" --project="${GCP_PROJECT}" --router-region="${GCP_REGION}" --router="${CLUSTER_NAME}-myrouter" --quiet || true
```

# Delete the router

```
gcloud compute routers delete "${CLUSTER_NAME}-myrouter" --project="${GCP_PROJECT}" \
--region="${GCP_REGION}" --quiet || true
```

# setup a bootstrap kind cluster w/ CluterAPI controllers
```
kind create cluster --image kindest/node:"${KUBERNETES_VERSION}"
clusterctl init --infrastructure gcp --addon helm
k rollout status deploy/capg-controller-manager -ncapg-system
k rollout status deploy/capi-kubeadm-bootstrap-controller-manager -ncapi-kubeadm-bootstrap-system
k rollout status deploy/capi-kubeadm-control-plane-controller-manager -ncapi-kubeadm-control-plane-system
k rollout status deploy/capi-controller-manager -ncapi-system
k rollout status deploy/caaph-controller-manager -ncaaph-system
```

# Replace the capg controller image with - version from this PR https://github.com/kubernetes-sigs/cluster-api-provider-gcp/pull/1341
hot-fix until the pr is merged

```
function capg-with-gpus() {
  k8s_context=${1:-"kind-kind"}
  arch=${2:-"arm64"}
  echo -e "context: ${k8s_context}\narch: ${arch}"
  if [ ! -d ./cluster-api-provider-gcp ]; then
    git clone git@github.com:kubernetes-sigs/cluster-api-provider-gcp.git
    pushd cluster-api-provider-gcp && { git fetch origin pull/1341/head:pr1341 && git checkout pr1341 ; } ; popd
  fi
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
capg-with-gpus
```

# build capg images (optional)
```
# requires also ansible to be installed
# GOOGLE_APPLICATION_CREDENTIALS must be set

export IMAGE_NAME=$(gcloud compute images list --project ${GCP_PROJECT} --no-standard-images --format json | jq -r '.[0].name')
export IMAGE_ID=projects/"${GCP_PROJECT_ID}"/global/images/"${IMAGE_NAME}"
git clone https://github.com/kubernetes-sigs/image-builder.git image-builder; pushd image-builder/images/capi; make deps-common deps-gce build-gce-ubuntu-2404; popd
```

<!-- k delete mutatingwebhookconfigurations capg-mutating-webhook-configuration
k delete validatingwebhookconfigurations capg-validating-webhook-configuration -->

# create the cluster resources

either machine pools (managed gke)
```
source .env && k apply -f gke.yaml
sleep 1 && {
  date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=InfrastructureReady && date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=ControlPlaneReady && date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=Ready && date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=ControlPlaneInitialized && date
}
k get machinepools
```

or gcp - machinedeployments

```
source .env && cat gcp.yaml | envsubst | k apply -f - && cat ccm.yaml | envsubst | k apply -f -
sleep 1 && {
  date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=InfrastructureReady && date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=ControlPlaneReady && date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=Ready && date
  kubectl wait --timeout=600s clusters/${CLUSTER_NAME} --for condition=ControlPlaneInitialized && date
}
k get machinedeployments
```


# verify scaling of gpu node

```
k scale machinedeployments ${CLUSTER_NAME}-gpu-nodes --replicas=2
open https://console.cloud.google.com/compute/instances
```

# troubleshoot
```
k get gcpmachine
gcloud compute ssh --tunnel-through-iap --project=${GCP_PROJECT} --zone=${GCP_ZONE} ${CLUSTER_NAME}-control-plane-zk52x
```

# get kubeconfig
```
k kc delete ${CLUSTER_NAME} ; k kc add -c --context-name ${CLUSTER_NAME} -f <(clusterctl get kubeconfig ${CLUSTER_NAME})
```

# make self-managed cluster
```
clusterctl --kubeconfig-context=${CLUSTER_NAME} init --infrastructure gcp --addon helm
capg-with-gpus ${CLUSTER_NAME} amd64
#cd cluster-api-provider-gcp ; k apply -f config/crd/bases/ ; cd -
#k --context ${CLUSTER_NAME} set image deploy -ncapg-system capg-controller-manager manager=docker.io/jkremser/cluster-api-gcp-controller-amd64:gpu
clusterctl --kubeconfig-context=kind-kind get kubeconfig ${CLUSTER_NAME} > kc.tmp ; clusterctl --kubeconfig-context=kind-kind move --to-kubeconfig=./kc.tmp ; rm ./kc.tmp
```


# ingress controller
```
kubectl --context=${CLUSTER_NAME} apply -f https://k8s.io/examples/controllers/nginx-deployment.yaml
kubectl --context=${CLUSTER_NAME} expose deploy/nginx-deployment --type=LoadBalancer --name=nginx-service
```

# /etc/hosts instead of DNS
```
IP=$(k --context=${CLUSTER_NAME} get svc nginx-service -ojsonpath='{.status.loadBalancer.ingress[].ip}')
sudo sed -i '/aicluster/d' /etc/hosts
echo "${IP}  aicluster" | sudo tee -a /etc/hosts
```

# cleanup
```
# if cluster was moved
k delete --context=kind-kind cluster ${CLUSTER_NAME}
# if not
k delete --context=${CLUSTER_NAME} cluster ${CLUSTER_NAME}
kind delete cluster
```

# todo:
- [x] remove verbosity of ccm
- [x] nvidia device plugin (but depends on the drivers)
- [x] fix the daemonset of ccm - done
- [x] metrics server
- [x] csi for volumes to work
- [x] ~build image w/ drivers~ not needed, gpu operator handles this - https://github.com/kubernetes-sigs/image-builder/blob/main/images/capi/ansible/roles/gpu/README.md , https://github.com/kubernetes-sigs/image-builder/pull/1402/files , https://github.com/NVIDIA/k8s-device-plugin#prerequisites
- [x] set all pull policies to ifnotpresent
- [x] The node was low on resource: ephemeral-storage. Threshold quantity: 2952383810, available: 2727252Ki (increased the disk on the GCPMachineTemplate lvl)
- [x] demo related images:
    - kserve/huggingfaceserver:v0.15.0-rc1-gpu
    - docker.io/vllm/vllm-openai:v0.6.4
    - all csi driver images
- [] record demos
- [] webui: https://github.com/open-webui/helm-charts/tree/main/charts/open-webui (explore if they expose traces or metrics that could be used by otel scaler)
