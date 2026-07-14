# Review panel — lenses

One `card-lens-reviewer` agent is dispatched per lens at the card's **review** phase, against the
branch diff in the card's worktree — **before any PR opens**. Together the panel is
`card-implementer`'s checker: blocking findings feed the automatic rework loop, so the PR the human
eventually sees has already survived every lens. Each expert reads the two shared sections
(**Etiquette**, **Method**) plus **only its own lens section**. Checklists distil
[Google's eng-practices reviewer guide](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
onto this codebase.

Each lens section has the same shape: **Focus** (your one job), **Walk** (the procedure — follow it
in order, don't freestyle), **Ask of every hunk** (anchor questions to hold in mind on the
line-by-line pass), **Red flags** (concrete patterns, greppable where possible), **Don't flag**
(known false positives — a wrong finding costs the implementer a rework loop), and a worked
**Example finding** showing the calibration bar and finding shape.

## Etiquette (every lens)
- Every finding **starts with your tag**, e.g. `[design] …` or `[security] …`.
- **Severity is `blocking` or `advisory`.** `blocking` = correctness, spec violation, broken
  invariant, or an acceptance criterion with no test — it goes back to the implementer verbatim and
  costs a rework loop from a finite budget. `advisory` = polish, nits, and things you suspect but
  could not verify; these ride the PR for the human and never trigger rework. **Do not inflate.** A
  card that burns its rework budget on nits parks for the driver.
- Comment on the code, never the author ("this function recomputes…", not "you recompute…").
- Every finding is anchored to `path:line` in the branch diff.
- Stay in your lane: skip findings clearly owned by another lens unless severe and likely missed.
- Max 10 findings — but never pad toward it. Two verified findings beat ten speculative ones.
- Mention one notable good thing in your phase doc when you see it. Reviews teach.
- You do not touch GitHub. There is no PR yet.

## Method (every lens — this is how you avoid being a shallow reviewer)

1. **Map pass, then line pass.** First read the whole diff end to end *without writing anything*,
   plus `design.md`, to understand what the change is and why. Only then go line-by-line through
   your lens with the anchor questions. Findings written during the first pass are skims — don't.
2. **Verify before you file it.** A pattern-match is a *hypothesis*, not a finding. Before writing
   a finding, check the worktree for the counter-evidence: read the surrounding function, grep for
   the validation/test/caller you claim is missing (`grep -rn` is cheap; a wrong finding is not).
   If you can't verify it, either drop it or record it honestly as `advisory` with what you checked.
3. **The rebuttal test.** Before filing a blocking finding, imagine the author's strongest one-line
   defence ("that's validated upstream in X", "the spec requires exactly this", "that case can't
   occur because Y"). If the defence wins, drop it. If you can't tell, make it `advisory`.
4. **Finding formula — observation → consequence → fix.** (a) What is true at this line, stated
   as fact you verified. (b) Why it matters: the concrete failure, wrong figure, or maintenance
   cost — cite the spec rule or invariant when one applies. (c) The smallest concrete fix — a
   ` ```suggestion ` block when the patch is small and you are certain it compiles/passes.
   A finding missing any of the three is not ready to file.
5. **Trace, don't vibe.** For behavioural claims, follow the actual data flow: where does this
   value come from, who has already checked it, where does it go? Quote the evidence in the
   finding ("`rt` here comes from `list_rate()` at pricing.py:41, but reward points
   need the *net* rate — spec §4.2").
6. **Zero findings must be earned.** If you find nothing, your returned phase_doc lists what you
   checked and found clean ("traced both rate paths; checked all 6 rounding call sites reuse
   `round_half_up`; …"). "No findings" without the list means "didn't look" and will be treated
   as such by `/retro`.
7. **Anchor precisely.** File the finding at the exact line where the fix goes, not the hunk
   header. If a finding spans files, put one finding at the primary site and mention the others in
   it — don't scatter duplicates.

## [acceptance]
**Focus:** Does this branch actually deliver the card, and does it hold the project's invariants?
You are the lens that absorbed the old `card-reviewer` — traceability and conventions are yours, and
if you do not check them, nobody does.

**Walk:**
1. **Traceability, criterion by criterion.** For every acceptance criterion in `design.md`, name the
   specific test(s) that prove it — file and test name. A criterion with no test is a **blocking**
   finding, always. This is the single highest-value check on the panel: a card can be beautiful,
   secure, simple and readable and still not do what it was asked to do.
2. **Scope, both directions.** Anything in the diff outside `design.md`'s in-scope list is a
   drive-by; anything in the in-scope list absent from the diff is unfinished. Both are findings.
3. **Convention adherence:** `KNOWLEDGE.md`'s Conventions section, and the project invariants — core
   logic only in its designated layer; adapters and wrappers hold no business logic; the spec's exact
   rounding rule, never a language default.
4. **Deviation audit:** read `implement.md`'s `## Deviations from design`. Every deviation is either
   justified in writing or a finding.

**Ask of every hunk:** Which acceptance criterion does this line serve? If none — why is it here?

**Red flags:** an acceptance criterion whose "test" only asserts the function returns without
raising; a criterion marked done in `implement.md` with no corresponding test; production code with
no test touching it at all; a `## Deviations from design` section that is empty on a diff that
plainly departs from the design; business logic outside its designated layer.

**Don't flag:** test *quality* (that's `[tests]`'s lane — you check a criterion has *a* test; they
check it would catch a bug); design elegance (`[design]`); missing criteria the card never claimed.

**Example finding.** `design.md` lists AC-3 "a voided line item is excluded from the order total",
and `implement.md` marks it done. Grep of the diff finds `tests/domain/test_totals.py` with
`test_total_sums_lines` and `test_total_empty_order` — neither constructs a voided line.
Finding: `[acceptance] blocking — tests/domain/test_totals.py: AC-3 (voided line items excluded from
the total) has no test. The two tests here cover the happy path and the empty case; neither builds a
voided line, so the exclusion branch in domain/totals.py:34 is unproven and would pass CI even if it
were inverted. Add a test with one voided and one live line asserting the total equals the live line
only.`

## [design]
**Focus:** Is this change well-designed, in the right place, and built to be extended by the next
card rather than fought by it?

**Walk:**
1. From `design.md` and the diff map, draw the dependency picture: which layer does each new/changed
   module sit in, who imports whom, which direction do the arrows point?
2. Check every arrow against the architecture: `domain` imports nothing but stdlib; `db`/`api`
   import domain, never the reverse; the adapter layer imports neither (HTTP client only); web
   calls the API only.
3. For each new public interface, ask what the *next* card in `MILESTONES.md` needs from it —
   will it extend cleanly or need reshaping?
4. Look for logic in the wrong home: business rules in routers, schema logic in domain, rendering
   maths in React.

**Ask of every hunk:** Does this belong in this module? Could this interact badly with something
that already exists? Is this the right time for this abstraction, or is it speculative?

**Red flags:** pricing/billing arithmetic outside `domain/`; `from myapp.db` or framework imports
inside `domain/`; adapter-layer code importing the ORM or DB models directly; web code computing
totals/differentials/rates itself; a "utils" module accreting unrelated helpers; a new abstraction
with exactly one implementation and no second one on the milestone plan; a discount rate read from
the standard price list instead of the customer's region-specific price list.

**Don't flag:** placement that follows an existing, established pattern in the codebase (consistency
beats your preference — Google's rule); missing generality the spec doesn't ask for (that's YAGNI
working as intended); alternatives already weighed and rejected in `design.md` — argue with the
recorded reasoning only if it's factually wrong.

**Example finding.** Diff adds to `api/routers/orders.py`:
```python
points = max(0, base_reward + threshold - amount_due)
```
Finding: `[design] blocking — This computes reward points inline in the router. Pricing rules must
live in domain/ as pure functions (the project's single-implementation invariant — CLAUDE.md); a
second caller (the adapter's contract tests, nightly reporting) will otherwise duplicate it. Move to
domain/pricing.py::reward_points() and call it here; the router should only shape the response.`

## [functionality]
**Focus:** Does the code do what the PR intends, and is that behaviour right for users and for
future developers — especially at the edges?

**Walk:**
1. Restate (to yourself) each acceptance criterion from `design.md`; find the code path that
   satisfies it; follow that path with real values, by hand, at least once.
2. Run the edge-case sweep against every calculation the diff touches: exact `.5` values; rating
   clamps at the valid range's floor/ceiling (0/100); voided/missing line items; single-item vs
   multi-item orders; no-rating-established-yet (a wider provisional cap); the 20th vs 21st order;
   same-date orders; an order whose price list was later edited (snapshot semantics).
3. For every rate value, trace which path it came from: the list rate (100%) → caps/adjusted
   totals/differential; the net rate (list rate × the account's discount allowance) → the
   customer-facing reward points. Confirm each consumer got the right one.
4. For writes: what recomputes? A confirmed-order edit must replay every later order; a
   draft-order change must not touch confirmed figures.

**Ask of every hunk:** What input makes this line wrong? Who calls this with data the author
didn't picture? Is this ordering deterministic?

**Red flags:** `sorted(...)` on date alone (same-date orders need a tiebreaker — date then id);
slicing for "most recent 20" without confirming sort direction; rates read from the live price
tables at billing time instead of the order's stored snapshot; "today's" rating used for a
historical order's figures; `if item_count == 1` with a bare `else` silently absorbing bundle and
other multi-item orders; float equality or `pytest.approx` on money figures; off-by-one in a
proration table (last unit vs first, half-period boundary).

**Don't flag:** behaviour that matches a spec rule you find surprising (verify against the spec's
worked examples before commenting — the spec wins); edge cases `design.md` explicitly scopes out
to a later card (check `## Out of scope` first).

**Example finding.** Diff in `domain/loyalty.py`:
```python
recent = sorted(orders, key=lambda o: o.placed_on)[-20:]
```
Finding: `[functionality] blocking — Orders placed on the same date have no tiebreaker here, so the
selected "most recent 20" set (and therefore the loyalty rating) is nondeterministic across runs —
the test fixtures have single-date orders, which is why nothing catches it. Sort by (placed_on, id):`
```suggestion
recent = sorted(orders, key=lambda o: (o.placed_on, o.id))[-20:]
```

## [simplicity]
**Focus:** Could a smaller, plainer diff satisfy the same acceptance criteria? "A reviewer can't
understand it quickly" *is* the defect.

**Walk:**
1. Read each new function once, at reading speed. Note every place you had to stop and re-read —
   each is a candidate finding (rename, extract, or simplify).
2. For each new class, layer of indirection, config option, or parameter: find the second caller
   or the acceptance criterion demanding it. No second use and no criterion → speculative.
3. Diff-size audit: list what the change touches beyond `design.md`'s file list (drive-by
   refactors belong on their own card).
4. Reuse check: grep for existing helpers the diff reimplements (`round_half_up`, existing
   fixtures/schemas, seed loaders).

**Ask of every hunk:** What would the boring version of this look like? What can be deleted with
no acceptance criterion failing?

**Red flags:** an interface/ABC/Protocol with one implementation; a registry or strategy pattern
dispatching between two known cases (an `if` is fine); pass-through wrapper functions; parameters
every caller passes with the same value; a hand-rolled reimplementation of something in the
codebase or stdlib; "flexible" config the spec never mentions; deep nesting where guard clauses
would flatten it.

**Don't flag:** intrinsic domain complexity (the chronological replay genuinely is intricate —
simplify the expression of it, not the rules); the pure-function/plain-data style of `domain/`
(that's a project invariant, not over-engineering); code that follows an established codebase
pattern.

**Example finding.** Diff adds `domain/pricing_strategies.py` with a `PricingStrategy` Protocol,
`StandardPricingStrategy`, `PromotionalPricingStrategy`, and a registry dict. Finding: `[simplicity]
advisory — Three files of indirection dispatch between exactly two cases that the spec fixes forever
(standard and promotional — no third tier exists). A single function with one branch says the same
thing in ~10 lines and gives the next reader one place to look: def price_order(order): if
order.is_promotional: … else: …. The Protocol earns its keep only when a third variant exists, and
none is on the milestone plan.`

## [tests]
**Focus:** Would these tests fail if the code were wrong? Tests that mirror the implementation,
assert too weakly, or skip the boundaries are worse than missing — they certify bugs.

**Walk:**
1. **Read the tests before the production code.** For each test, predict what implementation bug
   it would catch. A test you can't name a caught-bug for is decoration.
2. Provenance-check every expected value: it must come from a spec worked example, the shipped
   fixture, or hand arithmetic you can reproduce in the comment. If the expected value could only
   have been produced by running the code under test, flag it.
3. Map acceptance criteria → tests (design.md lists both). Criterion with no test → finding.
4. Boundary audit: for every clamp/cap/threshold in the diff, look for the test at the boundary,
   just inside, and just outside (the rating's valid-range floor/ceiling, `.5` cases, the cap
   formula's edge, 20th/21st order).
5. Hypothesis check: strategies constrained to valid domain ranges; asserts real invariants
   (bounds, monotonicity, idempotency), not just "doesn't raise"; fixed profile/seed for CI.
6. **Branch & outcome coverage (esp. UI and adapter code).** Enumerate the distinct outcomes and
   render variants the unit under test can take, and confirm each has its own test:
   - **Every failure OUTCOME gets its own stub.** A handler that branches on *why* it failed has
     more outcomes than "ok vs not-ok" — e.g. a fetch wrapper with a distinct not-found path has
     three (not-found, other-error, network-reject), and a single not-found stub leaves the
     generic error branch unexercised.
   - **Render EVERY variant, not one representative.** Both sides of a two-way split, each
     status/state a row can render, each visual mark — a variant no test renders is a mutation
     that survives.
   - **Pick DISCRIMINATING fixtures and assertions.** No substring assertion whose negative case
     contains the positive (`"inactive".includes("active")`); no fixture symmetric across the very
     branch the test means to distinguish (both branches computing the same number). The expected
     value must differ between the branch under test and its sibling, or the assertion can't fail
     on a swap.

**Ask of every hunk (of test code):** What bug slips through this assertion? Where did this
expected value come from? What happens at the boundary ±1?

**Red flags:** expected values computed with the same formula as the implementation (`assert
differential == round((100/factor)*(total-reference), 1)` proves nothing); `pytest.approx`/float
tolerance on money values (they're exact `Decimal`s); asserting only types/lengths/"is not None";
mocking pure domain functions; tests asserting private call order (implementation-coupled); a
single happy-path test for a function full of branches; `@settings(deadline=None)` hiding a slow
strategy; a `toContain`/substring assertion whose negative case contains the positive; a fixture
symmetric across the very branch it means to discriminate; only one of a component's render
variants exercised; a multi-outcome error handler tested with a single failure stub.

**Don't flag:** coverage % by itself (card-tester owns the number — you own whether the tests
*mean* anything); E2E gaps when the card's test strategy explicitly defers them.

**Example finding.** Diff in `tests/domain/test_price_differential.py`:
```python
def test_price_differential():
    assert price_differential(total=85, reference=Decimal("70.2"), factor=125) == \
        round_half_up(Decimal(100) / 125 * (85 - Decimal("70.2")), 1)
```
Finding: `[tests] blocking — The expected value is computed with the same formula and helpers as
the implementation, so this test passes even if the formula itself is wrong (e.g. factor and the
scaling constant inverted — both sides invert together). Assert the literal: the spec's worked
example gives (100/125)×(85−70.2) = 11.84 → 11.8. `
```suggestion
    assert price_differential(total=85, reference=Decimal("70.2"), factor=125) == Decimal("11.8")
```

## [readability]
**Focus:** Could the next card's implementer understand and safely modify this in one read?
Naming, comments-that-explain-why, consistency, and docs that still tell the truth.

**Walk:**
1. Unfamiliar-reader pass: read each changed file top to bottom pretending you haven't seen
  `design.md`. Note every identifier whose meaning you had to infer and every block you had to
  re-read.
2. Comment audit: each comment must say *why*, or explain genuinely non-obvious *what* (a domain
   rule, a spec citation). Comments restating the code, stale TODOs, leftover scaffolding → flag.
3. Consistency sweep: naming and idioms match neighbouring code? (Existing style wins even where
   you'd choose differently.)
4. Docs: does the diff change behaviour that README/CLAUDE.md/docstrings/OpenAPI descriptions
   describe? Are they updated?

**Ask of every hunk:** Would I understand this identifier out of context? Does this comment earn
its line? Will this doc sentence still be true after merge?

**Red flags:** `rt`/`rate` naming that doesn't say *which* rate (list? net? loyalty rating? — in
this codebase that ambiguity causes real bugs, cf. the two-path invariant); single-letter names
outside tight comprehensions; magic numbers where the spec has a name (100, 0.95, the rating
ceiling — name them or cite the rule inline); functions whose name promises less/more than they do
(`get_total` that also persists); mixed formatting the linters would fix (point at the linter,
don't hand-fix in review).

**Don't flag:** style the project's formatters/linters already enforce or permit (don't
relitigate ruff/prettier); domain vocabulary that's standard for this system (list rate,
differential, proration are the *right* jargon here — see the spec glossary); length alone.

**Example finding.** Diff in `domain/rewards.py`:
```python
def points(amount: int, threshold: int, rt: int) -> int:
```
Finding: `[readability] advisory — rt doesn't say which rate this is, and in this codebase that
ambiguity is dangerous — reward points must use the net rate (list rate × the account's discount
allowance), not the list rate (spec §4.2). Naming the parameter net_rate makes a caller passing
the wrong one visibly wrong at the call site.`

## [security]
**Focus:** The trust boundaries: API input, DB queries, outbound HTTP, secrets, dependencies, and
the container/release surface. A small user base ≠ no threat model — it still ships as a network
service.

**Walk:**
1. Boundary inventory: list every point in the diff where external data enters (endpoints, query
   params, seed/file loads, adapter tool args) and every point where data leaves (DB, httpx, logs,
   filesystem).
2. For each input: what constrains it? Pydantic types must actually bound it (ranges on amounts/
   quantities/dates, enum for category names, max lengths on strings) — `str`/`int` alone is not
   validation. Trace the value to first use: what breaks with 10⁹ line items, a negative amount,
   a 10 MB string?
3. For each query: parameters bound by SQLAlchemy, or string-built? Any raw `text()` with
   interpolation?
4. For each outbound call (adapter-layer httpx): timeout set? URL fixed/allowlisted, or
   attacker-influenced (SSRF)? TLS verification untouched?
5. Sweep for secrets and config: hardcoded tokens/paths in code, compose files, CI, k8s manifests;
   containers running as root; new dependencies (pinned? maintained? why this one?).

**Ask of every hunk:** Where did this value come from, and who checked it? What's the worst input
that reaches this line? What does an attacker on the same network get?

**Red flags:** f-strings/`%`/`+` building SQL or shell commands; `text(f"…")`; `httpx` calls with
no `timeout`; user-supplied path segments reaching `open()`/`Path` without normalization;
`verify=False` anywhere; secrets in envs committed to the repo; `debug=True`/wide-open CORS in
anything that ships; Pydantic models with unconstrained fields on write endpoints; new deps
without pins.

**Don't flag:** theoretical attacks the spec explicitly scopes out (e.g. multi-tenant isolation in
a single-tenant system with no other tenants), unless the code pretends to have that boundary and
gets it wrong; hardening already handled at a different layer (verify the layer exists, then stay
silent).

**Example finding.** Diff in `adapter/src/client.py`:
```python
resp = httpx.get(f"{base_url}/orders/{order_id}")
```
Finding: `[security] blocking — Two issues at this call: no timeout (a hung API blocks the adapter
service indefinitely — httpx has no default timeout), and order_id is interpolated into the path
unchecked — a value like "1/../../admin" changes the target route. Use the typed client with a
timeout and params, and validate order_id as int in the tool schema before it gets here:`
```suggestion
resp = client.get(f"/orders/{int(order_id)}", timeout=10.0)
```

## [python]
*This lens assumes a Python/FastAPI/SQLAlchemy stack — this file is copied into the target repo and
editable, so tune the stack names below to the project's actual toolchain.*

**Focus:** Language-expert review of `*.py` changes — idioms, typing, and the specific traps of
this stack (Decimal/money maths, SQLAlchemy 2.x, FastAPI, Pydantic v2, Alembic+SQLite, pytest/Hypothesis).

**Walk:**
1. Numeric audit first (highest-stakes): every money/precision value is `Decimal` end to end —
   constructed from `str`/`int`, compared exactly, rounded only via the `domain/` primitive. `grep -n
   'round(\|float(\|Decimal(' ` over the diff and inspect each hit.
2. Typing pass: signatures precise enough for mypy strict in `domain/` (no implicit `Any`,
   `Optional` explicit, return types on everything public).
3. Framework pass: SQLAlchemy 2.x style (`select()`, typed `Mapped[]`, session lifecycle owned by
   the request, relationship loading explicit — hunt N+1s in list endpoints); FastAPI (correct
   `response_model`, dependencies over globals, **no blocking DB/CPU work in `async def` paths**);
   Pydantic v2 (`model_config`, `field_validator`, no v1 idioms).
4. Migration pass (if Alembic files): SQLite ALTERs need `batch_alter_table`; downgrade defined;
   no data-destroying autogen surprises; seed stays idempotent.
5. General idiom sweep: mutable default args, bare `except:`/over-broad `except Exception`,
   resources without context managers, `os.path` where `pathlib` is the codebase norm, dict access
   chains that should be a dataclass.

**Ask of every hunk:** Would mypy strict accept this? Is this how SQLAlchemy 2.x / Pydantic v2
wants it written? What does this line do with a `float` that looks like an int?

**Red flags:** `Decimal(0.1)` (float constructor — the value is already wrong before rounding);
bare `round()` on any money figure; `dict`-typed payloads crossing layer boundaries; `async def`
endpoint calling a sync session; `Session()` created ad hoc instead of the dependency;
`.query(...)` legacy API; comparing dates as strings; Hypothesis strategies over unconstrained
floats/text for domain values; `# type: ignore` without an issue reference.

**Don't flag:** stdlib `round()` on non-money values where banker's is harmless and no project
convention applies (verify it's truly non-money first); style ruff already enforces; `assert` in
tests (that's pytest idiom, not production `assert` misuse).

**Example finding.** Diff in `domain/rates.py`:
```python
return round_half_up(Decimal(rating * factor / 100) + (base_rate - reference_rate), 0)
```
Finding: `[python] blocking — rating * factor / 100 is computed in float before Decimal sees it, so
the value carries binary representation error into the half-up rounding — exactly the class of bug
the Decimal convention exists to prevent (a true x.5 can arrive as x.4999…). Keep the arithmetic in
Decimal end to end:`
```suggestion
return round_half_up(Decimal(rating) * factor / Decimal(100) + (base_rate - reference_rate), 0)
```

## [typescript]
*This lens assumes a React/Vite stack — this file is copied into the target repo and editable, so
tune the stack names below to the project's actual toolchain.*

**Focus:** Language-expert review of `*.ts`/`*.tsx` changes — type safety, React correctness, and
this stack's specifics (Vite, Tailwind design tokens, Recharts, API-data-only rendering).

**Walk:**
1. Type-safety pass: `grep -n 'any\|as \|!' ` over the diff — every `any`, assertion cast, and
   non-null `!` needs a justification the code makes visible; API response types should come from
   one shared source, not be redeclared per component.
2. Hooks pass: for each `useEffect`/`useMemo`/`useCallback` — deps complete and stable? cleanup
   returned where it subscribes/schedules? Is the effect necessary at all (derived data belongs in
   render or `useMemo`, not `useState`+effect mirrors)?
3. Data-flow pass: every fetch has loading and error states rendered (not just the happy path);
   no pricing/totals arithmetic recomputed client-side — the API's figures are the truth
   (project invariant); list keys stable and identity-based (never array index for reorderable
   data).
4. Design-system pass: colors/fonts via the project's design tokens (e.g. primary/secondary/
   surface/text, accent), not hex literals; figures/stats in the mono font per the design bundle;
   interactive elements are semantic elements (`button`, labels tied to inputs).
5. Build hygiene: nothing secret in client code (`import.meta.env` only exposes `VITE_*` — check
   nothing sensitive is named into exposure); heavy chart data memoized before Recharts.

**Ask of every hunk:** What does the compiler no longer check because of this line? What happens
on the render *before* the data arrives? Does this state duplicate something derivable?

**Red flags:** `as unknown as T` / double casts; `useEffect` with an incomplete dep array
"because it loops" (fix the dependency identity instead); state mirrored from props;
`key={index}` on order/line-item lists; unhandled promise in an event handler; hex color literals
where a token exists; a component reimplementing `PriceCell` markings instead of reusing it;
`fetch` scattered per-component instead of the shared API client.

**Don't flag:** prettier/eslint-enforced formatting; explicit types where inference would work
(verbose ≠ wrong); missing tests (that's `[tests]`'s lane — you flag *untypeable* or *untestable*
component design only).

**Example finding.** Diff in `web/src/components/OrderSummary.tsx`:
```tsx
const [total, setTotal] = useState(0);
useEffect(() => { setTotal(lines.reduce((s, l) => s + l.amount, 0)); }, [lines]);
```
Finding: `[typescript] advisory — total is derived data mirrored into state via an effect — it
renders one frame stale after lines changes and adds a render cycle. Derive it in render (or
useMemo if lines is large). Also note the summed total must come from the API's per-line figures,
never be recomputed from unit prices client-side:`
```suggestion
const total = lines.reduce((s, l) => s + l.amount, 0);
```
