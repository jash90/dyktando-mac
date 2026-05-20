# Dyktando

Polish-focused on-device dictation app for macOS.

See `docs/superpowers/specs/2026-05-20-dyktando-design.md` for the design and `docs/superpowers/plans/2026-05-20-dyktando-implementation.md` for the implementation plan.

## Develop

```bash
# Generate Xcode project (idempotent, safe to re-run)
xcodegen generate

# Build via CLI
xcodebuild -project Dyktando.xcodeproj -scheme Dyktando -destination 'platform=macOS' build

# Or open in Xcode
open Dyktando.xcodeproj
```

Requires Xcode 26.5+ and macOS 14+. Install xcodegen with `brew install xcodegen` if not present.
