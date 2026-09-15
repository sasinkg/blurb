# Daily Burb

Daily Burb is a private social app that helps close friends stay connected through one thoughtful question each day. Instead of placing everyone into a public feed, the app organizes conversations around small, intentional groups.

Each group has its own daily feed, so people can answer differently depending on who they are talking to. Answers can also be reused across selected groups when the same response feels appropriate.

[Visit the project website](https://sasinkg.github.io/blurb/)

![Daily Burb product overview](docs/assets/blurb-linkedin-newspaper.png)

## Why I built it

Most social apps optimize for broadcasting and endless consumption. Daily Burb explores a different model: a small daily ritual that creates conversation between people who already care about one another.

The product is built around three principles:

- Private by default
- Group context matters
- Participation should feel intentional, not addictive

## Features

- One daily question shared across the app
- Separate private feeds for each friend group
- Different answers for different groups
- Reuse an answer in one or more other groups
- Create groups and join them with secure invite codes
- Real-time group posts and participation counts
- Text and photo responses
- Profile names and profile photos
- Likes, comments, streaks, points, and achievement badges
- Weekly trivia
- One private reflection question each week for monthly recaps
- Two recurring photo prompts each month
- Light, dark, and system appearance settings
- Sign in with Apple, sign out, and account deletion

## Architecture

Daily Burb is a native iOS application written in SwiftUI. It uses a lightweight, MVVM-inspired architecture with Firebase as the backend.

### App and presentation layer

`blurbApp` configures Firebase, owns the shared authentication and app-data objects, and chooses between onboarding and the signed-in experience.

`ContentView` contains the primary SwiftUI navigation and presentation flow. The interface uses a group-first home screen instead of a universal social feed. Native `NavigationStack`, sheets, tab navigation, photo pickers, and system appearance APIs keep the experience familiar on iPhone and iPad.

The visual system uses a newspaper-inspired editorial style with serif typography, strong rules, rectangular cards, and a contextual yellow accent that adapts between light and dark mode.

### State and data layer

`BlurbStore` is the app's central `ObservableObject`. It owns groups, posts, profile data, selected-group state, and Firebase listeners. Keeping Firebase access in one store gives views a consistent source of truth and prevents backend details from spreading throughout the UI.

Firestore snapshot listeners keep group membership, feeds, profiles, and answer counts current without requiring manual refreshes. New groups are also inserted into local state immediately after a successful write, giving the interface responsive feedback while the listener catches up.

`QuestionBank` generates deterministic prompts locally. This avoids a backend request just to display the day's question and ensures everyone sees the same prompt for a given date. It also schedules weekly trivia, private reflection prompts, and photo prompts.

### Authentication

`AuthManager` wraps Sign in with Apple and Firebase Authentication. Apple credentials authenticate the Firebase user, while the user's available name is persisted to their Firestore profile. Firebase's authentication-state listener determines whether the app displays onboarding or the main experience.

### Firebase services

- **Firebase Authentication:** Sign in with Apple and user sessions
- **Cloud Firestore:** Profiles, groups, invitations, posts, reactions, and real-time updates
- **Cloud Storage:** Profile pictures and photo responses
- **Firebase Security Rules:** Membership-based access control and upload validation

## Data model

The main Firestore collections are:

```text
users/{userID}
groups/{groupID}
groupInvites/{inviteCode}
posts/{postID}
```

A post contains a `groupID`, so the same person can submit a different response in each group. Posts also contain a `viewerIDs` snapshot used by feed queries and security rules.

Invitations are deliberately separated from group documents. A signed-in person can fetch a single invite only when they know its exact code, but invite documents cannot be listed or queried. Normal group documents remain readable only by their members. Creating a group writes the group and its invite together in a Firestore batch.

Images use predictable, user-scoped Storage paths:

```text
profile-images/{userID}.jpg
post-images/{groupID}/{userID}/{postID}.jpg
```

Storage rules limit uploads to authenticated users, image content types, files under 5 MB, and the appropriate user or group membership.

## Important architecture choices

### Groups are the core social boundary

The home screen presents the user's groups and today's participation rather than combining every friend into one feed. Entering a group feels like entering a private room, and every response retains its conversational context.

### Answers belong to groups

Responses are stored as group-specific posts instead of one global answer copied everywhere. This avoids context collapse between family, friends, classmates, or coworkers. A reuse flow preserves convenience without removing control.

### Invite lookup is separate from group access

Allowing invite-code queries directly against `groups` would require broader read permissions than the product's privacy model should allow. The separate `groupInvites` collection supports direct code lookup while keeping group metadata private.

### Prompts are deterministic and local

The prompt calendar lives in the app rather than requiring a scheduled backend job for the MVP. This lowers complexity and cost while still providing daily, weekly, monthly, trivia, and photo-based experiences.

### Native-first interface

The app favors SwiftUI and Apple platform conventions over a custom cross-platform navigation system. This provides native gestures, accessibility behavior, appearance support, and familiar controls with a relatively small codebase.

## Running the project

### Requirements

- macOS with Xcode
- An Apple Developer account for Sign in with Apple and device distribution
- A Firebase project with Authentication, Firestore, and Storage enabled
- Firebase CLI for deploying backend rules

### Setup

1. Clone the repository.
2. Open `blurb.xcodeproj` in Xcode.
3. Add your Firebase iOS configuration file as `blurb/GoogleService-Info.plist`.
4. Confirm the bundle identifier and development team under **Signing & Capabilities**.
5. Enable the **Sign in with Apple** capability.
6. In Firebase Authentication, enable Apple as a sign-in provider.
7. Build and run on an iPhone, iPad, or simulator.

### Deploy Firebase rules and indexes

Select your Firebase project and deploy the checked-in configuration:

```bash
firebase use YOUR_PROJECT_ID
firebase deploy --only firestore:rules,firestore:indexes,storage --project YOUR_PROJECT_ID
```

## Project structure

```text
blurb/
├── blurbApp.swift        App entry point and appearance configuration
├── AuthManager.swift     Sign in with Apple and Firebase authentication
├── BlurbStore.swift      Models, shared state, and Firebase data operations
├── ContentView.swift     Main navigation and signed-in SwiftUI experience
├── QuestionBank.swift    Daily and recurring prompt scheduling
├── WelcomeView.swift     Authentication and onboarding interface
└── Assets.xcassets       App icon, colors, and image assets

firebase/
├── firestore.rules       Firestore authorization rules
├── firestore.indexes.json
└── storage.rules         Image access and validation rules

docs/                     GitHub Pages website and promotional assets
```

## Current status

Daily Burb is an MVP under active development. The core group, prompt, profile, photo, authentication, and Firebase flows are implemented. Future work includes notification scheduling, richer monthly reports, moderation tools, accessibility testing, analytics, automated tests, and additional production hardening.

## Built by

Created by [Sasin Gudipati](https://github.com/sasinkg).
