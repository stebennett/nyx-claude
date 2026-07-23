# design — check criteria

Read `checks/_method.md` first (the discipline and the return format); this file is your criterion
set. Checks `card-designer`. Your inputs: `card.md`, `slice.md`, `design.md`, the spec sections it
cites, `KNOWLEDGE.md`, and the ADR index.

| id | criterion | severity when failed |
|---|---|---|
| `DSG-AC-COVERED` | every acceptance criterion maps to at least one design task | blocking |
| `DSG-SPEC-FIDELITY` | `## Spec references` cite real spec sections, and the design contradicts none of them | blocking |
| `DSG-TASK-TDD` | the task list is file-level and TDD-ordered — a test precedes the code it drives | blocking |
| `DSG-DOCTRINE` | where the card's domain touches them, the design honours standing doctrine (below) | blocking |
| `DSG-ADR-NEEDED` | expensive-to-reverse decisions are proposed as ADRs, and none duplicates or silently contradicts a standing one | blocking |
| `DSG-KNOWLEDGE` | the design does not re-tread a gotcha already recorded in `KNOWLEDGE.md` | advisory |
| `DSG-SCOPE` | in/out of scope is explicit, and nothing in the design falls outside the card's acceptance criteria | blocking |
| `DSG-NO-CODE` | the design branch is docs-only — the design proposes no code files as *written*, only as tasks | blocking |

**`DSG-DOCTRINE` — what to check.** This is where `AGENT-PROTOCOL.md`'s Doctrine section stops being
advice and becomes something verified. For each doctrine rule, decide whether the card's domain touches
it; if it does, the design must say how it is honoured, and `na` is only correct when it genuinely does
not apply:
- **Spec outranks training** — the design cites the spec for every rule it implements, not memory.
- **Numeric precision** — any money/precision value: the project's decimal/rounding primitive is
  named, never a language default or binary float.
- **Parallel derived values** — where the spec defines two related computed quantities, the design
  names *which one* each consumer gets.
- **As-of semantics** — per-record figures come from the record's stored snapshot, not live reference
  data; replay order is deterministic (date, then id).
- **Determinism** — fixed clock, fixed seed, ordered queries, always; unit/domain tests hermetic
  (no I/O, no network); higher-level tests may use the project's declared test environment but must
  stay deterministic (pinned images, seeded data, readiness waits — never fixed sleeps).

**Walk:** Read `card.md`'s acceptance criteria and write your own list of the tasks you would expect,
*before* reading `design.md`'s task list. Then read the design. Map criteria → tasks (a criterion with
no task is `DSG-AC-COVERED`); map tasks → criteria (a task serving no criterion is `DSG-SCOPE`). Open
every spec section cited and confirm it says what the design claims. Read `docs/adrs/README.md` before
judging `DSG-ADR-NEEDED`.

**Don't flag:** a design choice you would have made differently that satisfies the criteria and
violates no doctrine (`DSG-*` is not a taste review — the lens panel reviews the code later); missing
generality the spec does not ask for (YAGNI is working); an ADR-worthy decision the design *does*
propose as an ADR.
