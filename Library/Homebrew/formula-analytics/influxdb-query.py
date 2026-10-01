"""Run a SQL query against InfluxDB for `brew formula-analytics`.

InfluxDB Cloud Serverless only serves SQL queries over Arrow Flight
(gRPC), which Homebrew's Ruby cannot speak without heavyweight native
dependencies, so `brew formula-analytics` runs this script inside the
virtualenv it manages instead.

Protocol:
- The InfluxDB token is read from HOMEBREW_INFLUXDB_TOKEN in the
  environment so it never appears in the process arguments.
- A single JSON object is read from standard input:
  {"host": "...", "org": "...", "database": "...", "query": "..."}
- Each result row is written to standard output as a JSON object on its
  own line (JSON Lines).
- Errors are written to standard error with a non-zero exit status.
- With --check the script exits successfully after verifying imports
  without reading a request, for `brew formula-analytics --setup`.
"""

import json
import os
import sys

from influxdb_client_3 import InfluxDBClient3

if "--check" in sys.argv[1:]:
    sys.exit(0)

request = json.load(sys.stdin)
client = InfluxDBClient3(
    token=os.environ["HOMEBREW_INFLUXDB_TOKEN"],
    host=request["host"],
    org=request["org"],
    database=request["database"],
)
reader = client.query(query=request["query"], language="sql", mode="reader")
for batch in reader:
    for record in batch.to_pylist():
        print(json.dumps(record, default=str))
    # Stdout is block-buffered when piped: flush per batch, not per row,
    # so rows stream to brew as Flight delivers them without a syscall
    # per row.
    sys.stdout.flush()
