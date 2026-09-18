# blurb repository onboarding

Inspected September 17, 2026. Scope: the available local repository; no attached ZIP was visible, so equivalence to that ZIP has not been verified. Source files take precedence over this report and the older README. No application code or cloud resources were changed.

## A. Project overview

Daily Blurb is a native iPhone private-group social app (the README also discusses iPad, but the app target sets TARGETED_DEVICE_FAMILY = 1). People sign in with Apple, create or join groups, answer recurring prompts with text/photos, reuse answers across groups, and interact through likes and comments. It includes points, streaks, newsletter previews/archives, local reminders, and reply push notifications.

The architecture is a small, MVVM-inspired SwiftUI app: views use shared ObservableObjects, AuthManager handles identity, and BlurbStore contains models, Firebase operations, and listeners. Most UI lives in ContentView.swift. The serif/newspaper styling and existing SwiftUI/Firebase patterns are conventions to preserve.

Data flow:
1. blurbApp configures Firebase and notification delegates, then shows WelcomeView or ContentView according to Firebase Auth state.
2. Apple credentials with a hashed nonce authenticate through Firebase; profile data is written to users/{uid}.
3. ContentView refreshes the session and starts BlurbStore listeners for membership, profile, newsletters, group posts, participation counts, and comments.
4. QuestionBank computes prompts locally, using a 5 AM America/Los_Angeles content-day boundary. Preferences are stored locally with AppStorage/UserDefaults.
5. Posting optionally uploads a JPEG to Storage, then writes a group-specific Firestore post. Snapshot listeners update the UI. Comments and count increments are batched.
6. A comment-created Cloud Function sends FCM/APNs notifications to the post author. A scheduled function generates the previous month's group newsletters on the third at 8 AM Pacific.

Implemented does not mean production-verified: core screens and persistence paths exist, but backend deployment and end-to-end behavior remain unverified. The README's future-work section predates notification and newsletter implementations.

## B. Technology stack

| Area | Repository evidence |
|---|---|
| iOS | Swift, SwiftUI, UIKit, PhotosUI, AuthenticationServices, CryptoKit, UserNotifications |
| Build | Xcode project; Swift language mode 5.0; iOS deployment target 18.5; iPhone target; project created with Xcode 16.4 |
| iOS dependencies | Swift Package Manager through project.pbxproj and Package.resolved; Firebase iOS SDK locked to 12.18.0, allowed from 12.0.0 up to the next major |
| Firebase products linked | Auth, Core, Firestore, Storage, Messaging |
| Backend | JavaScript/CommonJS, Firebase Functions v2, Node.js 22 |
| Backend dependencies | npm; package.json and package-lock.json; locked firebase-admin 13.10.0 and firebase-functions 6.6.0 |
| Websites | Static HTML/CSS and image/SVG assets; no frontend bundler |
| Tests | Swift Testing unit target; XCTest UI target |
| Hosting | Firebase Hosting configured for public/; README describes docs/ as a GitHub Pages site, but remote Pages configuration is not in the repository |

There is no custom HTTP API server: the app uses Firebase SDKs directly; backend exports are event/schedule triggers. No SQL database, migrations directory, Docker/Compose, Python dependency manifest, CI workflow, formatter/linter configuration, CONTRIBUTING.md, or applicable AGENTS.md was found. Firestore schema is implicit in Swift/JavaScript models and security rules; BlurbStore also backfills missing invite records for group owners.

## C. Repository map

```text
README.md                          Product/architecture/setup notes; partly outdated
ONBOARDING.md                      This reusable repository context
blurb.xcodeproj/
  project.pbxproj                  Targets, signing, build settings, SPM references
  project.xcworkspace/.../
    swiftpm/Package.resolved       Locked Swift dependencies
  xcuserdata/                     User-specific scheme metadata
blurb/
  blurbApp.swift                   @main entry, Firebase setup, auth routing
  AuthManager.swift               Apple/Firebase auth, profile bootstrap, auth deletion
  BlurbStore.swift                 Models, listeners, CRUD, images, account-data cleanup
  ContentView.swift               Most app screens, composition, groups, profile/settings
  WelcomeView.swift               Sign-in/onboarding screen
  QuestionBank.swift              Deterministic prompt calendar, polls, trivia
  NotificationManager.swift       Local reminders, FCM tokens, APNs app delegate
  GroupNewsletterHomeView.swift   Current-month preview and archive navigation
  ArchivedNewsletterView.swift    Saved/live newsletter rendering
  DemoMonthlyNewsletterView.swift Sample newsletter with fictional content
  GoogleService-Info.plist        Checked-in Firebase client configuration
  blurb.entitlements              Apple sign-in and development APNs entitlement
  Assets.xcassets/                App icon/colors
blurbTests/                       Placeholder unit test
blurbUITests/                     Launch/performance/screenshot scaffolding
functions/
  index.js                       Reply notifications and monthly newsletter triggers
  package.json, package-lock.json Node runtime and dependencies; no npm scripts
firebase/
  firestore.rules                Document permissions and limited validation
  firestore.indexes.json         Three composite indexes on posts
  storage.rules                  Image ownership/membership/type/size checks
firebase.json                    Functions, rules, indexes, Hosting configuration
.firebaserc                      Default Firebase project alias
docs/                            Marketing website, support, promotional artwork
public/                          Firebase-hosted privacy and support pages
AppStoreScreenshots/             Three checked-in screenshot PNGs
.gitignore                       Build/cache/macOS metadata exclusions
```

Local .firebase/, .screenshot-derived-data*, functions/node_modules/, and AppleDouble ._* files are deployment/build/dependency/volume artifacts, not authoritative source. The repository was clean before adding this report.

Firestore collections: users, groups, groupInvites, posts with comments subcollections, and newsletterEditions. Storage paths: profile-images/{uid}.jpg and post-images/{groupID}/{uid}/{postID}.jpg. Posts carry viewerIDs, but current feed queries/rules use group membership; newsletter reads use saved viewerIDs.

## D. Setup and run instructions

These are the most likely commands derived from configuration; full iOS execution has not been verified here.

Prerequisites: macOS with full Xcode and an iOS 18.5-or-later simulator SDK/runtime; Node 22/npm for Functions; Firebase CLI for backend operations. Configure the intended Apple signing team/bundle ID, Apple sign-in provider, Firebase Auth/Firestore/Storage, and APNs/FCM integration. The checked-in Firebase plist exists and its project ID matches the CLI default alias; this does not verify cloud provisioning.

From the repository root:

```sh
xcodebuild -resolvePackageDependencies -project blurb.xcodeproj -scheme blurb
npm ci --prefix functions
xcodebuild -list -project blurb.xcodeproj
xcodebuild -showdestinations -project blurb.xcodeproj -scheme blurb
```

Open blurb.xcodeproj in Xcode, select the blurb scheme and an available simulator/device, and Run. There is no npm dev command or iOS development web server.

Simulator build, replacing the destination placeholder:

```sh
xcodebuild -project blurb.xcodeproj -scheme blurb -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/blurb-derived build
```

Production archive, with signing correctly configured:

```sh
xcodebuild -project blurb.xcodeproj -scheme blurb -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/blurb.xcarchive archive
```

Use Xcode Organizer for distribution. No export-options plist or release pipeline is provided. Static sites and plain-JavaScript Functions have no build/transpile step.

Backend deployment reference only; not executed during onboarding:

```sh
firebase deploy --only firestore:rules,firestore:indexes,storage,functions,hosting \
  --project <FIREBASE_PROJECT_ID>
```

No Emulator Suite settings or app-side emulator connections are configured. Running the app normally connects to the project identified by its plist. Fully isolated local backend development requires additional configuration.

## E. Testing and validation instructions

```sh
xcodebuild -project blurb.xcodeproj -scheme blurb \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/blurb-derived test
node --check functions/index.js
```

Actual onboarding results: Node syntax check passed. Node 22.6.0 and npm 10.8.2 are available. xcodebuild -version failed because the active developer directory is CommandLineTools rather than full Xcode. Firebase CLI was not found on PATH. No iOS build/tests, dependency installation, rules emulator tests, deployment, or live service validation was performed.

The unit test has no assertions. UI tests launch the app, measure launch performance, and capture screenshots; they do not verify product flows. No backend tests or npm test/lint/format/build scripts exist. No configured lint/format command was found.

Priority manual validation in a test Firebase project: two-user group isolation, create/join, text/photo posting and reuse, comments/likes, edit/delete, account deletion, notification preferences, and newsletter generation/membership changes. Debug-only -AppStoreScreenshot welcome|home|feed arguments provide screenshot fixtures; they are launch arguments, not environment variables or a full emulator mode.

## F. Required environment-variable names

No application-defined environment-variable reads, .env template, or Functions secret/parameter declarations were found. Do not invent an .env setup.

Firebase client configuration comes from GoogleService-Info.plist. Relevant configuration keys (not shell variables):

| Key | Purpose |
|---|---|
| API_KEY | Firebase client API configuration |
| PROJECT_ID | Backend project selection |
| GOOGLE_APP_ID | Registered Firebase iOS app |
| GCM_SENDER_ID | Messaging sender configuration |
| STORAGE_BUCKET | Image bucket |
| BUNDLE_ID | Registered iOS bundle |

The plist also contains PLIST_VERSION and service enablement flags. Values are intentionally omitted. Signing uses Xcode DEVELOPMENT_TEAM and PRODUCT_BUNDLE_IDENTIFIER settings. Server initializeApp() relies on the managed Firebase runtime's credentials/configuration; the repository does not specify manual service-account credentials. APNs credentials and Apple/Firebase provider setup are external configuration, not checked-in environment variables.

## G. Current risks, missing pieces, or uncertainties

1. **Authorization needs hardening.** Group self-join rules verify that the group's stored invite exists, but do not prove the caller knows its code. Inference: knowledge of a group ID can suffice to self-add via a direct write. Invite codes are only six hexadecimal characters, without collision retry. Members can rewrite the entire likeIDs list; post creation does not enforce server-trusted scores, timestamps, prompt validity, or canonical IDs. The answer-to-unlock gate is UI-only; members can read posts before answering.
2. **Deletion is incomplete and non-atomic.** Individual post deletion leaves comments and images. Account deletion does not remove comments on others' posts or newsletter snapshots; deleted posts' subcollections can remain. Group deletion does not delete newsletter editions. Data deletion precedes Auth deletion, which may fail for stale login. Several Storage failures are suppressed. Apple token revocation is not implemented.
3. **Prompt IDs are not consistently daily or annual.** Ordinary surface/timely IDs lack a year/date and birthday uses birthday-today. Deterministic post IDs include these IDs, so repeated prompts can collide with prior answers. This is a source-derived correctness risk, not a reproduced runtime failure.
4. **Newsletter access and retention use snapshots.** viewerIDs is fixed at generation, and read rules do not recheck current group membership. Former members can retain access, new members lack older editions, and copies survive source deletion. This requires an explicit product policy. Reflection answers are ordinary member-readable posts, despite the README's wording about private reflections.
5. **Several settings/integrations are incomplete.** Weekly Trivia and Monthly report switches are stored but have no consumers outside Settings. Trivia isCorrect has no call sites. Copied blurb.app/join links have no checked-in URL handler, associated-domains entitlement, or hosting route. FCM token refresh saves tokens without consulting replyNotificationsEnabled. Reminder scheduling covers only 30 days and is restored from Settings.
6. **Scores/time boundaries can disagree.** Posting calculates rank from locally loaded posts, which may be stale or belong to another selected group. Streaks/profile points use the selected group's posts and Calendar.current, while prompts use a Pacific 5 AM boundary. Newsletter winners group by display name, merging people with identical names.
7. **Scale and portability need work.** Feeds load all group posts; the scheduler scans every group and all its posts, then embeds newsletter entries in one document. There is no pagination or batching strategy for large datasets. ContentView (~2,500 lines) and BlurbStore (~1,000 lines) concentrate responsibilities. Index definitions still emphasize viewerIDs although current post queries do not. Promotional HTML references temporary file:// images from another machine.
8. **Operational state is unknown.** Cloud deployment, provider/APNs credentials, billing, actual indexes, App Store/TestFlight status, and live hosting cannot be established from files. There is no CI or meaningful automated coverage. README naming/status/setup is stale, and no shared .xcscheme file is checked in despite user scheme metadata.

## H. Five recommended next actions

1. Add focused Firebase Emulator authorization tests, then fix invite authorization, post/like validation, and decide newsletter membership access policy.
2. Implement and test complete, retry-safe deletion across Auth, Firestore/subcollections, Storage, and newsletter copies; authenticate deletion before destructive cleanup.
3. Fix prompt occurrence IDs and define a compatibility/migration plan before changing existing document IDs; test day/year/DST boundaries, ranking races, and cross-group reuse.
4. Establish a reproducible full-Xcode build/test baseline and meaningful tests/CI; validate notification preferences, APNs delivery, and scheduler behavior in a test project.
5. Reconcile README/product behavior, wire or remove inactive toggles, complete invitation links, and document verified release/hosting/backend configuration.

## I. Questions the repository cannot answer

- Is this local checkout identical to the intended ZIP, or is another snapshot authoritative?
- Which Firebase environment and Apple signing/distribution setup should future work target, and what is already deployed? No secret values are needed.
- Should new/former group members access historical newsletters, and should deleting an answer/account remove it from generated editions?
- Is answer-before-reading a user-experience convention or a backend-enforced privacy requirement? Are reflections intended to be private to their author or shared with their group?

## Future working context

Signing follow-up: the user reported Xcode No Accounts and no development profile for sasinkg.blurb. Both app configurations use automatic signing with a fixed development team. Full Xcode exists at /Applications/Xcode.app, although the active command-line developer directory points elsewhere. Device provisioning requires signing in to the appropriate Apple account and selecting its team; simulator builds do not require an iOS device provisioning profile. Concurrent external changes added generated Info.plist settings during onboarding; those changes were left intact.

Read this report alongside current source before future changes. Preserve native SwiftUI, ObservableObject/async-await, centralized Firebase operations, deterministic local scheduling, and newspaper visual conventions unless an explained change is warranted. Update this report when facts change. This file provides portable context; automatic availability in every future ChatGPT Project conversation is not guaranteed by a local repository write. Add the report to Project files/instructions if conversations do not share this workspace.
