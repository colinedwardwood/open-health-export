FIX-F09: refuse a JSON sidecar larger than 2 GiB, and split CSV quantity
files at the 1,048,576-row spreadsheet limit. NDJSON remains the unbounded
streaming archive; these limits apply only to the compatibility encodings.
