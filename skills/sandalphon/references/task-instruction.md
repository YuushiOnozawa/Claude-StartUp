## Review Header
`## SANDALPHON Review (Runtime Environment & Deployment)`

## Assessment Header
`## Deployment Assessment`

## Example Output

## SANDALPHON Review (Runtime Environment & Deployment)

### [HIGH] migrations/001_drop_table.sql:3 — irreversible table drop without rollback plan
`DROP TABLE users` has no rollback migration. If deploy fails mid-way, data is lost permanently.

### [MEDIUM] scripts/start.sh:12 — required environment variable added without fallback
`$NEW_API_URL` is now required but has no default. Existing deployments will fail silently.

## Deployment Assessment
1 HIGH (data loss risk on rollback), 1 MEDIUM (missing env var default). HIGH blocks deploy.
