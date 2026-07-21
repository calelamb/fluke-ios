# Contributing

Fluke iOS is part of the [Fluke](https://github.com/calelamb/fluke) project, a
single-author personal project, and is **not accepting outside contributions**.
Pull requests and feature requests are not being reviewed or merged. The source
is public so people can read it and learn from it — not because help is being
solicited.

The one message that's always welcome: if you maintain an orca catalog, took a
photograph the project uses or wants to use, or spot a factual error about a
whale, reach the maintainer through the contact details on the live site.

## Code conventions (for reference, not a contribution guide)

The codebase follows strict test-driven development and a layered package
architecture. For anyone reading along:

- **Three packages, one direction of dependency.** `FlukeKit` (domain, no SwiftUI)
  → `FlukeUI` (design system, SwiftUI-only) → `FlukeFeatures` (feature modules).
  Nothing depends upward.
- **Tests first.** Every behavior change lands with a failing test, then the
  minimal code to pass, then a refactor pass.
- **Deterministic API fixtures.** `FlukeKit` decodes exact copies of the API's
  released contract fixtures, so a backend shape change fails in the client test
  suite before release. Don't hand-edit the copied JSON — update the API contract
  and regenerate.
- **Conventional commits.** `feat(scope):` / `fix(scope):` / `test(scope):`.
- **Fail closed.** Missing or malformed configuration disables a feature rather
  than shipping a broken or insecure one.

Full testing strategy is in [`testing.md`](testing.md); the package boundary
rules are in [`architecture.md`](architecture.md).
