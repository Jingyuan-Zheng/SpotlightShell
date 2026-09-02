# Verification — 2 September 2026

## Delivered

- Repository: `/Users/jingyuan/Github/SpotlightShell` (the user's Github folder is a OneDrive symlink).
- Installed app: `/Users/jingyuan/Applications/SpotlightShell.app`.
- Native application and shared Xcode scheme, seven Swift source files, Info.plist, one app entitlement, 14 XCTest cases, README and .gitignore.
- macOS 26.0 deployment target. Verified using macOS 26.6.2 (25G83), Xcode 26.2 (17C52), macOS SDK 26.2.

## Actually verified

| Check | Result |
| --- | --- |
| Debug and Release compilation with xcodebuild | Passed; universal arm64 and x86_64 app |
| Swift compiler diagnostics in final app builds | No compiler errors or warnings |
| App exists and signature verifies | Passed; Apple Development signature, team F4575K29KQ, Hardened Runtime enabled |
| Installed app entitlements | Only `com.apple.security.automation.apple-events`; no App Sandbox |
| Extracted App Intents metadata | Runtime required String command, optional String directory, Background/Terminal enum, all three inline summary fields, discoverable intent and App Shortcut |
| LaunchServices | Installed application registered with identifier `dev.jingyuan.SpotlightShell` |
| macOS App Intents service | Signed client accepted; metadata indexing transactions completed; shortcut-change notifications issued |
| Idle lifetime | Installed signed app launched twice and exited after approximately 15 seconds; no SpotlightShell process remained |
| XCTest | 14 tests passed, 0 failures, 10.7 seconds on arm64 |

Tests exercised stdout and stderr independently, exit status 7, closed stdin and absence of a TTY, login zsh and `$SHELL`, PATH fallback ordering, a TERM-ignoring command timing out, cancellation, ordinary child cleanup, simultaneous large stdout/stderr with visible truncation, input validation, shell quoting, Apple Event string round-trip, and Terminal payload execution/failed-directory short-circuiting. Directory tests include spaces, single and double quotes, dollar signs, backticks, Chinese characters and a newline. Only harmless commands and disposable test directories were used.

Terminal payload tests execute the same payload through zsh, including the interactive shell option. They do **not** test a real Terminal window, TTY, Automation consent, or Spotlight invocation.

## Build/test procedure used by the agent

Compilation used the following commands from the isolated Git worktree, with logs kept in ignored `build/`:

```sh
xcodebuild -project SpotlightShell.xcodeproj -scheme SpotlightShell \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build-for-testing

/Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  build/Build/Products/Debug/SpotlightShellTests.xctest

xcodebuild -project SpotlightShell.xcodeproj -scheme SpotlightShell \
  -configuration Release -derivedDataPath build \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build

codesign --force --sign 'Apple Development: mr.jingyuan.zheng@icloud.com (FYJ3J7XP24)' \
  --options runtime --entitlements SpotlightShell/SpotlightShell.entitlements \
  --timestamp=none build/Build/Products/Release/SpotlightShell.app

codesign --verify --strict --verbose=2 \
  build/Build/Products/Release/SpotlightShell.app
```

Compilation and certificate signing were separated because of the agent's execution environment. The project itself is configured for this Mac's existing Apple Development identity/team, so normal Xcode use can sign during the build. No certificate was created, imported or exported.

The initial unrestricted `xcodebuild test` stalled before compilation in `NSFileCoordinator` while opening the workspace; a process sample identified that wait. Only that agent-started process was terminated. Building the test bundle with `xcodebuild build-for-testing`, then invoking Apple's `xctest` directly, succeeded. The normal `xcodebuild test` orchestration is therefore not claimed as verified. Sandboxed Xcode also emitted unrelated simulator/service diagnostics; the test-only target emitted its expected “No AppIntents.framework dependency found” metadata-extraction warning. App metadata extraction succeeded.

The first XCTest run found one incorrect assertion caused by `/var` versus `/private/var` physical-path representation. The test now compares the POSIX `realpath`; the final full suite passed.

## Signing and registration finding

The ad-hoc build compiled and its static metadata was indexed, but `linkd` rejected its runtime shortcut-refresh connection because it had no team identifier. Signing with the existing Apple Development certificate resolved client validation. This is why the delivered project uses a real development identity instead of relying on ad-hoc signing.

Evidence from the signed installation:

- 13:09:41: `linkd` accepted the signed SpotlightShell client.
- 13:09:43: indexing completed using metadata from the installed app.
- The first signed launch reported a private refresh error while installation/indexing was occurring.
- 13:10:33: a second launch was accepted by both autoShortcut and mediator services; its indexing completed, without the earlier refresh error in that launch's observed log.
- 13:10:49: AppKit logged completed termination; a process check found no remaining SpotlightShell process.

This confirms native registration/indexing and idle termination. It does not substitute for seeing and running the action in Spotlight.

## Still requires interactive testing

The Computer Use service timed out while acquiring Spotlight, before any visible UI could be inspected. No claim is made that the action's visible row, inline input, results, Quick Keys or Terminal handoff were tested end to end. Spotlight settings, shell startup files, Terminal preferences, system services and privacy permissions were not changed.

1. Press **Command-Space**, then **Command-3**. Search **Run Shell Command** or **SpotlightShell** and select the SpotlightShell action.
2. Type `printf "hello\n"` in Command, choose **Background**, leave Working Directory empty, and press Return. Expect exit status 0 and stdout `hello`.
3. Test `pwd` with `/tmp`, then `echo "$SHELL"`. Test `printf 'example error\n' >&2; exit 7` to check visible stderr/status.
4. Choose **Terminal**, enter `printf "hello\n"; tty`, and run it. If macOS asks, allow SpotlightShell to control Terminal. Expect a new Terminal window and a `/dev/ttys…` device. Then try `top` and quit it with `q`.
5. Wait for the utility to exit and invoke it again through Spotlight to test cold intent delivery and the five-second post-action idle exit.
6. Beside the action, choose **Add quick keys**, enter `sh`, and confirm. Invoke with Command-Space, `sh`, then enter the command. This is a manual user setting documented by [Apple](https://support.apple.com/guide/mac-help/mchl4953dfeb/mac).

If Spotlight does not show the action immediately, reopen the installed app and check Shortcuts → Apps → SpotlightShell. The README covers fallback parameter configuration, shell/environment limits, output caps, signing, privacy and process-group limitations.
