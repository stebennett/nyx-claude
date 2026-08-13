---
name: slice-check
description: "Check one slice verdict against SLC-* criteria. Derive own view from spec before reading slice.md. Vets verdict correctness, independent size estimate, child vertical slices, child ACs, no-loss, dependents rewire, acyclic DAG."
---

# slice-check

Check ONE slice verdict. Read `checks/_method.md` (the discipline, the return format, and the
size-estimate appendix) and obey it exactly.

Read, in order: `checks/_method.md` and `checks/slice.md` (absolute paths in your dispatch;
layer any `## Check criteria — slice` addendum on top), `PROTOCOL-ADDENDUM.md` if present. Then your inputs: `card.md`, `slice.md`, the slicer's `proposed_cards` /
`dependents_rewire` / `estimated_lines`, the card's dependents, the spec at `spec_path`, and
`MILESTONES.md`.

## Procedure

1. **Derive before you read** (per `_method.md`): form your own view — would you split this
   card, and how — before reading the slicer's rationale, then diff its answer against yours.
2. **Estimate the size yourself** — the highest-value thing you do. Size the card (right-sized)
   or each child (split) by `_method.md`'s appendix, then apply `SLC-SIZE`: your estimate over
   `size_limit` for any card is blocking (split it); a slicer estimate you cannot reconstruct
   from its own working is blocking even under the limit.
3. **Work the rest of `## slice`** in order. Build the `depends_on` graph by hand for
   `SLC-DAG`; for `SLC-REWIRE`, tick every dependent from your dispatch off against
   `dependents_rewire` — a missing one is a card orphaned by the split.
4. **Verdict every criterion** with evidence; findings only where you can cite a location in
   `slice.md` or the proposed card set.

## Return

- `checks: slice`, `phase: check`, `gate: none`. `verdict: pass` → the orchestrator applies the
  slice gate; `verdict: fail` → it re-dispatches `analyst` with your findings verbatim, up
  to the `slice` check budget, then parks the card.
- `phase_doc` is `slice-check.md`: `## Verdict`, `## Criteria` (the full table — id, verdict,
  evidence), `## Size estimate` (your per-file working, your total, the slicer's total, and
  whether it holds), `## Blocking findings`, `## Advisory findings`.
- `status: needs-input` only if you cannot check at all (the spec is unreadable, `slice.md`
  missing). A slice you disagree with is a `fail`, not a blocker.
- Add `knowledge` entries for recurring slicing traps (scope: repo).
