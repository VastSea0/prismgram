# Feature parity

Everything the Instagram website lets a signed-in user do, and whether the native interface
covers it yet. The goal is parity: whatever works on instagram.com should work here.

Legend: ✅ native · 🟡 partial · ❌ missing

## Home

| Feature | Status | Notes |
|---|---|---|
| Browse feed, infinite scroll | ✅ | |
| "For you" / "Following" switch | ❌ | |
| Carousel posts, inline video | ✅ | |
| Like, double-tap to like | ✅ | Optimistic toggle with rollback on failure |
| Save / unsave | ✅ | |
| Open post on instagram.com | ✅ | |
| Share a post to a chat | ❌ | |
| Follow / unfollow from a post | ❌ | |

## Stories

| Feature | Status | Notes |
|---|---|---|
| Story tray | ✅ | Full tray from `reels_tray` |
| Watch other people's stories | ✅ | Loaded on demand via `POST /api/v1/feed/reels_media/` with WebView route fallback |
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
| Explore grid | ✅ | |
| Search users, tags, places | ❌ | |
| Recent searches | ❌ | |

## Reels

| Feature | Status | Notes |
|---|---|---|
| Vertical reels feed | ✅ | Native `AVPlayerView` paging |
| Like / save / comment | ✅ | |
| Follow the creator | ❌ | |

## Messages

| Feature | Status | Notes |
|---|---|---|
| Inbox | ✅ | Driven by hidden WebView `/direct/inbox/` (`PolarisDirectInboxQuery`) |
| Read and send messages | ✅ | Thread detail via `IGDThreadDetailQuery`, sending via hidden WebView composer |
| Notes | ✅ | Native Notes bar (`IGDInboxTrayQuery`, text + music metadata) |
| Message requests | ❌ | |
| Start a new chat, group chats | 🟡 | Existing group chats work; starting a new chat not yet covered |
| Photos, reactions, replies, unsend | ❌ | |

## Notifications

| Feature | Status | Notes |
|---|---|---|
| Activity list | ✅ | Sidebar inspector (`⌥⌘I`) or dedicated tab |
| Follow requests | ❌ | |

## Profile

| Feature | Status | Notes |
|---|---|---|
| Own profile header and grid | ✅ | Driven by hidden WebView `/<username>/` (`PolarisProfilePageContentQuery` & `PolarisProfilePostsQuery`) |
| Other people's profiles | ✅ | Click any author in feed, stories, reels, notes, or messages |
| Follow / unfollow | ✅ | Native button on other users' profiles |
| Reels, tagged and saved tabs | ❌ | |
| Followers / following lists | ❌ | |
| Highlights | ✅ | Native Highlights bar (`PolarisProfileStoryHighlightsTrayContentQuery`) + StoryViewer |
| Edit profile, settings, log out | ❌ | |

## Creating

| Feature | Status | Notes |
|---|---|---|
| New post with caption and location | ❌ | |
