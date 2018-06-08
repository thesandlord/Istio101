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
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"time"

	"go.opencensus.io/stats"

	"go.opencensus.io/exporter/jaeger"
	"go.opencensus.io/exporter/prometheus"
	"go.opencensus.io/plugin/ochttp"
	"go.opencensus.io/stats/view"
	"go.opencensus.io/trace"
)

var (
	port           = getEnv("PORT", "3000")
	upstreamURI    = getEnv("UPSTREAM_URI", "http://time.jsontest.com/")
	serviceName    = getEnv("SERVICE_NAME", "test-1-v1")
	jaegerEndpoint = getEnv("JAEGER_ENDPOINT", "http://localhost:14268")

	// Stats
	fibCount *stats.Int64Measure
)

func init() {

	// Register prometheus as the stats exporter
	p, err := prometheus.NewExporter(prometheus.Options{})
	if err != nil {
		log.Fatal(err)
	}
	view.RegisterExporter(p)
	http.Handle("/metrics", p)

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

	// Set up custom stats

	// Number of times the fib function is called
	fibCount, err = stats.Int64("demo/measures/fib_count", "fib function invocation", "")
	if err != nil {
		log.Fatalf("Fib count measure not created: %v", err)
	}
	numFibCount, err := view.New(
		"fib_count",
		"number of fib functions calls over time",
		nil,
		fibCount,
		view.CountAggregation{},
	)
	if err != nil {
		log.Fatalf("Cannot create view: %v", err)
	}
	if err := numFibCount.Subscribe(); err != nil {
		log.Fatalf("Cannot subscribe to the view: %v", err)
	}

	// Always trace for this demo.
	trace.SetDefaultSampler(trace.AlwaysSample())
	// Set reporting period to report data at every second.
	view.SetReportingPeriod(1 * time.Second)
}

func main() {
	http.HandleFunc("/", handleRoot)
	log.Fatal(http.ListenAndServe(":"+port, &ochttp.Handler{}))
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	// Get context from incoming request
	ctx := r.Context()

	fibCtx, fibSpan := trace.StartSpan(ctx, "Fibonacci Odd Or Even")
	isOddOrEven, number := oddOrEven(fibCtx, rand.Intn(5)+20) // Random Fibonacci number between 25 and 30
	fibSpan.End()

	// Do a GET to the downstream
	start := time.Now()
	out, err := callUpstream(ctx)
	if err != nil {
		out = err.Error()
	}
	elapsed := time.Since(start)

	// Return the service name, fib number, time elapsed, and the response body from the downstream
	fmt.Fprintf(w, "%s - %d - %t - %s\n%s -> %s", serviceName, number, isOddOrEven, elapsed, upstreamURI, out)
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

func oddOrEven(ctx context.Context, n int) (bool, int) {
	calcCtx, span := trace.StartSpan(ctx, "Fibonacci Calculation")
	num := fib(calcCtx, n)
	span.End()

	sleepCtx, span := trace.StartSpan(ctx, "Sleep")
	cmd := exec.CommandContext(sleepCtx, "sleep", "0.3")
	cmd.Wait()
	span.End()

	if num%2 == 0 {
		return true, num
	}
	return false, num
}

func fib(ctx context.Context, n int) int {
	stats.Record(ctx, fibCount.M(1))
	if n == 0 || n == 1 {
		return n
	}
	return fib(ctx, n-2) + fib(ctx, n-1)
}
