    func signIn(provider: StreamProvider) async {
        // Real sign-in hands off to the provider's own OAuth/web login flow
        // (a WKWebView-based auth session) — no credentials are handled in-app.
        let account = await gameService.authenticate(provider: provider)
        self.accountLabel = account
        self.isSignedIn = account != nil
        if isSignedIn {
            self.library = await gameService.fetchLibrary(provider: provider)
        }
    }
