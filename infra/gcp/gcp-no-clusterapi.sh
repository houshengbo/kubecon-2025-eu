#!/bin/sh
set -e

# GCP_ZONE GCP_PROJECT
source .env

export CLUSTER="gpu"
#export GPU="nvidia-tesla-t4"
# export MACHINE="n1-highmem-8"
# export DISK="pd-standard"

export GPU="nvidia-l4"
export MACHINE="g2-standard-8"
export DISK="pd-balanced"

gcloud -q beta container clusters delete ${CLUSTER} --zone ${GCP_ZONE} --project ${${GCP_PROJECT}} --async

gcloud beta container clusters create ${CLUSTER} \
  --project ${${GCP_PROJECT}} \
  --zone ${GCP_ZONE} \
  --release-channel "regular" \
  --machine-type "${MACHINE}" \
  --accelerator "type=${GPU},count=1,gpu-driver-version=default" \
  --image-type "UBUNTU_CONTAINERD" \
  --disk-type "${DISK}" \
  --disk-size "300" \
  --metadata disable-legacy-endpoints=true \
  --service-account "${${GCP_PROJECT}}@${${GCP_PROJECT}}.iam.gserviceaccount.com" \
  --spot \
  --no-enable-intra-node-visibility \
  --max-pods-per-node "110" \
  --num-nodes "1" \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM \
  --enable-ip-alias \
  --security-posture=disabled \
  --workload-vulnerability-scanning=disabled \
  --no-enable-managed-prometheus \
  --no-enable-intra-node-visibility \
  --default-max-pods-per-node "110" \
  --no-enable-master-authorized-networks \
  --tags=nvidia-ingress-all

sleep 5

gcloud container clusters update ${CLUSTER} \
  --project ${${GCP_PROJECT}} \
  --zone ${GCP_ZONE} \
  --enable-autoprovisioning \
  --min-cpu=1 --max-cpu=8 --min-memory=1 --max-memory=52 \
  --autoprovisioning-scopes=https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring,https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/compute

sleep 5

# login
gcloud container clusters get-credentials ${CLUSTER} --zone ${GCP_ZONE} --project ${${GCP_PROJECT}}

# install kserve and model
kubectl --context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml
kubectl --context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} rollout status -ncert-manager deploy/cert-manager-webhook
helm --kube-context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} upgrade -i kserve-crd oci://ghcr.io/kserve/charts/kserve-crd --version v0.15.0-rc1
helm --kube-context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} upgrade -i kserve oci://ghcr.io/kserve/charts/kserve --version v0.15.0-rc1 --set kserve.controller.deploymentMode=RawDeployment
kubectl --context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} rollout status deploy/kserve-controller-manager

kubectl --context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} apply -f ./all-kserve-crs.yaml

# expose the svc
kubectl expose deploy/huggingface-llama3-predictor --type=LoadBalancer --name=llama3 --port=8080 --target-port=8080
while [ "x$(kubectl --context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} get svc llama3 -ojsonpath='{.status.loadBalancer.ingress[].ip}')" = "x" ] ; do sleep 1;printf .; done
IP=$(kubectl --context gke_${${GCP_PROJECT}}_${GCP_ZONE}_${CLUSTER} get svc llama3 -ojsonpath='{.status.loadBalancer.ingress[].ip}')


PROMPT="What tool is the best for templating YAMLs in k8s ecosystem?"
curl -XPOST -H 'Content-Type: application/json' -H "Host: huggingface-llama3-predictor" http://${IP}:8080/openai/v1/chat/completions -d '{ "model": "llama3", "messages": [ { "role": "user", "content": "${PROMPT}"} ], "stream": false, "max_tokens": 300 }' | jq

#hey -c 100 curl -XPOST -H 'Content-Type: application/json' -H "Host: huggingface-llama3-predictor" http://${IP}:8080/openai/v1/chat/completions -d '{ "model": "llama3", "messages": [ { "role": "user", "content": "${PROMPT}"} ], "stream": false, "max_tokens": 300 }' | jq
