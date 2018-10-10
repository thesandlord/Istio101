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
const port = process.env.PORT || 3000
const upstream_uri = process.env.UPSTREAM_URI || 'http://time.jsontest.com/'
const service_name = process.env.SERVICE_NAME || 'opencensus-test-1-v1'

const express = require('express')
const app = express()
const request = require('request-promise-native')


// Start of OpenCensus setup ----------------------------------------------------------------------------

const opencensus = require('@opencensus/core')
const tracing = require('@opencensus/nodejs')
const propagation = require('@opencensus/propagation-b3')
const b3 = new propagation.B3Format()

// Set up jaeger
const jaeger = require('@opencensus/exporter-jaeger')

const jaeger_host = process.env.JAEGER_HOST || 'localhost'
const jaeger_port = process.env.JAEGER_PORT || '6832'

const exporter = new jaeger.JaegerTraceExporter({
	host: jaeger_host,
    port: jaeger_port,
	serviceName: service_name,
});

tracing.start({
	propagation: b3,
	samplingRate: 1.0,
    exporter: exporter
});


// Set up Prometheus
const prometheus = require('@opencensus/exporter-prometheus');

const prometheusExporter = new prometheus.PrometheusStatsExporter({
    startServer: true
})

// Set up custom stats
const stats = new opencensus.Stats()
const tags = {ServiceName: service_name};
const tagKeys = Object.keys(tags);

const fibCount = stats.createMeasureInt64('fib function invocation', '1')
stats.createView('fib_count', fibCount, 0, tagKeys,'number of fib functions calls over time', null)

stats.registerExporter(prometheusExporter)

// End of OpenCensus setup ----------------------------------------------------------------------------


app.get('/', async(req, res) => {

  const begin = Date.now()

  // Calculate a Fibbonacci Number and check if it is Odd or Even
  const childSpan = tracing.tracer.startChildSpan('Fibonacci Odd Or Even')
  const isOddOrEven = await oddOrEven(childSpan)
  childSpan.end()

  let up
  try {
    up = await request({url: upstream_uri})
  } catch (error) {
        up = error
  }
  const timeSpent = (Date.now() - begin) / 1000 + "secs (opencensus full)"

  res.end(`${service_name} - ${timeSpent} - num: ${isOddOrEven.num} - isOdd: ${isOddOrEven.isOdd}\n${upstream_uri} -> ${up}`)
})

app.listen(port, () => {
	console.log(`${service_name} listening on port ${port}!`)
})


function oddOrEven(span) {
  return new Promise(async (res,rej)=>{
    const fibSpan = tracing.tracer.startChildSpan('Fibonacci Calculation')
    fibSpan.parentSpanId = span.id
    const num = fibonacci(Math.floor(Math.random() * 30));
    fibSpan.end()

    // Random sleep! Because everyone needs their sleep!
    const sleepSpan = tracing.tracer.startChildSpan('Sleep')
    sleepSpan.parentSpanId = span.id
    await sleep()
    sleepSpan.end()
    
    res({
        isOdd: Boolean(num%2),
        num
    })
    
  })
}

function fibonacci(num) {
  stats.record({measure: fibCount, tags, value: 1})
  if (num <= 1) return 1;
  return fibonacci(num - 1) + fibonacci(num - 2);
}

function sleep() {
  return new Promise((res, rej) => {
    setTimeout(res,Math.random*2000)
  })
}