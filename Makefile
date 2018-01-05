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
ZIPKIN_POD_NAME=$(shell kubectl -n istio-system get pod -l app=zipkin -o jsonpath='{.items[0].metadata.name}')
SERVICEGRAPH_POD_NAME=$(shell kubectl -n istio-system get pod -l app=servicegraph -o jsonpath='{.items[0].metadata.name}')
GRAFANA_POD_NAME=$(shell kubectl -n istio-system get pod -l app=grafana -o jsonpath='{.items[0].metadata.name}')

create-cluster:
	gcloud beta container --project "$(PROJECT_ID)" clusters create "my-istio-cluster" --zone "$(ZONE)" --username="admin" --machine-type "n1-standard-1" --image-type "COS" --disk-size "100" --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --enable-kubernetes-alpha --num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring --enable-legacy-authorization
deploy-istio:
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/istio.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/istio-initializer.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/addons/zipkin.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/addons/prometheus.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/addons/servicegraph.yaml'
	kubectl apply -f 'https://raw.githubusercontent.com/istio/istio/4bc1381/install/kubernetes/addons/grafana.yaml'
deploy-stuff:
	kubectl apply -f ./configs/kube/services.yaml
	-sed -e 's~<PROJECT_ID>~$(PROJECT_ID)~g' ./configs/kube/deployments.yaml | kubectl apply -f -
get-stuff:
	kubectl get pods && kubectl get svc && kubectl get ingress
egress:
	istioctl create -f ./configs/istio/egress.yaml
prod:
	istioctl create -f ./configs/istio/routing-1.yaml
retry:
	istioctl replace -f ./configs/istio/routing-2.yaml
ingress:
	kubectl delete svc frontend
	kubectl apply -f ./configs/kube/services-2.yaml
canary:
	istioctl create -f ./configs/istio/routing-3.yaml


start-monitoring-services:
	$(shell kubectl -n istio-system port-forward $(ZIPKIN_POD_NAME) 9411:9411 & kubectl -n istio-system port-forward $(SERVICEGRAPH_POD_NAME) 8088:8088 & kubectl -n istio-system port-forward $(GRAFANA_POD_NAME) 3000:3000)
build:
	docker build -t gcr.io/$(PROJECT_ID)/istiotest:1.0 ./code/
push:
	gcloud docker -- push gcr.io/$(PROJECT_ID)/istiotest:1.0
run-local:
	docker run -ti -p 3000:3000 gcr.io/$(PROJECT_ID)/istiotest:1.0
restart-all:
	kubectl delete pods --all
delete-route-rules:
	-istioctl delete routerules frontend-route
	-istioctl delete routerules middleware-dev-route
	-istioctl delete routerules middleware-route
	-istioctl delete routerules backend-route
delete-cluster:
	kubectl delete service frontend
	kubectl delete ingress istio-ingress
	gcloud container clusters delete "my-istio-cluster" --zone "$(ZONE)"