/*
Copyright 2018 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"context"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"time"

	"go.opencensus.io/exporter/jaeger"
	"go.opencensus.io/plugin/ochttp"
	"go.opencensus.io/trace"
)

var (
	port           = getEnv("PORT", "3000")
	upstreamURI    = getEnv("UPSTREAM_URI", "http://time.jsontest.com/")
	serviceName    = getEnv("SERVICE_NAME", "test-1-v1")
	jaegerEndpoint = getEnv("JAEGER_ENDPOINT", "http://localhost:14268")
)

func init() {

	// Register jaeger as the trace exporter
	j, err := jaeger.NewExporter(jaeger.Options{
		Endpoint:    jaegerEndpoint,
		ServiceName: serviceName,
	})
	if err != nil {
		log.Fatal(err)
	}
	trace.RegisterExporter(j)

	// Set up the HTTP client to talk to downstreams
	http.DefaultClient = &http.Client{
		Transport: &ochttp.Transport{},
	}

	// Always trace for this demo.
	trace.SetDefaultSampler(trace.AlwaysSample())

}

func main() {
	http.HandleFunc("/", handleRoot)
	log.Fatal(http.ListenAndServe(":"+port, &ochttp.Handler{}))
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	// Get context from incoming request
	ctx := r.Context()

	// Do a GET to the downstream
	start := time.Now()
	out, err := callUpstream(ctx)
	if err != nil {
		out = err.Error()
	}
	elapsed := time.Since(start)

	// Return the service name, time elapsed, and the response body from the downstream
	fmt.Fprintf(w, "%s - %s\n%s -> %s", serviceName, elapsed, upstreamURI, out)
}

func callUpstream(ctx context.Context) (string, error) {
	if upstreamURI == "" {
		return "Done", nil
	}
	req, _ := http.NewRequest("GET", upstreamURI, nil)
	req = req.WithContext(ctx)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("Out not OK: %v", resp.Status)
	}
	b, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
