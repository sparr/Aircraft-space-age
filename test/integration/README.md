# Integration tier (work in progress)

Drives the mod in a real graphical Factorio with real keyboard and mouse input, on a
private Xvfb display. Where the headless suite in `test/ft` checks that the module sets
`minable_flag`, this is meant to check the thing the flag is for: that a vehicle you have
driven can then be mined by hand, including a plane that has taken off and landed.

```sh
ASA_AIRCRAFTREALISM=/path/to/AircraftRealism test/integration/run.sh
```

## Status

**Not reliable yet, and not part of any pass/fail claim.** The runner drives the game
correctly and the scenario reports faithfully, but the session wedges after the first
vehicle entry often enough that this cannot be trusted as a gate. The game stops ticking
with the vehicle still selectable and no character on screen; it is not the window losing
focus, since activating the window and clicking does not resume it. Cause not yet found.

Use `test/ft` for a green-or-red answer. This is here so the harness is not lost, and
because the manual runs it grew out of did establish the behavior:

- With the module as shipped and the `require` uncommented, pressing Enter to get into a
  car kills the game on the spot: `Exception at tick 262: ... LuaEntity::minable is read
  only.`
- With the fix, a car driven and left can be mined by hand back into the inventory, and so
  can a gunship that has taken off (`gunship` to `gunship-flying`), flown, and landed
  (`gunship-flying` back to `gunship`) under real W and S keys. `minable_flag` stays true
  across both prototype swaps.

## How the two sides talk

The scenario cannot press keys and the shell cannot see the screen, so they take turns.
The scenario prints an `AWAIT` line when it wants input and the shell answers with xdotool.

Aiming the mouse is the fiddly part. The scenario reports the target's offset from the
player in tiles; at zoom 1 a tile is 32 screen pixels and the camera is centred on the
player, so that converts straight to a pixel. The shell still confirms against the
scenario's `SEL` line, which reports what the game says is under the pointer, before it
commits to a click. Standing the player *west* of the target works; standing *south* of it
put nothing selectable near the centre of the screen.

A window manager is mandatory. Without one SDL never gives the window mouse focus, so
Factorio ignores pointer motion and clicks entirely while keyboard input still works,
which makes it look like a mouse problem rather than a focus one.
