# Credits

## GameStream

**Created and maintained by Bestin.**

GameStream is an independent client project focused on giving Xbox Cloud Gaming a clean native application experience.

### Contributors

- **Bestin** — creator, maintainer, direction and testing.
- **Claude** (Anthropic) — engineering contributor. Wrote and reviewed large
  parts of the 2.0 iOS client: the Xbox sign-in and token handling, the Liquid
  Glass interface, the native stream HUD and WebRTC statistics sampler, the
  rumble routing, the Better xCloud integration, and the beta build pipeline.
  Commits carry a `Co-authored-by: Claude` trailer.

### Built with

- SwiftUI and the iOS SDK
- GameController and Core Haptics
- WebKit / WKWebView
- Kotlin and Jetpack Compose
- Better xCloud
- XcodeGen
- GitHub Actions

### Acknowledgements

GameStream uses and integrates with open-source projects and platform technologies. Their respective names, licenses, and terms remain with their owners.

- **Better xCloud** for the userscript and streaming enhancements.
- **OpenNOW** (MIT) for the controller haptics design that GameStream's
  rumble implementation follows: a continuous pattern held at full strength
  and reshaped by dynamic parameters, one engine per controller, rebuilt
  whenever it stops. https://github.com/OpenCloudGaming/OpenNOW
- **Apple** frameworks for the native iOS application, controller input, haptics, WebView, and SwiftUI.
- **Android / Jetpack Compose** for the Android application layer.
- **GitHub Actions** for automated builds and release packaging.

### Creator note

GameStream started as a small cloud-gaming client and has grown through many iterations of UI, streaming, controller, catalog, and stability work.

**Made with ♥ by Bestin.**
