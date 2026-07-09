# FitbitAir build fixes

This package includes a corrected GitHub Actions workflow and rewritten SwiftUI screens for the build errors seen in GitHub Actions.

Fixed:
- `HistoryView.swift`: removed malformed `gSpecifier` interpolation and split the view into smaller components.
- `CoachView.swift`: replaced invalid `.opacity(.2)` with `0.2` and simplified the view structure.
- `InsightsView.swift`: split the large expression into simpler SwiftUI views.
- `WorkoutView.swift`: corrected all weight formatting expressions and simplified the screen hierarchy.
- `.github/workflows/build-ipa.yml`: removed the conflicting build directory creation/clean behavior.

Upload the full contents over the repository, commit, then run `Build FitbitAir IPA` again.
