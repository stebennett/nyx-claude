# kanban-flow — design rationale

Design rationale for kanban-flow. Never dispatched to agents; read it when editing the plugin.

The operational rules live in the templates and agent files an agent actually reads
(`templates/AGENT-PROTOCOL.md`, `templates/checks/`, `templates/lenses/`, the `agents/` files). This
file holds the *why* behind the load-bearing ones — the arguments that justify a rule but that an agent
does not need in front of it to execute. Each section names the file and rule it explains.

## `templates/checks/_method.md` — why the checker contract is enforced, not requested

An LLM checking an LLM tends to rubber-stamp: handed a producer's artifact that argues its own case, a
checker that reads the argument first is only agreeing with it, and it will not notice that it is. The
whole check layer exists to counter that tendency, and two of its rules are *enforced* by the
orchestrator rather than merely stated, because a rule a checker can quietly skip is not a safeguard.

**Verdict-every-criterion (why an omission is malformed).** The orchestrator handed the checker its
exact id set, so it holds that set and compares the returned `criteria` table against it before doing
anything else. A table missing any id is a **malformed result**: the card does not advance, no gate is
applied, the doc is not persisted, and the checker is re-dispatched with the omitted ids named. A
`verdict: pass` over an empty or partial table is not a pass — it is a checker that did not check, and
it is caught. This is the mirror of the location rule: the location rule stops a checker *inventing*
findings; the completeness valve stops it *skimming*. A skim is the more dangerous of the two, because
a `pass` that checked nothing manufactures confidence. And it costs the producer nothing — an
incomplete check is the checker's failure, not a defect in the work, so it never spends the producer's
rework budget.

**Evidence over adjectives (why agreement must be earned).** A `pass` with thin evidence is worse than
no check at all, because it manufactures confidence where there was none. Each passing criterion's
evidence must state what was actually verified — not "looks fine". `/retro` reads these to tell
diligence from a skim.

## `templates/checks/split.md` — why `SPL-NO-LOSS` is the criterion that matters most

A splitter that silently drops code ships a broken card, and the defect is invisible to every slice's
own review — each slice looks complete on its own terms, so nothing downstream of the split would ever
catch it. `SPL-NO-LOSS` is also the guarantee that makes it safe for the lens panel to have reviewed
the whole diff *before* the split happened: if the union of the slices is exactly the change set the
panel approved, the slices are the code it already reviewed. `pr-splitter` is therefore a
**redistribution, not a rewrite** — never a second chance to change the code unreviewed. That is why
the check is set-equality in *both* directions (a deletion no slice performs is lost work exactly as
much as a dropped file), and why it is the one criterion a split check may never omit.

## `templates/checks/deliver.md` — why a `DLV-SIZE` breach is advisory, not blocking

The code is written and the PR is open. Re-dispatching `card-deliverer` cannot un-write it, so a
blocking verdict would burn rework budget against a remedy that does not exist at this phase. That is
why the breach is `advisory` — but deliberately not a shrug: the checker must propose a concrete split
in the finding's `remedy` (which commits or file groups become which smaller PRs, in what order), which
the orchestrator surfaces prominently for the driver, who decides whether to land the PR or split it.

**Why the card's own phase docs are excluded from the count.** The delivered diff also carries
`implement.md`, `test.md`, `review.md`, `pr-body.md` and `feedback.md` under the board dir. The budget
measures *the change a human must review, not the paperwork describing it*, and `estimated_lines` — the
number `actual_lines` is reported against — estimated code + tests only. Counting the docs inflates
every card against its own estimate and can breach `size_limit` on documentation volume alone, so they
are excluded even if a local `size_exclude` forgets to.

## `templates/AGENT-PROTOCOL.md` — why a design-phase agent records ADR proposals in its phase doc

Design-phase ADRs are written only once the design *check* passes, because the `adr` skill reserves a
number the moment it writes, and an ADR the checker rejects would burn one on a decision that gets
reworked. So the orchestrator holds proposed ADRs unwritten across the checker's whole dispatch — and a
pump can end inside that hold, at which point the only surviving copy of anything is what was persisted
to disk. A result block is not persisted; a `phase_doc` is. That is why a design-phase agent must write
each proposal out in full under a `## Proposed ADRs` section (title, context, decision, consequences,
any `supersedes`) **and** return it in `proposed_adrs`: the section is the durable copy the checker
verdicts and the orchestrator routes from, not a replacement for the field. Nothing load-bearing may
live only in a result block that the next pump will never see.
