#	Copyright 2018, Google, Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
PROJECT_ID=$(shell gcloud config list project --format=flattened | awk 'FNR == 1 {print $$2}')
ZONE=us-west1-b
CLUSTER_NAME=my-istio-cluster
ZIPKIN_POD_NAME=$(shell kubectl -n istio-system get pod -l app=zipkin -o jsonpath='{.items[0].metadata.name}')
SERVICEGRAPH_POD_NAME=$(shell kubectl -n istio-system get pod -l app=servicegraph -o jsonpath='{.items[0].metadata.name}')
GRAFANA_POD_NAME=$(shell kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}')
GCLOUD_USER=$(shell gcloud config get-value core/account)

create-cluster:
	gcloud container --project "$(PROJECT_ID)" clusters create "$(CLUSTER_NAME)" --zone "$(ZONE)" --machine-type "n1-standard-1" --image-type "COS" --disk-size "100" --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --cluster-version=1.9
	kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(GCLOUD_USER)
deploy-istio:
	kubectl apply -f istio-0.6/install/kubernetes/istio.yaml
	./istio-0.6/install/kubernetes/webhook-create-signed-cert.sh --service istio-sidecar-injector --namespace istio-system --secret sidecar-injector-certs
	kubectl apply -f istio-0.6/install/kubernetes/istio-sidecar-injector-configmap-release.yaml
	cat istio-0.6/install/kubernetes/istio-sidecar-injector.yaml | ./istio-0.6/install/kubernetes/webhook-patch-ca-bundle.sh > istio-0.6/install/kubernetes/istio-sidecar-injector-with-ca-bundle.yaml
	kubectl apply -f istio-0.6/install/kubernetes/istio-sidecar-injector-with-ca-bundle.yaml
	kubectl apply -f istio-0.6/install/kubernetes/addons/prometheus.yaml
	kubectl apply -f istio-0.6/install/kubernetes/addons/grafana.yaml
	kubectl apply -f istio-0.6/install/kubernetes/addons/zipkin.yaml
	kubectl apply -f istio-0.6/install/kubernetes/addons/servicegraph.yaml
	kubectl label namespace default istio-injection=enabled
deploy-stuff:
	kubectl apply -f ./configs/kube/services.yaml
	-sed -e 's~<PROJECT_ID>~$(PROJECT_ID)~g' ./configs/kube/deployments.yaml | kubectl apply -f -
get-stuff:
	kubectl get pods && kubectl get svc && kubectl get ingress
egress:
	./istio-0.6/bin/istioctl create -f ./configs/istio/egress.yaml
prod:
	./istio-0.6/bin/istioctl create -f ./configs/istio/routing-1.yaml
retry:
	./istio-0.6/bin/istioctl replace -f ./configs/istio/routing-2.yaml
ingress:
	kubectl delete svc frontend
	kubectl apply -f ./configs/kube/services-2.yaml
canary:
	./istio-0.6/bin/istioctl create -f ./configs/istio/routing-3.yaml


start-monitoring-services:
	$(shell kubectl -n istio-system port-forward $(ZIPKIN_POD_NAME) 9411:9411 & kubectl -n istio-system port-forward $(SERVICEGRAPH_POD_NAME) 8088:8088 & kubectl -n istio-system port-forward $(GRAFANA_POD_NAME) 3000:3000)
build:
	docker build -t gcr.io/$(PROJECT_ID)/istiotest:1.0 ./code/
push:
	gcloud auth configure-docker
	docker push gcr.io/$(PROJECT_ID)/istiotest:1.0
run-local:
	docker run -ti -p 3000:3000 gcr.io/$(PROJECT_ID)/istiotest:1.0
restart-all:
	kubectl delete pods --all
delete-route-rules:
	-./istio-0.6/bin/istioctl delete routerules frontend-route -n default
	-./istio-0.6/bin/istioctl delete routerules middleware-dev-route -n default
	-./istio-0.6/bin/istioctl delete routerules middleware-route -n default
	-./istio-0.6/bin/istioctl delete routerules backend-route -n default
delete-cluster:
	kubectl delete service frontend
	kubectl delete ingress istio-ingress
	gcloud container clusters delete "$(CLUSTER_NAME)" --zone "$(ZONE)"
