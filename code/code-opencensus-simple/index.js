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

const tracing = require('@opencensus/nodejs');
const propagation = require('@opencensus/propagation-b3');
const b3 = new propagation.B3Format();

tracing.start({
	propagation: b3,
	samplingRate: 1.0
});

const express = require('express')
const app = express()
const request = require('request-promise-native')

app.get('/', async(req, res) => {
	const begin = Date.now()

	let up
	try {
		up = await request({
			url: upstream_uri
		})
	} catch (error) {
		up = error
	}
	const timeSpent = (Date.now() - begin) / 1000 + "secs (opencensus simple)"

	res.end(`${service_name} - ${timeSpent}\n${upstream_uri} -> ${up}`)
})

app.listen(port, () => {
	console.log(`${service_name} listening on port ${port}!`)
})