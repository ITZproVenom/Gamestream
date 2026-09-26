# Changelog

All notable changes to GameStream are documented here.

## 2026-09-26

### Latest Build

- **Build #588** completed successfully.
- Archive and IPA packaging completed successfully.
- Latest release candidate commit: `a75552d2ef098d194ad53658f5f82522728a19e9`.

### UI Redesign

- **Library** (`bad2224`)
  - Rebuilt the cloud library interface with a cleaner product-focused layout.
  - Reduced unnecessary glass effects and visual noise.
  - Grouped navigation and stream controls more clearly.
  - Refined Better xCloud controls and information presentation.
  - Improved sign-in, loading, error, and stream-exit surfaces.

- **Search** (`f217c55`, `a75552d`)
  - Rebuilt the search experience around a search-first layout.
  - Added compact recent/pinned content and ranked popular searches.
  - Added restrained genre navigation and favorites presentation.
  - Added responsive poster results and a cloud-search action.
  - Fixed SwiftUI list identity keys that were blocking the build.

- **Settings** (`09363b7`)
  - Rebuilt settings as a native iOS grouped control center.
  - Replaced oversized glass cards with structured material sections.
  - Reworked controls into native toggles and menus.
  - Organized appearance, GameHub, playback, streaming, controller, motion/sound, activity, and maintenance settings.

- **Navigation** (`4ae5687`)
  - Simplified the bottom navigation.
  - Removed the draggable Liquid Glass navigation slider.
  - Added a restrained three-tab floating navigation bar.
  - Preserved controller LB/RB navigation and accessibility selection state.

### Earlier UI Refinements

- **Game detail hero** (`783c83b`) made the detail hero responsive with a 16:9 aspect ratio.
- **Intro layout** (`027dd74`, `cfcf27d`) improved responsive sizing and action width handling.
- **Jump Back In** (`1cdb227`) prevented action compression.
- **Search grid** (`93cbaae`) improved responsive poster layout.
- **List posters** (`9702ee4`) improved poster presentation.
- **Continue Playing** (`6839f73`) restored the Continue Playing surface.
- **Empty states** (`bad6303`) improved empty-state presentation.
- **Settings safe area** (`da99e85`) kept settings content within safe areas.
- **Header compression** (`541a994`) refined compact header behavior.

### Build / Stability

- Corrected SwiftUI `ForEach` identity handling in SearchHubView.
- Kept the redesign changes isolated from the existing Xbox Cloud WebKit/auth flow.
- Preserved controller navigation and existing streaming functionality while rebuilding the surrounding UI.
