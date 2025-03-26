#!/bin/sh

helm upgrade -i podinfo podinfo/podinfo -f https://raw.githubusercontent.com/kedify/otel-add-on/refs/heads/main/examples/metric-pull/podinfo-values.yaml
helm upgrade -i keda kedify/keda --namespace keda --create-namespace --version v2.16.0-1
helm upgrade -i kedify-otel oci://ghcr.io/kedify/charts/otel-add-on --version=v0.0.6 -f https://raw.githubusercontent.com/kedify/otel-add-on/refs/heads/main/examples/metric-pull/scaler-with-collector-pull-values.yaml

k apply -f ./podinfo-so.yaml
k port-forward svc/podinfo 9898


hey -n 7000 -z 180s http://localhost:9898/delay/2 &> /dev/null