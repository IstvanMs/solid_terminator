# SolidTerminator

*Hasta la vista, ActiveJob.*

Terminate a specific in-progress [SolidQueue](https://github.com/rails/solid_queue) job without stopping the worker process or affecting any other running jobs.

SolidQueue has no native per-job termination. Sending `TERM`/`QUIT` to a worker kills every job running on it. SolidTerminator fills that gap by raising a custom exception on exactly the thread running the target job.

## How it works

1. **Web server** — `SolidTerminator.terminate!(active_job_id)` inserts a row into `solid_queue_terminations`.
2. **Worker** — one monitor thread per worker process polls the table every 5 seconds (configurable). When it finds a row matching a locally-running job, it raises `SolidTerminator::JobTerminated` on that job's thread via `Thread#raise`.
3. **Job** — jobs that include `SolidTerminator::Terminable` rescue the exception, write a `TerminatedExecution` audit record, and stop cleanly.

The monitor skips the DB query entirely when no jobs are running — zero overhead at idle.

If the job catches the exception internally and keeps running, the termination row stays in the table and the monitor raises again on the next poll. Termination keeps retrying until the job actually stops.

## Requirements

- Ruby >= 3.1
- Rails >= 7.1
- SolidQueue >= 1.0

## Installation

Add to your `Gemfile`:

```ruby
gem "solid_terminator"
```

Run the install generator:

```bash
bin/rails generate solid_terminator:install
```

This copies two migrations and an initializer. Then run migrations.

**Single-database apps** (SolidQueue shares the main database):

```bash
bin/rails db:migrate
```

**Multi-database apps** (SolidQueue uses a dedicated database, typically keyed `queue` in `database.yml`):

```bash
bin/rails db:migrate:queue
```

> If your queue database key is not `queue`, pass `--database=<key>` to the generator:
> ```bash
> bin/rails generate solid_terminator:install --database=jobs
> ```

The generator creates two tables:

| Table | Purpose |
|---|---|
| `solid_queue_terminations` | Termination signal — almost always empty |
| `solid_queue_terminated_executions` | Audit trail of every terminated job |

## Usage

### Make a job terminable

Include `SolidTerminator::Terminable` in any job you want to be able to terminate:

```ruby
class MyJob < ApplicationJob
  include SolidTerminator::Terminable

  def perform
    loop do
      do_some_work
    end
  end
end
```

The concern registers the job's thread when execution starts and deregisters it when execution ends — whether the job succeeds, fails, or is terminated.

### Graceful cleanup on termination

`JobTerminated` propagates through your job's `perform` like any other exception. Use `ensure` for cleanup that must always run, and `rescue` if you need to react to termination specifically:

```ruby
class MyJob < ApplicationJob
  include SolidTerminator::Terminable

  def perform
    acquire_lock
    do_long_work
  rescue SolidTerminator::JobTerminated
    release_lock      # clean up before the job stops
    raise             # always re-raise so SolidTerminator can finish
  ensure
    close_connections # runs on success, failure, and termination
  end
end
```

> **Important:** Always re-raise `JobTerminated` after your cleanup. If you swallow it, the termination row stays in the database and the monitor will raise again on the next poll until the job stops.

### Request termination

From a controller, background job, console, or anywhere in your app:

```ruby
SolidTerminator.terminate!(active_job_id)
```

The job's thread receives `SolidTerminator::JobTerminated` within the next polling interval (default 5 seconds) and stops cleanly. Calling `terminate!` twice for the same job is safe — the duplicate is silently ignored.

**From a controller:**

```ruby
class JobsController < ApplicationController
  def destroy
    SolidTerminator.terminate!(params[:active_job_id])
    head :accepted
  end
end
```

**From the Rails console:**

```ruby
SolidTerminator.terminate!("9a7b3c2d-1234-5678-abcd-ef0123456789")
```

### Find the active_job_id

`active_job_id` is the UUID assigned by ActiveJob. Capture it at enqueue time:

```ruby
job = MyJob.perform_later(args)
job.job_id  # => "9a7b3c2d-..."
```

Find currently running jobs via SolidQueue's claimed executions:

```ruby
SolidQueue::ClaimedExecution
  .joins(:job)
  .where(solid_queue_jobs: { class_name: 'MyJob' })
  .pluck('solid_queue_jobs.active_job_id')
```

Or find any enqueued/running job by class:

```ruby
SolidQueue::Job.where(class_name: 'MyJob').pluck(:active_job_id)
```

## Terminated jobs

When a job is terminated, SolidTerminator writes a `SolidQueue::TerminatedExecution` record so you have a queryable audit trail.

> **Note:** SolidQueue has no "terminated" state, so it records a terminated job as **finished**, the same as a job that succeeded. Mission Control and `SolidQueue::Job.finished` include terminated jobs. Use `SolidQueue::TerminatedExecution` to tell them apart.

### Query

```ruby
# All terminated jobs, newest first
SolidQueue::TerminatedExecution.ordered

# Filter by queue
SolidQueue::TerminatedExecution.where(queue_name: 'critical')
```

Each record exposes: `job_id`, `queue_name`, `priority`, `terminated_at`.

### Retry a terminated job

Re-enqueue the original job with its original arguments:

```ruby
SolidQueue::TerminatedExecution.find_by(job_id: sq_job_id).retry
```

This destroys the `TerminatedExecution` record and enqueues a new job in a single transaction.

## Configuration

The generator creates `config/initializers/solid_terminator.rb` with all available options:

```ruby
SolidTerminator.configure do |config|
  # How often the monitor thread polls for termination requests (seconds).
  # config.polling_interval = 5  # default: 5

  # Route logs to Rails.logger instead of a dedicated file.
  # config.logger = Rails.logger

  # Log file path. Ignored when config.logger is set.
  # config.log_file = Rails.root.join("log", "solid_terminator.log")  # default

  # Log verbosity. Default: Logger::INFO.
  # Logger::DEBUG adds per-poll trace lines; Logger::WARN suppresses routine messages.
  # config.log_level = Logger::INFO
end
```

## Deployment topologies

Works across all SolidQueue topologies without any topology-specific configuration:

| Topology | Behaviour |
|---|---|
| Puma plugin (in-process) | Monitor starts with the worker thread pool |
| Separate `bin/jobs` process | One monitor per `bin/jobs` instance |
| Multiple worker processes on one host | One monitor per process; registry is process-local |
| Multiple hosts | Works automatically — each host's workers manage their own jobs |

The thread registry and `Thread#raise` always operate within the same OS process, so no cross-host signalling is needed. A termination row created on any host is picked up by whichever worker is running the job, because each monitor only queries for jobs in its own process-local registry.

## Design decisions

**Why a separate table instead of Redis or PostgreSQL LISTEN/NOTIFY?**
Works with PostgreSQL, MySQL, and SQLite out of the box — no extra infrastructure required. The table is almost always empty, so polling is essentially free.

**Why `Thread#raise` instead of process signals?**
Workers run a thread pool. A signal would interrupt every thread in the process; `Thread#raise` targets exactly the right one without disturbing other jobs.

**Why does `JobTerminated` inherit from `Exception` instead of `StandardError`?**
`rescue => e` only catches `StandardError`. Inheriting from `Exception` means the termination signal propagates through typical job error-handling code without being accidentally swallowed. Jobs that do have a `rescue Exception` handler will simply receive the exception again on the next poll until they stop.

**Why inherit from `SolidQueue::Record`?**
Ensures both tables live in the same database as the rest of SolidQueue, including multi-database setups that use `connects_to`.

## Roadmap

Planned improvements — no particular order:

**Signaling adapters**
- Redis pub/sub adapter — lower latency for stacks that already have Redis
- PostgreSQL `LISTEN/NOTIFY` adapter — zero extra infra for PG-only apps
- Pluggable adapter interface so custom adapters can be dropped in

**Termination control**
- Timeout-based auto-termination — automatically terminate a job that exceeds a configured runtime
- Grace period — wait N seconds after signaling before re-raising, allowing the job to reach a natural checkpoint
- Bulk termination — `SolidTerminator.terminate_all!(class_name:)` or by queue name

**Observability**
- ActiveSupport notifications (`solid_terminator.terminated`, `solid_terminator.monitor_error`) for APM integration and custom hooks
- `TerminatedExecution` retention policy and auto-cleanup of old records
- Termination status query — `SolidTerminator.termination_pending?(active_job_id)`

## Development

```bash
bundle install
bundle exec rspec          # run tests
bundle exec rubocop        # lint
bundle exec rubocop -A     # lint with auto-fix
```

## License

MIT
