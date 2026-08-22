# 008 — Test scaffolding + lint/format tooling

## Goal
Zero test files exist anywhere in this repo (`find . -iname "*test*"` across the whole codebase
returns nothing — no `tests.py`, no `tests/` package, no `conftest.py`, and no CI workflow under
`.github/workflows/` either). No lint/format config exists either (no `.flake8`, `pyproject.toml`,
`ruff.toml`, `.pre-commit-config.yaml`, black/isort config). This is foundational tooling debt that
makes every other task in this list riskier to land safely — pick it up early, independent of the
feature work above.

## Part 1 — testing
- Decide `pytest` + `pytest-django` vs. plain `manage.py test` / `unittest` — either is reasonable for
  a Django/DRF project this size; `pytest-django` is the more common modern choice and plays well with
  DRF's `APIClient`, but match whatever the human prefers if they have an opinion.
- Add real coverage for the parts of the codebase that are both (a) already fully implemented and
  (b) currently completely unverified by any automated check:
  - `accounts/authentication.py`'s `SupabaseJWTAuthentication` — valid token, expired token, missing
    `sub` claim, missing header, malformed bearer.
  - `accounts/auth_views.py`'s four `/auth/*` views — at minimum, mock the Supabase GoTrue HTTP calls
    (`accounts/supabase_auth.py`) and verify each view's success/error-mapping paths.
  - `rpa/views.py`'s HMAC signature verification (`_verify_uipath_signature`) — valid signature,
    invalid signature, missing header, and the fail-open-when-secret-unset behavior (worth a test
    specifically because that behavior is a deliberate but risky tradeoff — a test documents and
    guards it, doesn't just leave it as an undocumented surprise).
  - `pdf_extraction/tasks.py`'s retry/backoff logic — this is exactly the kind of orchestration logic
    that's easy to silently break while implementing backend task 002; a test here is the highest-value
    thing to add before that task starts.
- As each subsequent backend task (003–007) lands new views/models, add tests alongside — this task
  is about getting the scaffolding + first real tests in place, not about hitting 100% coverage
  single-handedly.

## Part 2 — lint/format
- Add a `pyproject.toml` (or equivalent) configuring `ruff` (recommended — fast, combines lint +
  import-sort + a lot of what flake8/isort do separately) or `flake8`+`black`+`isort` if the human
  prefers the more traditional split. Either is fine; pick one and be consistent.
- Wire it into a documented command (update `korra-project/CLAUDE.md`'s "Commands" section once this
  lands — it currently says "No lint/format command exists yet").
- Optional but recommended: a `.pre-commit-config.yaml` so lint runs automatically, matching common
  Django project convention — not required if the human would rather keep this manual for now.

## Acceptance criteria
- `python manage.py test` (or `pytest`, whichever was chosen) runs and passes, with real assertions
  covering at least the four areas listed in Part 1.
- A lint command exists and running it against the current codebase either passes or the actual
  findings are fixed (don't add a linter and leave the whole codebase red on first run — fix what it
  finds or configure reasonable exceptions).
- `korra-project/CLAUDE.md`'s backend Commands section is updated to include the new test/lint
  commands once they exist (currently a placeholder note there points back to this task).

## Cross-repo dependency
None. Independent, and the earlier this lands the safer every other backend task in this list becomes.
