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

remote-build-full:
	gcloud container builds submit --tag gcr.io/$(PROJECT_ID)/trace:full ./code/
remote-build-simple:
	gcloud container builds submit --tag gcr.io/$(PROJECT_ID)/trace:simple ./simple-code/
build-full:
	docker build -t gcr.io/$(PROJECT_ID)/trace:full ./code/
build-simple:
	docker build -t gcr.io/$(PROJECT_ID)/trace:simple ./simple-code/
push:
	gcloud auth configure-docker
	-docker push gcr.io/$(PROJECT_ID)/trace:simple
	-docker push gcr.io/$(PROJECT_ID)/trace:full
run-local:
	docker run -ti -p 3000:8080 gcr.io/$(PROJECT_ID)/trace:go
restart-all:
	-kubectl delete svc frontend backend middleware
	-kubectl delete deployment frontend backend middleware
get-logs:
	kubectl logs --tail=9 $(shell kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') frontend
	kubectl logs --tail=9 $(shell kubectl get pod -l app=middleware -o jsonpath='{.items[0].metadata.name}') middleware
	kubectl logs --tail=9 $(shell kubectl get pod -l app=backend -o jsonpath='{.items[0].metadata.name}') backend
deploy-opencensus-code:
	kubectl apply -f ./config/config.yaml
	-sed -e 's~<PROJECT_ID>~$(PROJECT_ID)~g' ./config/deployment.yaml | kubectl apply -f -
update-deployment:
	-sed -e 's~<PROJECT_ID>~$(PROJECT_ID)~g' ./config/deployment2.yaml | kubectl apply -f -