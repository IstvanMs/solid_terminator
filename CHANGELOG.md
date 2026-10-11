# Changelog

## [Unreleased]

### Upgrading

Run `bin/rails generate solid_terminator:update` and migrate. This adds the `arguments` column to `solid_queue_terminated_executions`.

### Breaking

- Requires a new migration that adds `arguments` to `solid_queue_terminated_executions` (see Upgrading). Until it runs, terminated executions are not recorded.
- `perform_now` on a terminated job no longer raises `SolidTerminator::JobTerminated`. `Terminable` now handles it with `rescue_from`, so the job returns normally and SolidQueue marks it finished.
- Removed `SolidTerminator::ClaimedExecutionPatch`. SolidTerminator no longer patches SolidQueue internals.

### Added

- `bin/rails generate solid_terminator:update` copies only the migrations the app is missing, without touching the initializer.

### Changed

- Depends on `activejob`, `activerecord` and `railties` instead of the whole `rails` gem.

### Fixed

- `NameError: undefined local variable or method 'unblock_next_job'` raised after every job on solid_queue >= 1.5.0.
- `SolidQueue::TerminatedExecution#retry` failed once SolidQueue cleared the finished job (immediately with `preserve_finished_jobs = false`, otherwise after `clear_finished_jobs_after`). The job's arguments are now stored on the terminated execution.
- `SolidQueue::TerminatedExecution#retry` raised `NoMethodError: undefined method '[]' for nil` on executions recorded before 0.2.0 whose job was already cleared. It now raises `SolidQueue::TerminatedExecution::NotRetryable` with an explanation.
- A termination could hit the wrong job: if the targeted job finished just as the monitor signalled it, `JobTerminated` could land in the next job on the same worker thread, or interrupt cleanup and leave a stale registry entry that kept signalling that thread. The monitor now raises under the registry lock, and `Terminable` only accepts the signal while the job's own code runs.

## [0.1.0] - 2026-06-06

- Initial release
