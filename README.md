# InstagramMac

A hobby project that makes using Instagram on a Mac nicer: a native SwiftUI interface for
your own account, with three window layouts (phone, hybrid, desktop).

> **No guarantees.** This is an unofficial, personal project. It is not affiliated with or
> endorsed by Meta or Instagram. It can break whenever Instagram changes its website, and
> using automated clients may be against Instagram's terms. It doesn't bypass anything, it
> doesn't unlock anything, and it only ever talks to Instagram as the account you sign in
> with. Use it at your own risk.

## Requirements

- macOS 26 or later
- Xcode 26 or later (Swift 6.2 toolchain)

## Build and run

```sh
scripts/build-app.sh
open Instagram.app
```

On first launch you sign in through Instagram's own login page. After that the session is
kept in the app's persistent website data store.

## Status

See [docs/FEATURES.md](docs/FEATURES.md) for what works and what is still missing.

## License

MIT, see [LICENSE](LICENSE).
