---
name: netcase-bbq
description: Grill the user on a plan, design, or proposal until every reversible decision has a defensible rationale and every irreversible one has explicit buy-in. Use when the user wants their thinking stress-tested, says "bbq me", "grill this idea", "pressure-test the plan", or is about to commit to a costly direction without explicit trade-off analysis.
---

# netcase-bbq

A structured Socratic interview that ends with a **written decision register** — not just shared understanding, but recorded choices with rationale and reversibility for each.

The name is literal: this is a barbecue. Heat applied methodically until the meat is done. No rushing, no skipping cuts.

## Three phases

Run these in order. Don't skip ahead even if the user gestures forward.

### 1. Warm-up — scope and stakes (3–5 questions)

Before any design questions, lock down:

- **Who is the actual user / customer?** Real names if possible, role + context otherwise.
- **What's the smallest version that would make them notice?** This defines done.
- **What's the budget** — money, time, and team attention? This defines what's tradable.
- **Is anything about this irreversible once shipped?** This defines blast radius.

If the user can't answer these, design questions are premature. Send them to do customer discovery or scoping first.

### 2. Main grill — decision tree, one branch at a time

Walk the design as a tree. For each decision node:

- Ask the question with **your recommended answer first**, then the alternatives.
- For each alternative, name the trade-off in one sentence (cost / risk / capability lost).
- Resolve the decision before opening the next branch. No depth-first wandering across unresolved nodes.
- If the user defers ("we can decide later"), record it as an **explicit deferred decision** with a trigger condition (when must this be revisited).
- If a question can be answered by reading the codebase, read it instead of asking.

Push back when answers are vague. "It depends" is not a decision — ask what it depends on.

### 3. Consolidation — write the decision register

Before ending the grill, produce a single artifact in the conversation:

```
## Decision Register

| # | Decision | Choice | Rationale | Reversibility |
|---|----------|--------|-----------|---------------|
| 1 | …        | …      | …         | reversible / hard / one-way |

## Deferred
- <decision>: revisit when <trigger condition>

## Risks
- <risk>: <mitigation or "accepted">
```

This is what the user takes away. The chat transcript is auxiliary.

## Rules of the grill

- **One question at a time.** Always.
- **Recommend first, then alternatives.** Never ask a naked question.
- **Fewest decisions, not most thorough audit.** If a question doesn't change behavior, skip it.
- **Irreversible decisions need explicit acknowledgement.** Get a "yes, I understand" before moving on.
- **When you don't know enough, say so.** Propose how to find out (read code, ask stakeholder, prototype). Don't guess.
- **Track NETCASE's defaults** — when in doubt, lean toward Schweizer pragmatism: smaller scope, real customer evidence, fewer dependencies, easier reversibility.

## When NOT to use

- The user has already made the decision and wants execution, not interrogation.
- All decisions are reversible and cheap to undo — skip the ceremony, just build.
- The conversation is exploratory ("what could we do about X") rather than commitment-bound. A brainstorming approach is more useful than a grill.
