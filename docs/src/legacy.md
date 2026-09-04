# Legacy scripts

The original bash installers live under `legacy/` in this repository,
unmaintained and outside CI, as a read-only reference while catalog
entries are ported. Each catalog entry links back to its `legacy.ct` and
`legacy.install` paths. The tree is deleted once every entry has an
`impl` other than `planned`, or a documented reason it cannot.
