<img src="assets/icon.png" width="128" alt="Emberpath icon">

# Emberpath

A travel journal addon for a group of friends playing WoW: Forever.

## What it does

- **Omens.** At your first campfire of the day, you draw a secret challenge, like "No mount today" or "/bow to every quest giver". Only you can see it.
- **Campfires.** Every camp you pitch appears on your friends' world maps. You can leave a tale at any campfire, like "Elite patrols here, RUN".
- **Trails.** Your route is drawn on the map as a colored line that fades after a week.
- **The Gathering.** When you camp next to a friend, or at 21:00, everyone reveals their omen. You say whether you honored it, and friends vote on whether they believe you.
- **Ledger.** Stats, weekly titles like "The Wanderer", and every campfire tale.

The addon needs no server. It syncs through guild and party chat, so each friend needs the addon installed.

## Install

Copy or link this folder into `Interface/AddOns/Emberpath` in your WoW: Forever folder.

## Commands

- `/ember`: open the window
- `/pitch`: pitch a campfire where you stand
- `/ember tale <text>`: leave a tale at the nearest campfire
- `/ember gather`: start the Gathering now
- `/ember replay`: replay today's trails on the map

## Tests

```sh
luajit tests/run.lua
luajit tests/smoke.lua
```

## Release

Push a version tag. GitHub runs the tests, builds `Emberpath-<version>.zip` and attaches it to a release on the Releases page.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

Run `scripts/build.sh` to build the same zip locally in `.release/`.

## License

MIT. See [LICENSE](LICENSE).
