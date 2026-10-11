# SolidTerminator — Agent Instructions

## What Is This Gem

SolidTerminator adds per-job termination to [SolidQueue](https://github.com/rails/solid_queue).

SolidQueue has no native way to stop a specific in-progress job. Sending `TERM` or `QUIT` to a worker process kills **every** job running on it. SolidTerminator fills that gap: terminate one job, leave everything else running.

Works across all deployment topologies — single process, multi-worker, multi-host — with no external dependencies beyond a database already used by SolidQueue.

---

## How It Works

### Signal flow

```
Web request
  → SolidTerminator.terminate!(active_job_id)
  → INSERT into solid_queue_terminations

Monitor thread (per worker process, polls every N seconds)
  → SELECT from solid_queue_terminations WHERE active_job_id IN (running jobs)
  → finds match → looks up thread in ThreadRegistry
  → Thread#raise(SolidTerminator::JobTerminated)

Job thread
  → around_perform ensure: deregister from ThreadRegistry + DELETE termination row
  → rescue_from JobTerminated: record a TerminatedExecution, perform_now returns normally
  → SolidQueue marks the job finished
```

### Components

| Component | File | Role |
|-----------|------|------|
| `Terminable` concern | `lib/solid_terminator/terminable.rb` | `around_perform` registers/deregisters; `rescue_from` records termination |
| `ThreadRegistry` | `lib/solid_terminator/thread_registry.rb` | Process-local `active_job_id → Thread` map |
| `Monitor` | `lib/solid_terminator/monitor.rb` | Polling thread spawned per worker via `on_worker_start` |
| `Termination` | `lib/solid_terminator/termination.rb` | AR model for `solid_queue_terminations` table |
| `TerminatedExecution` | `lib/solid_terminator/terminated_execution.rb` | AR model recording termination history |
| `JobTerminated` | `lib/solid_terminator/job_terminated.rb` | Exception class raised on target thread |
| `Configuration` | `lib/solid_terminator/configuration.rb` | `polling_interval` and other settings |
| `Engine` | `lib/solid_terminator/engine.rb` | Rails engine — wires up hooks and migrations |
| Install generator | `lib/generators/solid_terminator/install_generator.rb` | `rails g solid_terminator:install` |

### Key design decisions

**Separate DB table (not Redis/PG NOTIFY)**
- Works with PostgreSQL, MySQL, and SQLite — no extra infrastructure
- Table is almost always empty; indexed query on empty table is essentially free
- Redis pub/sub or PG LISTEN/NOTIFY can be added as optional adapters later

**`Thread#raise` (not process signals)**
- Workers run thread pools — `SIGTERM` would kill all threads, not one
- `Thread#raise` targets a specific thread with no collateral damage
- Works in both threading and forking modes; `on_worker_start` fires per forked process

**Skip DB query when registry is empty**
- No jobs running → nothing to terminate → skip the query entirely
- Registry check is an in-memory hash size check — zero overhead at idle

**Monitor thread per worker (not watchdog process)**
- Watchdog would need cross-host signaling (impossible via OS signals)
- Monitor thread shares process memory with job threads — direct `Thread#raise` access

---

## Gem Interface

```ruby
# Include in any job
class MyJob < ApplicationJob
  include SolidTerminator::Terminable

  def perform
    # long-running work
  end
end

# Trigger termination (from a controller, admin UI, etc.)
SolidTerminator.terminate!(active_job_id)
```

## Configuration

```ruby
# config/initializers/solid_terminator.rb
SolidTerminator.configure do |config|
  config.polling_interval = 5  # seconds, default: 5
end
```

---

## Compatibility

Mirrors SolidQueue's own version requirements.

- **Ruby:** >= 3.1
- **Rails:** >= 7.1
- **SolidQueue:** >= 1.0
- **Databases:** PostgreSQL, MySQL, SQLite

### CI matrix

`.github/workflows/ci.yml` runs every row with `BUNDLE_GEMFILE=gemfiles/ci.gemfile`, which pins versions from env vars.

| Ruby | Rails | SolidQueue | Why |
|------|-------|------------|-----|
| 3.1  | 7.1   | 1.0.x      | Oldest supported |
| 3.2  | 7.2   | 1.4.x      | Last release before 1.5 changed how `ClaimedExecution` finalizes jobs |
| 3.3  | 8.0   | latest     | |
| 3.4  | 8.1   | latest     | |

---

## Agentic Coding Flow

Do not make changes without following this flow. No exceptions.

### Before writing any code

1. **State the problem.** What is broken or missing? Be specific. Reference the component and file.
2. **List alternatives.** At least two approaches. If only one exists, say why.
3. **Tradeoffs.** For each alternative: what it gains, what it costs.
4. **Decision.** Which approach and why. One sentence is enough if it is obvious.
5. **Scope.** Which files change and why each one is necessary.

Example:

```
Problem: polling_interval is hard-coded — no way to tune without forking the gem.

Alternatives:
  A) Add config option (chosen)
     + explicit, type-safe, Rails-idiomatic
     - one more public API surface
  B) ENV var
     + zero API surface
     - no type safety, surprising for a gem

Decision: A — consistent with Rails conventions, already have Configuration class.

Scope: lib/solid_terminator/configuration.rb (add attribute), spec/solid_terminator/configuration_spec.rb (new examples).
```

### Coding rules

- Introduce no abstraction beyond what the task requires. Three similar lines beats a premature helper.
- Add no error handling for scenarios that cannot happen. Trust internal invariants.
- Write no comments that explain what the code does. Only write a comment when the **why** is non-obvious: a hidden constraint, a workaround for a specific bug, a subtle invariant.
- Do not add features, flags, or backwards-compatibility shims unless the task requires them.
- Do not refactor surrounding code while fixing a bug. One change per commit.

### After writing code

Run the full validation checklist (see below). Do not report the task done until all three pass.

---

## Validation Checklist

Run all three after every change:

```bash
bundle exec rubocop                      # must report no offenses
bundle exec rspec                        # must report 0 failures
bundle exec rspec integration            # must report 0 failures
```

`integration/` runs against the real SolidQueue models in a minimal Rails app. It is a separate
suite because `spec/spec_helper.rb` defines fake SolidQueue models that clash with the real ones.
Any change to how a terminated job finishes in SolidQueue needs an integration example.

To reproduce a CI row locally:

```bash
BUNDLE_GEMFILE=gemfiles/ci.gemfile RAILS_VERSION='~> 8.1.0' SOLID_QUEUE_VERSION='>= 1.5' bundle install
```

If RuboCop reports offenses, fix them — do not disable cops unless the offense is a genuine false positive, and document why.

---

## Testing Flow

### Rules

- Every new method or behaviour change gets a new or updated spec in the same commit. Never leave a method untested.
- Run the full suite before marking any task complete.
- Unit tests must be fast. Tag slow or DB-dependent tests `:integration`.

### Running tests

```bash
# Full suite
bundle exec rspec

# Single file
bundle exec rspec spec/solid_terminator/monitor_spec.rb

# Single example by line number
bundle exec rspec spec/solid_terminator/monitor_spec.rb:42

# Tagged
bundle exec rspec --tag integration
```

### What to cover

| Area | Examples to write |
|------|------------------|
| `ThreadRegistry` | register, deregister, concurrent access, empty? check |
| `Monitor` | polls at interval, skips query when registry empty, raises on correct thread, retries if job swallows exception |
| `Terminable` | handles `JobTerminated` without raising, skips `after_perform`, deregisters in `ensure` even on other exceptions, does not swallow unrelated exceptions |
| `Termination` model | row created by `terminate!`, row deleted after signal handled |
| `TerminatedExecution` | record created on successful termination |
| Integration | full flow: `terminate!` call → job stops, row cleaned up |

---

## RSpec Patterns

### Structure

```ruby
RSpec.describe SolidTerminator::Monitor do
  subject(:monitor) { described_class.new(registry: registry, interval: 0.1) }

  let(:registry) { SolidTerminator::ThreadRegistry.new }

  context "when registry is empty" do
    it "skips the DB query" do
      expect(SolidTerminator::Termination).not_to receive(:where)
      monitor.check
    end
  end

  context "when a termination row matches a running job" do
    it "raises JobTerminated on the target thread" do
      # ...
    end
  end
end
```

### Rules

- Use `described_class` — never hardcode the class name in specs.
- Use `context` blocks for different states: `"when registry is empty"`, `"when the job swallows the exception"`.
- Describe behaviour, not implementation: `"terminates the job"` not `"calls Thread#raise"`.
- One assertion per example when possible. Split examples rather than stacking `expect` calls.
- Use `let` for setup. Avoid `before { @var = }`.
- Clean shared state in `around` blocks, not `after` (after does not run on failure):

```ruby
around do |example|
  SolidTerminator::ThreadRegistry.clear!
  example.run
ensure
  SolidTerminator::ThreadRegistry.clear!
end
```

### Improving existing specs

When reviewing a spec file, check for:

1. **Shared mutable state** — any `@ivar` or class-level mutation that leaks between examples. Fix with `let` + `around` cleanup.
2. **Over-mocking** — mocking internal classes hides real bugs. Prefer real objects; mock only at system boundaries (DB, external HTTP).
3. **Missing edge cases** — empty registry, concurrent terminations, job that rescues `StandardError` and keeps running, worker process that dies mid-termination.
4. **Ambiguous descriptions** — if you cannot tell what breaks when an example fails, rewrite the description.
5. **Slow unit tests** — anything sleeping real time in a unit test. Use `instance_double` or inject a fake clock/interval.

---

## Project Conventions

- Ruby style enforced by RuboCop. Config in `.rubocop.yml`.
- No monkey-patching. Integrate with SolidQueue and ActiveJob through public APIs and callbacks only.
- All public API is in `lib/solid_terminator.rb`. Internals live under `lib/solid_terminator/`.
- Migrations are templates in `lib/generators/solid_terminator/templates/` — not applied directly.
