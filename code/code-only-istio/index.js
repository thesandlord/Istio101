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
const upstream_uri = process.env.UPSTREAM_URI || 'http://worldclockapi.com/api/json/utc/now'
const service_name = process.env.SERVICE_NAME || 'test-1-v1'

const express = require('express')
const app = express()
const request = require('request-promise-native')

app.get('/', async(req, res) => {

	const begin = Date.now()

	// Do Bad Things
	createIssues(req, res)

	// Forward Headers for tracing
	const headers = forwardTraceHeaders(req)

	let up
	try {
		up = await request({
			url: upstream_uri,
			headers: headers
		})
	} catch (error) {
		up = error
	}
	const timeSpent = (Date.now() - begin) / 1000 + "secs"

	res.end(`${service_name} - ${timeSpent}\n${upstream_uri} -> ${up}`)
})

app.listen(port, () => {
	console.log(`${service_name} listening on port ${port}!`)
})



function forwardTraceHeaders(req) {
	incoming_headers = [
		'x-request-id',
		'x-b3-traceid',
		'x-b3-spanid',
		'x-b3-parentspanid',
		'x-b3-sampled',
		'x-b3-flags',
		'x-ot-span-context',
		'x-dev-user',
		'fail'
	]
	const headers = {}
	for (let h of incoming_headers) {
		if (req.header(h))
			headers[h] = req.header(h)
	}
	return headers
}



function createIssues(req, res) {
	// Look at the "fail %" header to increase chance of failure
	// Failures cascade, so this number shouldn't be set too high (under 0.3 is good)
	const failPercent = Number(req.header('fail')) || 0
	console.log(`failPercent: ${failPercent}`)
	if (Math.random() < failPercent) {
		res.status(500).end()
	}
}