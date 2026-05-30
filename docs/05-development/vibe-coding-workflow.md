# Vibe Coding Workflow (Claude Code Edition)

How to actually use **Claude Code** to build FixCare end-to-end — including brainstorming, planning, development, debugging, and testing — all from one tool.

---

## The Mindset Shift

**Vibe coding ≠ Letting AI build whatever it wants.**

It's:
- **You:** Architect, decision-maker, reviewer
- **Claude Code:** Very fast senior developer with agentic capabilities
- **Together:** 3-5x productivity over either alone

If you treat Claude Code as autopilot, you get garbage.
If you treat Claude Code as a collaborator with context, plugins, and disciplined methodology, you get gold.

---

## Why Claude Code (Not Cursor / Copilot)

For this project specifically:

| Capability | Claude Code | Cursor | Copilot |
|---|---|---|---|
| Multi-file agentic edits | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Long-running autonomous tasks | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐ |
| Plugin/skill ecosystem | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| Subagent orchestration | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐ |
| Terminal-native workflow | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| Brainstorming + dev unified | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐ |
| Cost predictability | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |

**Claude Code is the right pick** because:
- It does brainstorming, planning, coding, debugging, reviewing in one tool
- Agentic abilities (running tests, reading multi-file code, executing tools) far exceed Cursor
- Plugin ecosystem (Superpowers, etc.) adds proven workflows
- Terminal-native fits the Node/Fastify/Docker workflow naturally

---

## Setup

### Install Claude Code

```bash
# Requires Node.js 18+
npm install -g @anthropic-ai/claude-code

# Launch in your project directory
cd ~/projects/fixcare
claude
```

For latest install instructions, see https://docs.claude.com/en/docs/claude-code/overview

### Subscription Decision

- **Claude Pro (₹1,800/mo):** Sufficient for most solo dev work, hits limits on heavy days
- **Claude Max 5x or 20x:** Worth it once you're coding 4+ hours daily; 20x is rarely needed solo

Start with Pro. Upgrade if you hit message limits regularly.

---

## Plugin Stack to Install (Day 1)

These are non-negotiable for production-quality solo development.

### 1. Superpowers (Core Methodology)

**The big one.** Adds brainstorming, TDD, systematic debugging, planning, subagent orchestration as automatic workflows.

```bash
# Inside Claude Code session
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
```

OR via official marketplace:
```bash
/plugin install superpowers@claude-plugins-official
```

### What Superpowers Gives You

| Phase | Skill | What It Does |
|---|---|---|
| Idea | `brainstorming` | Refines rough ideas via Socratic questioning, presents design in bite-sized chunks for approval |
| Branching | `using-git-worktrees` | Creates isolated workspace per feature/task |
| Planning | `writing-plans` | Breaks work into 2-5 min tasks with exact paths and code |
| Execution | `subagent-driven-development` | Dispatches fresh subagents per task with two-stage review |
| Testing | `test-driven-development` | Enforces RED-GREEN-REFACTOR cycle |
| Debugging | `systematic-debugging` | 4-phase root cause analysis instead of guessing |
| Review | `requesting-code-review` | Pre-review checklist before merging |
| Verification | `verification-before-completion` | "Is it actually fixed?" gate before claiming done |
| Closing | `finishing-a-development-branch` | Merge/PR/discard decision workflow |

**Skills trigger automatically based on context.** You don't have to invoke them manually — Claude detects the situation and applies the right methodology.

### 2. Code Review Plugin (Anthropic Official)

Parallel multi-agent code review with confidence scoring (only issues scoring 80+ surface).

```bash
/plugin install code-review@claude-plugins-official
```

Critical for solo dev — you have no human reviewer, so multi-agent review fills that gap.

### 3. Language Server Plugins

Real-time type checking inside Claude Code.

```bash
# For backend (Node + TypeScript)
/plugin install typescript-lsp@claude-plugins-official

# Useful for catching type errors before runtime
```

### 4. PostgreSQL MCP Server

Lets Claude Code query your database directly during development.

Setup (one-time):
```bash
# Add to ~/.claude/mcp.json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost/fixcare_dev"]
    }
  }
}
```

Why this matters: Claude can inspect schema, run test queries, validate migrations without you copy-pasting.

### 5. GitHub MCP

Manages PRs, issues, repo state from Claude Code.

```bash
/plugin install github@claude-plugins-official
```

### 6. Playwright MCP (For Future E2E)

Useful when you start testing customer/technician app flows end-to-end. Install later, not Day 1.

### Optional Plugins to Consider Later

| Plugin | When To Add |
|---|---|
| `claude-mem` | When sessions become long-running and context loss hurts |
| `local-review` | If single agent code review feels insufficient |
| `plannotator` | If `writing-plans` output needs more structure |
| `commit-commands` | After ~50 commits, when commit hygiene matters |
| `security-guidance` | Before going live with payment flows |

**Don't install all 20+ plugins at once.** Plugins consume context. Start with Superpowers + code-review + DB MCP. Add more as needs emerge.

---

## The Superpowers Workflow (Adopt This Wholesale)

Superpowers enforces a specific lifecycle. Follow it. It works.

### Phase 1: Brainstorming
**Trigger:** Any time you start a new feature.

You describe a rough idea. Claude Code (via `brainstorming` skill) doesn't immediately code — it asks clarifying questions, explores alternatives, and produces a design doc you approve in chunks.

**Example:**
> "I want to build the booking flow."

Claude asks:
- What states does a booking go through?
- Who can transition between states?
- What validation at each transition?
- How is dispatch triggered?
- What happens on failures at each step?

You answer one at a time. Design document emerges. Saved to `docs/designs/booking-flow.md`.

### Phase 2: Worktree Creation
After design approval, Claude creates a git worktree for this feature on a fresh branch, ensuring clean baseline before any code.

### Phase 3: Planning
Claude (via `writing-plans`) breaks the design into tiny tasks (each 2-5 min). Each task has:
- Exact file paths
- Complete code
- Verification step (test that proves it works)

You review the plan before execution.

### Phase 4: Subagent Execution
Claude dispatches a fresh subagent per task. Each subagent:
1. Completes the task
2. Gets reviewed by another agent (spec compliance)
3. Gets reviewed again (code quality)
4. Only then moves to next task

You can leave it autonomous for 1-3 hours. Comes back with completed, reviewed work.

### Phase 5: Test-Driven Development
For any code, Claude follows strict RED-GREEN-REFACTOR:
1. Write failing test (RED)
2. Watch it fail
3. Write minimal code to pass (GREEN)
4. Watch it pass
5. Refactor if needed
6. Commit

Code written before tests gets deleted. No exceptions.

### Phase 6: Code Review
Multi-agent review (via code-review plugin) before merge. Critical issues block, minor issues noted.

### Phase 7: Branch Finishing
Merge, PR, keep, or discard — Claude walks through options. Worktree cleaned up.

---

## Living Documents (Maintained by You + Claude Code)

Claude Code reads project files automatically. Keep these maintained — they're the context that makes vibe coding work.

### Critical Files

#### `CLAUDE.md` (Project Root)
Claude Code automatically reads this on session start. Treat as the project's master prompt.

Contents:
- Project overview (1-2 paragraphs from `vision-and-scope.md`)
- Tech stack summary
- Conventions to enforce
- Reference to other docs

Example structure:
```markdown
# FixCare — Project Context

## What This Is
[2-paragraph summary]

## Stack
- Backend: Node.js 22 + Fastify 5 + Prisma 6 + Postgres 16 + Redis 7
- Mobile: Flutter 3.x (Android only V1)
- Hosting: Hetzner + Docker Compose
- Auth: Phone OTP + JWT
- Payments: Razorpay

## Conventions
- All routes use Zod for validation
- All DB writes go through service layer, never directly in routes
- All async functions have explicit error handling
- All financial operations log to audit table
- No `any` types; use `unknown` if absolutely needed
- Prisma for all queries; raw SQL only for PostGIS

## Reference Docs
- Architecture: docs/04-architecture/system-architecture.md
- API design: docs/04-architecture/module-structure.md
- Build sequence: docs/05-development/build-sequence.md
- Conventions detail: docs/05-development/coding-conventions.md
```

#### `PROJECT.md` (Optional Companion)
Deeper architectural details. Reference from CLAUDE.md.

#### `CHANGELOG.md`
What changed in last 30 days. Helps Claude avoid regenerating broken patterns.

#### `docs/designs/`
Brainstorming outputs from Superpowers (auto-generated, you review).

#### `docs/plans/`
Plan documents from `writing-plans` (auto-generated).

---

## Session Start Ritual

Every coding session:

1. `cd ~/projects/fixcare` and `claude` to launch
2. Claude auto-reads `CLAUDE.md`
3. Say what you want to do today:
   > "Today I want to build the OTP verification endpoint."
4. **Let Superpowers trigger naturally.** If it's a new feature, `brainstorming` activates. If continuing existing work, `writing-plans` or `executing-plans` runs.
5. **Don't skip the brainstorming phase**, even if you "already know what you want." The questions reveal edge cases.

---

## The Three Modes of Working with Claude Code

### Mode 1: Brainstorming / Architecture Discussion
**When:** Starting a feature, debating design, exploring options.

You're not coding. You're thinking with Claude.

> "Should the dispatch algorithm prioritize rating or proximity?
> Walk me through tradeoffs."

Claude explores, asks questions, recommends. Output: a decision documented in `docs/decisions/`.

### Mode 2: Focused Implementation
**When:** Plan is clear, just need to build.

> "Implement Phase 3 of the booking-flow plan."

Claude executes via subagents, you review chunks, ship.

### Mode 3: Debugging / Investigation
**When:** Something's broken.

> "The OTP verification returns 401 even with correct OTP. Investigate."

Claude triggers `systematic-debugging` — 4-phase root cause process, not random guessing.

---

## What Claude Code Is Genuinely Good At

Use heavily for:

### Backend Development
- Prisma schema design + iteration
- Fastify route handlers (with clear plan)
- Zod schemas
- Service layer functions
- BullMQ worker implementations
- Background job processors
- Database migrations
- Test cases (with TDD discipline)
- API documentation generation
- Third-party API wrappers (Razorpay, MSG91, Setu, etc.)

### Frontend (Flutter)
- Widget composition
- Riverpod providers and state management
- API client code (with retrofit/dio)
- Form layouts and validation
- Error/loading states
- Localization setup

### DevOps
- Docker Compose configuration
- Dockerfile optimization
- Caddyfile setup
- GitHub Actions CI/CD
- Database backup scripts
- Deployment scripts

### Investigation
- Reading unfamiliar code
- Tracing bugs through call chains
- Understanding error patterns
- Performance analysis

---

## What Claude Code Needs Heavy Supervision On

These are areas where Superpowers + your review matter most:

### Architecture Decisions
Claude implements, you decide. Use `brainstorming` for these:
- Cross-module communication patterns
- Database schema relationships
- API contract design
- State machine design
- Service boundaries

### Security
- Auth flow logic (verify manually every step)
- Token handling (subtle mistakes are catastrophic)
- Permission checks (Claude sometimes forgets)
- Input validation completeness
- Secrets handling (Claude occasionally hardcodes test values)

### Financial Logic
- Ledger calculations (audit every line)
- Settlement amount math
- Refund logic
- Tax/GST calculations
- Currency rounding rules

### Business Edge Cases
- Technician offline mid-job
- Customer pays then cancels
- Payment partial failure
- KYC vendor down
- Race conditions (two technicians accept same job)

For all of these, Superpowers' `verification-before-completion` skill is the safety net. Use it.

---

## Daily Workflow

### Morning: 20-Min Setup
1. Pull latest from GitHub
2. `claude` to start session
3. Read `CHANGELOG.md` to refresh
4. State today's goal explicitly
5. Let brainstorming/planning skills activate

### Mid-Morning: Deep Work Block (2-3 hours)
- One feature, focused
- Let subagents work autonomously where possible
- Review checkpoints between phases
- Commit small, commit often

### Lunch + Break (1 hour) — Non-negotiable

### Afternoon: Review + Polish (2-3 hours)
- Read morning's code
- Run multi-agent code review (`code-review` plugin)
- Address critical issues
- Run tests
- Update docs

### End-of-Day: 15-Min Wrap
- Update `CHANGELOG.md` with what changed
- Push final commits
- Note tomorrow's starting task
- Close session

**Hard limit: 6 hours of coding daily.** Beyond that, quality drops and bugs multiply.

---

## Using Subagents Effectively

Superpowers' `subagent-driven-development` skill is the biggest productivity unlock. Understanding it:

### What Subagents Are
Claude Code can spawn fresh sub-conversations (subagents) with isolated context for specific tasks. Each subagent:
- Starts clean (no accumulated context noise)
- Focuses on one task
- Reports back when done

### Why This Matters
- Main conversation stays clean
- Each task gets full attention
- Two-stage review (spec compliance + code quality) catches more issues
- You can run multiple in parallel (use `dispatching-parallel-agents` skill)

### When to Run Parallel Subagents
Examples:
- Implement 3 unrelated API endpoints simultaneously
- Generate tests for 5 modules in parallel
- Refactor multiple files with the same pattern

**Don't parallelize when tasks share files or depend on each other.** Race conditions kill productivity.

---

## Code Review with Multi-Agent Plugin

For every meaningful change before merge:

```bash
# Inside Claude Code
/code-review
```

What happens:
- 5 agents review in parallel
- Each focused on different aspect:
  - CLAUDE.md compliance
  - Bug detection in diff
  - Git blame historical context
  - PR history patterns
  - Code comment quality
- Each issue gets confidence score (0-100)
- Only issues scoring 80+ surface to you

This is your **substitute for a human reviewer.** Use it religiously.

---

## Debugging with Systematic Discipline

When something breaks, do NOT just ask Claude to "fix it." Superpowers' `systematic-debugging` activates a 4-phase process:

1. **Reproduce** — Can we reliably trigger the bug?
2. **Isolate** — What's the smallest case that reproduces?
3. **Root cause** — Why does this happen? (not just "where")
4. **Verify fix** — Does the fix actually address the root cause, or just mask symptoms?

This prevents the rabbit hole of "AI makes random changes until error message disappears."

---

## The Save-Often Pattern

**Commit small, commit often.**

- Working code → commit
- Refactor → commit
- New feature → commit
- Bug fix → commit
- Tests added → commit

Why:
- Easy to revert if subagent breaks something
- Git history tells the story
- Mental progress feels real
- Worktrees stay clean

Superpowers handles most commit hygiene automatically when working in worktrees.

---

## Cost Management

Claude Code can burn through subscription limits if uncared for.

### Cost-Saving Patterns
- **Use CLAUDE.md** instead of repeatedly explaining context
- **Use subagents** for big tasks (they exit cleanly without bloating main context)
- **End sessions** when work is done (don't keep dead conversations open)
- **Compact context** when sessions get long (`/compact` command)
- **Use plan mode** to think before doing expensive operations

### Cost-Wasting Patterns to Avoid
- Asking Claude to re-read the same file 10 times
- Long debugging sessions that lose focus
- Generating code without a plan
- Letting Claude search the codebase when you know exact path
- Forgetting to commit and re-asking same generation

---

## When AI Gets Stuck

Signs Superpowers should help (not always):
- Same error after 3 attempts
- Solutions getting weirder
- Claude contradicting itself
- You're losing track of what changed

### What To Do
1. **Stop iterating.** Don't let it spiral.
2. **Invoke `systematic-debugging`** explicitly if not already active
3. **Step away** (walk, water, snack — 10 min)
4. **Come back fresh**, often the issue clarifies
5. **Sometimes it's environmental** (env var, port conflict, stale Docker image, etc.) — check those before assuming logic bug
6. **Once found, document** so it doesn't recur

**Don't let any AI lead you down a rabbit hole.** Your judgment is the safety net.

---

## Documenting Decisions in Real-Time

Use this folder structure (the **canonical** convention — `CLAUDE.md`'s
Documentation Map is the single source of truth; this mirrors it):

```
CLAUDE.md                      # repo ROOT — main context, auto-read by Claude Code
STATUS.md                      # repo ROOT — live phase/task/blockers
CHANGELOG.md                   # repo ROOT — last 30 days
docs/
├── adrs/                      # Architecture Decision Records (expensive-to-reverse)
│   ├── ADR-0001-monorepo.md
│   ├── ADR-0002-trunk-based-branching.md
│   └── ADR-0003-worker-to-technician.md
├── designs/                   # Brainstorming specs (Superpowers writes HERE)
│   └── YYYY-MM-DD-<feature>-design.md
├── plans/                     # Implementation plans (Superpowers)
│   └── YYYY-MM-DD-<feature>.md
├── decisions/                 # Smaller decisions
│   └── why-onesignal-over-fcm.md
└── progress/weekly-notes/     # Weekly retros (YYYY-MM-DD.md)
```

When you start a feature, Superpowers' brainstorming spec goes to `docs/designs/`
(**not** the plugin default `docs/superpowers/specs/` — redirect it). Implementation
plans go to `docs/plans/`. Quick decisions go to `docs/decisions/`. Major
architectural choices get ADRs. `CLAUDE.md`, `STATUS.md`, and `CHANGELOG.md` live
at the **repo root**, not under `docs/`.

---

## Anti-Patterns To Avoid

### ❌ Skipping Brainstorming
"I know what I want, just build it."
Result: You miss edge cases. Brainstorming surfaces them in 10 min vs days of bug-hunting.

### ❌ Disabling TDD When Inconvenient
Result: Untested code accumulates. Future bugs become harder to find.

### ❌ Accepting Code You Don't Understand
"It works, ship it" → 6 months later, can't debug it.
Fix: Read every line. If you can't explain it, ask Claude to explain, then rewrite simpler.

### ❌ Running Many Plugins Without Review
Plugins consume context. Audit your installed plugins quarterly.

### ❌ Letting Subagents Run For Hours Unsupervised
1-3 hours is fine. 6 hours is too much. Check in periodically.

### ❌ Forgetting to Commit During Subagent Runs
If subagent goes off the rails after 2 hours, you lose 2 hours. Subagents auto-commit when configured, but verify.

### ❌ Bypassing Code Review for "Quick Fixes"
Quick fixes are where most bugs hide. Always run `/code-review`.

---

## Sustainability Rules (Repeat From Build Sequence)

1. **Never code more than 6 hours/day.**
2. **Take Sundays off entirely.**
3. **Sleep 7+ hours.**
4. **Exercise daily** (20 min minimum).
5. **One social interaction daily.**
6. **Talk to other solo founders.**
7. **Celebrate small wins.**

Burnout kills projects. Pace yourself.

---

## When to Stop Coding and Think

Pause and use plain conversation (not coding session) when:
- About to make architectural decision
- About to add a new technology
- About to skip a security check "just for now"
- About to merge code you don't fully understand
- Frustrated for >1 hour

**Thinking is also work.** Sometimes the highest-ROI hour of the day is the one where you don't write code.

---

## The 80/20 of Vibe Coding with Claude Code

**80% of value comes from:**
- Clear `CLAUDE.md` (always present in repo root)
- Superpowers plugin enforcing discipline
- Test-driven development (RED-GREEN-REFACTOR)
- Multi-agent code review before merging
- Systematic debugging instead of guessing
- Small, frequent commits
- Daily 6-hour limit

**20% of value comes from:**
- Fancy plugins, shortcuts, hacks

Focus on the 80%. Don't get distracted by every new Claude Code plugin announced.

---

## Plugin Stack Recap

Install on Day 1:
1. **superpowers** — Methodology
2. **code-review** (Anthropic official) — Multi-agent review
3. **typescript-lsp** — Real-time type checking
4. **postgres MCP** — DB inspection
5. **github MCP** — Repo automation

Install when needed:
6. **playwright MCP** — E2E testing (Month 6+)
7. **security-guidance** — Before going live (Month 10+)
8. **commit-commands** — When commit hygiene needs polish

Skip unless specific need:
- claude-mem, local-review, plannotator, dev-browser, ralph-wiggum, shipyard

---

## References

- Superpowers: https://github.com/obra/superpowers
- Claude Code docs: https://docs.claude.com/en/docs/claude-code/overview
- Claude Code plugins marketplace: https://claude.com/plugins
- Anthropic official plugins: https://github.com/anthropics/claude-code-skills
