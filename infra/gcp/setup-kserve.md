```
helm --kube-context ${CLUSTER_NAME} upgrade -i kserve-crd oci://ghcr.io/kserve/charts/kserve-crd --version v0.15.0-rc1
helm --kube-context ${CLUSTER_NAME} upgrade -i kserve oci://ghcr.io/kserve/charts/kserve --version v0.15.0-rc1 --set kserve.controller.deploymentMode=RawDeployment
kubectl --context ${CLUSTER_NAME} rollout status deploy/kserve-controller-manager
```
