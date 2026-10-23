# Feature parity

Everything the Instagram website lets a signed-in user do, and whether the native interface
covers it yet. The goal is parity: whatever works on instagram.com should work here.

Legend: ✅ native · 🟡 partial · ❌ missing

## Home

| Feature | Status | Notes |
|---|---|---|
| Browse feed, infinite scroll | ✅ | |
| "For you" / "Following" switch | ❌ | |
| Carousel posts, inline video | ✅ | Sized by the first item, hover arrows; videos autoplay muted and loop while on screen |
| Like, double-tap to like | ✅ | Optimistic toggle with rollback on failure |
| Save / unsave | ✅ | |
| Open post on instagram.com | ✅ | |
| Share a post to a chat | ❌ | |
| Follow / unfollow from a post | ❌ | |

## Stories

| Feature | Status | Notes |
|---|---|---|
| Story tray | ✅ | Full tray from `reels_tray` |
| Watch other people's stories | ✅ | Full-window viewer, cube transition between people, hold to pause, resumes at first unseen slide, real video durations |
| Reply to / react to a story | ❌ | |
| Create a story | ❌ | |

## Comments

| Feature | Status | Notes |
|---|---|---|
| Read comments | ✅ | |
| Post a comment | ✅ | |
| Reply to / like a comment | ❌ | |

## Explore and search

| Feature | Status | Notes |
|---|---|---|
| Explore grid | ✅ | iOS mosaic layout |
| Search users, tags, places | 🟡 | Users and hashtags via `/api/v1/web/search/topsearch/`; places not yet |
| Recent searches | ❌ | |

## Reels

| Feature | Status | Notes |
|---|---|---|
| Vertical reels feed | ✅ | Only the visible reel plays; tap to mute, hold to pause, infinite paging |
| Like / save / comment | ✅ | |
| Follow the creator | ❌ | |

## Messages

| Feature | Status | Notes |
|---|---|---|
| Inbox | ✅ | Driven by hidden WebView `/direct/inbox/` (`PolarisDirectInboxQuery`) under a serialized page lease |
| Read and send messages | ✅ | Apple Messages layout; optimistic sending (`direct_v2/threads/broadcast/text/` with hidden WebView composer fallback) |
| Notes | ✅ | Native Notes bar (`IGDInboxTrayQuery`, text + music playback, replies and own notes) |
| Message requests | ❌ | |
| Start a new chat, group chats | 🟡 | Existing group chats work; starting a new chat not yet covered |
| Photos, reactions, replies, unsend | 🟡 | Attached photos/shares, emoji reactions and message replies work; sending photos and unsend are missing |

## Notifications

| Feature | Status | Notes |
|---|---|---|
| Activity list | ✅ | Sidebar inspector (`⌥⌘I`) or dedicated tab |
| Follow requests | ❌ | |

## Profile

| Feature | Status | Notes |
|---|---|---|
| Own profile header and grid | ✅ | Driven by hidden WebView `/<username>/` (`PolarisProfilePageContentQuery` + `PolarisProfilePostsQuery`), Instagram iOS layout |
| Other people's profiles | ✅ | Click any author in feed, stories, reels, notes, or messages |
| Follow / unfollow | ✅ | Native button on other users' profiles |
| Reels, tagged and saved tabs | ✅ | Driven by hidden WebView `/<username>/reels/`, `/tagged/`, `/saved/all-posts/` with scroll pagination |
| Followers / following lists | ✅ | Searchable, paginated sheet |
| Highlights | ✅ | `PolarisProfileStoryHighlightsTrayContentQuery` + `reels_media`, played in sequence in the story viewer |
| Edit profile, settings, log out | ✅ | Native Prismgram preferences (`⌘,`), Instagram settings (`⇧⌘,`), account privacy toggle, in-app edit profile and sign out |

## Creating

| Feature | Status | Notes |
|---|---|---|
| New post with caption and location | ❌ | |
