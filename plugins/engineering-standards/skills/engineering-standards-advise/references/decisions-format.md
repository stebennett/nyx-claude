# The `## Technology decisions` section

`engineering-standards-advise` writes this section into a spec; `engineering-standards-scaffold`
reads it back. Keep the heading, field names and values exactly as below so scaffold can map them
across without asking again.

## Shape

```markdown
## Technology decisions

Checked against Engineering Standards v<framework_version>.

| Field | Value | Source |
|---|---|---|
| type | ... | ... |
| status | ... | ... |
| backend | ... | ... |
| frontend | ... | ... |
| deployment_target | ... | ... |
| database | ... | ... |
| lightweight | ... | ... |
| <open-choice> | ... | ... |

### Exemptions

- <CRITERION-ID>: <reason>
```

`<framework_version>` is the `Version` line of `standards.md` (e.g. `1.4`). A section stamped with
a different version is stale: re-run the advise flow before scaffolding from it.

## Required rows, in this order

| Field | Allowed values |
|---|---|
| `type` | `service` \| `library` \| `cli` |
| `status` | `active` \| `maintained` \| `archived` (default `active`) |
| `backend` | `go` \| `python` \| `none`; any other language only with matching exemptions (STK-1) |
| `frontend` | `none` \| `typescript (<framework>)`, e.g. `typescript (react + vite)` |
| `deployment_target` | `fly` \| `cloudflare` \| `kubernetes` \| `none` |
| `database` | `postgresql` \| `sqlite` \| `d1` \| `none`; any other database only with matching exemptions (DAT-1) |
| `lightweight` | `true` \| `false`. When `database` is `sqlite` or `d1`, follow the value with one short answer to each DAT condition: single instance with one writer; no other service touches the data; losing data since the last backup is acceptable. `true` needs all three |

After the required rows, add one row per open choice the standards do not settle. `Field` is a
short kebab-case name: `web-framework`, `orm`, `migration-tool`, `http-router`, `queue`,
`auth-library`, `frontend-test-runner`, and so on.

## Source

| Value | Meaning |
|---|---|
| `mandated` | Fixed by the standards; nobody chose it |
| `spec` | Stated in the spec and compliant (or kept as an exemption) |
| `user` | The user picked it when asked |
| `advisor-suggestion-accepted` | The user handed the choice over and accepted the advisor's suggestion |

Mandated choices (`just`, GitHub Actions, Renovate, Docker Hardened Images, Dev Container, Helm for
Kubernetes, exact pinning) need no rows of their own; they apply to every repo. Add a row only when
the spec explicitly states one, so a reader can see it was checked.

## Exemptions

One line per kept deviation: `- <CRITERION-ID>: <reason>`, the reason in the user's words. Omit
the sub-section when there are none. A deviation that changes the stack (a backend other than Go
or Python, a database outside the enum) means scaffold builds only the stack-neutral parts.

## Mapping to the `.nyx.yml` tag

| Decisions field | Tag key | Rule |
|---|---|---|
| `type` | `type` | as is |
| `status` | `status` | as is |
| `deployment_target` | `deployment_target` | as is |
| `database` | `database` | as is when in the enum; otherwise `none`, and the DAT-1 exemption reason names the actual database |
| `lightweight` | `lightweight` | the boolean only; `false` unless `database` is `sqlite` or `d1` |
| `### Exemptions` | `exemptions` | `[{id, reason}]` per line |
| (derived) | `optional_categories` | the `O` categories in the standards section 3 matrix for the type that the repo will adopt: `DAT` when `database` is not `none` and DAT is optional for the type; any other `O` category only when the user says yes (scaffold asks, as classify does) |
| `backend`, `frontend`, open choices | — | not in the tag; scaffold uses them to choose checklist entries |

## Example: Go service on Kubernetes with PostgreSQL

```markdown
## Technology decisions

Checked against Engineering Standards v1.4.

| Field | Value | Source |
|---|---|---|
| type | service | spec |
| status | active | mandated |
| backend | go | user |
| frontend | none | spec |
| deployment_target | kubernetes | user |
| database | postgresql | spec |
| lightweight | false | user |
| http-router | chi | advisor-suggestion-accepted |
| migration-tool | goose | advisor-suggestion-accepted |
```

Tag: `{"type":"service","status":"active","deployment_target":"kubernetes","database":"postgresql","lightweight":false,"optional_categories":[],"exemptions":[]}`
(`DAT` is required for a service, so it is not an optional category here.)

## Example: kept MySQL exemption

```markdown
| database | mysql | spec |
...

### Exemptions

- DAT-1: Shares the existing MySQL instance run by the household finance app
```

Tag: `"database": "none"`, `"exemptions": [{"id": "DAT-1", "reason": "MySQL (shares the existing MySQL instance run by the household finance app)"}]`.
Scaffold leaves the database parts to the user and says so.
