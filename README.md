# omarchy-asus/omarchy

A fork of [omacom/omarchy](https://github.com/omacom/omarchy) that holds Omarchy fixes for
ASUS laptops (ROG Zephyrus G16 GA605KM first) on their way upstream.

- **`quattro`** is upstream's `quattro`, unchanged. A daily workflow fast-forwards it
  (`.github/workflows/sync-upstream.yml`); nothing else is committed there.
- **One topic branch per fix**, each rebased on upstream `quattro`, listed in
  [`branches`](branches) with its kind and pull request draft (under [`prs/`](prs)).
  `pr/<name>` branches are the heads of pull requests open on omacom/omarchy.
- **`fork-tools`** (this branch, the default) holds only this README, the list, the drafts,
  the sync workflow and `rebase-topics`.
- **`asus/v4-0-5`** is the fixes backported onto the v4.0.5 release. The packages that ship
  them live in [omarchy-asus/omarchy-asus](https://github.com/omarchy-asus/omarchy-asus),
  as patch files on stock omarchy.

## Keeping the topic branches current

```sh
git clone -b fork-tools https://github.com/omarchy-asus/omarchy.git && cd omarchy
./rebase-topics --dry-run   # what would move
./rebase-topics             # rebase onto upstream quattro, push --force-with-lease
```

It reports branches upstream already has (remove them from `branches`) and branches that
don't rebase cleanly (left at their old tip; rebase those by hand).

## History

Until 2026-10-18 `quattro` was upstream with every topic branch merged in, and `asus/stack`
was the same as one linear series. Both are kept as tags:
`archive/quattro-integrated-2026-10-18` and `archive/asus-stack-2026-10-18`. Earlier tips of
rebased topic branches that neither tag holds are under `archive/topic-tips-2026-10-18/`.
