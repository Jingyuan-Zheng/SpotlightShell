# Background login-startup investigation — 2 September 2026

## Finding and scope

The missing-login-shell diagnosis could not be reproduced in this checkout or its installed build. The source at commit `1428d7b` already used a genuine noninteractive login zsh. It did not use Foundation `Process` or invoke `zsh -c` without `-l`.

The installed build-1 executable's SHA-256 matched the previously built Release executable:

```
70ec9d6718420810f466444e471bcaecd2e6e8bd4fb0979469f054aeb0d13bca
```

Previous invocation:

```swift
let arguments = CStringArray(["/bin/zsh", "-lc", request.command])
posix_spawn(&pid, "/bin/zsh", &actions, &attributes, argv, envp)
```

Current invocation is the same. The first array element is POSIX `argv[0]`. Its Foundation Process equivalent would be:

```swift
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = ["-lc", command]
```

There is no `-i`, explicit `.zshrc` sourcing, command-text rewriting, or nested shell wrapper in Background mode. The command remains one argument, and the working directory remains a separate spawn file action.

## Changes made

- Removed the previous hardcoded additions of Homebrew and other PATH directories. An inherited PATH is preserved verbatim. If PATH is absent, only `/usr/bin:/bin:/usr/sbin:/sbin` is supplied as a starting point. Normal login startup files determine subsequent PATH setup.
- Added explicit child-environment injection to the internal runner API so tests can use an isolated temporary HOME without changing process-global environment or real dotfiles. The app uses its normal environment by default.
- Strengthened the runtime login test to require both login and noninteractive shell options, including the requested `$-` check.
- Added a behavioral test with a temporary `.zprofile` that exports a marker and changes PATH, a `.zlogin` marker, and a `.zshrc` marker that must remain unset. It deliberately runs in `/tmp`, separate from the temporary HOME, to establish that the profile is found through HOME.
- Bumped `CFBundleVersion` to 2 and reinstalled the development-signed Release build.

These changes improve the startup contract and prevent PATH fallback from masking profile failures. They are **not proof that the reported Spotlight-specific failure has been fixed**: the original invocation also passed the added startup tests before PATH handling changed.

## Actual verification

1. Original Release runner: all 14 existing tests passed, including its existing login-shell check.
2. With the original invocation and PATH behavior, the isolated HOME test passed. A temporary diagnostic test using the real home directory plus a minimal system-only PATH also found `/opt/homebrew/bin/brew`. That machine-specific test was removed from the permanent portable suite.
3. A temporary windowless, Apple Development-signed GUI app compiled the same runner sources with Release optimization. A LaunchServices launch reported:

   ```text
   login=on
   noninteractive
   HOME=/Users/jingyuan
   ZDOTDIR_set=0
   /opt/homebrew/bin/brew
   Homebrew 6.0.21-26-g9368622
   ```

   Exit status was 0, stderr was empty, and PATH began with the Homebrew bin/sbin directories. This probe passed both before and after removing the hardcoded PATH additions. Its temporary source was removed after diagnosis; it is not included in the product.
4. Final Debug app build: succeeded for arm64 and x86_64. All 15 Debug tests passed, 0 failures (10.1 seconds).
5. Final Release app/test build: succeeded for arm64 and x86_64. All 15 Release tests passed, 0 failures (8.2 seconds).
6. Existing tests still cover separate stdout/stderr, nonzero status, timeout, cancellation, child cleanup, output limits, working-directory quoting, shell syntax and Terminal payload handling.
7. Installed app: `/Users/jingyuan/Applications/SpotlightShell.app`, build 2, Apple Development signing team `F4575K29KQ`, Hardened Runtime enabled. Strict signature verification passed. macOS completed indexing, accepted the app on its autoShortcut and mediator connections, and the app exited after approximately 16 seconds; no SpotlightShell process remained.

No user dotfiles, Terminal preferences or Spotlight settings were changed. No interactive shell was added to Background mode. Terminal mode retains its existing interactive behavior.

Builds used `xcodebuild build-for-testing` with Debug and Release configurations, followed by Apple's `xctest` runner on each built test bundle. A separate final Debug `xcodebuild build` also passed. As in the original verification, the agent's build sandbox emitted unrelated simulator/service diagnostics, and Xcode skipped App Intents metadata extraction for the test-only target. The application compiled without Swift compiler warnings and its App Intents metadata was generated. Signing was performed on a staging copy without Finder/File Provider extended attributes, which had caused a signing error in the synchronized build folder.

## Remaining Spotlight check

Computer Use again timed out acquiring Spotlight, so this investigation could not inspect or execute the selected Spotlight action. A similarly named saved shortcut, a different action, or an environment specific to Spotlight invocation has not been ruled out. None is asserted as the cause.

In Spotlight, explicitly select **Run Shell Command from SpotlightShell**, choose **Background**, and run each of these:

```sh
echo "$PATH"
command -v brew
brew --version
case "$-" in *i*) echo interactive;; *) echo noninteractive;; esac
```

The last command must print `noninteractive`. The PATH need not match an already-running interactive Terminal session exactly. If the discrepancy remains, also run `printf 'login=%s ZDOTDIR_set=%s\n' "$options[login]" "${+ZDOTDIR}"` and capture the selected action's app name along with its output; those distinguish login state and an unset versus empty ZDOTDIR without exposing the full environment.
