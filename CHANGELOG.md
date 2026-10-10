# Changelog

## [Unreleased]

### Breaking

- `perform_now` on a terminated job no longer raises `SolidTerminator::JobTerminated`. `Terminable` now handles it with `rescue_from`, so the job returns normally and SolidQueue marks it finished.
- Removed `SolidTerminator::ClaimedExecutionPatch`. SolidTerminator no longer patches SolidQueue internals.

### Fixed

- `NameError: undefined local variable or method 'unblock_next_job'` raised after every job on solid_queue >= 1.5.0.

## [0.1.0] - 2026-06-06

- Initial release
