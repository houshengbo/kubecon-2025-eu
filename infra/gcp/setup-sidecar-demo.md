```
# https://raw.githubusercontent.com/houshengbo/kubecon-2025-eu/refs/heads/main/config/llama-vllm/001-sidecarotel.yaml
# https://github.com/houshengbo/kubecon-2025-eu/blob/main/config/llama-vllm/002-deployment.yaml
# https://raw.githubusercontent.com/houshengbo/kubecon-2025-eu/refs/heads/main/config/llama-vllm/003-scaledobject.yaml
```


```
k port-forward deploy/autoscaling-llama-3-1-70b-instruct-vllm-predictor -n s-dsplatform 1234:1234
k port-forward deploy/autoscaling-llama-3-1-70b-instruct-vllm-predictor -n s-dsplatform 8080:8080
http://127.0.0.1:1234/metrics
http://127.0.0.1:8080/metrics
```

