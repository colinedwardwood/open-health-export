### Closed request-template grammar

`RequestTemplate` is a non-Turing grammar: `{{name|directive}}` only, no conditionals or
evaluation. Directives are `header` (fail closed on CR/LF), `json` (quoted JSON string),
`query` (percent-encode), and `raw` (trusted engine fields only). Secrets are
`{{secret:handle|header}}`. The HTTPS URL host/path is never templated. Sample metadata is
not a slot, so it cannot inject headers or close JSON.
