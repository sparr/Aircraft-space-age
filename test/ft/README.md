# Integration tests

These run inside a real Factorio, on a real surface, with real entities.

```sh
npm install          # once
test/ft/run.sh       # the whole suite, headless
test/ft/run.sh -v    # with the game's own log lines
```

`ASA_FACTORIO` points at the game binary if it is not where the script expects.

`asa-tests` holds no prototypes. It exists so `control.lua` can tell a test run from a
player's game, since `.gitattributes` keeps `test/` out of the release archive and the
fixtures would not be there to require.

## What these are about

`control/assert-minable.lua` was written in December 2024 and commented out in the same
commit, with the note that it crashed when entering a vehicle. Both things that were wrong
with it are engine behavior rather than anything this mod controls, which is why they are
worth pinning here.

`LuaEntity::minable` answers whether an entity can be mined right now, and a vehicle
somebody is sitting in cannot be. `minable_flag` is the prototype flag, and it stays set
either way. Measured on both game versions:

| car | `minable_flag` | `minable` |
|---|---|---|
| empty | true | true |
| driver aboard | true | false |
| driver removed again | true | true |

So `assert(player.vehicle.minable)`, inside a loop over players who are *driving*,
asserted something that is false by construction. That is the crash from 2024.

Factorio 2.1 then made `minable` read only, so on 2.1 the write above the assertion raises
before the assertion can even fire:

```
Error while running event Aircraft-space-age::on_tick (ID 0)
LuaEntity::minable is read only.
```

The `baseline` branch is this suite on top of the module as shipped, with only the
`require` in `control.lua` switched on. That is where the error above comes from. On this
branch the same suite passes.
