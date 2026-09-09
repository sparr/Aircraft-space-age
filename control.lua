require("control.assert-minable") --Keeps vehicles minable while they are being driven.

-------------------------------------------------------------------------------
--[[Tests]]
-- The integration tier, which runs inside a live game rather than against stubs.
-- asa-tests is never published, so this can never fire on a player's machine -- which
-- matters, because .gitattributes keeps test/ out of the release archive and the fixtures
-- would not be there to require.
if script.active_mods["factorio-test"] and script.active_mods["asa-tests"] then
    require("__factorio-test__/init")({
        "test.ft.minable",
    }, {
        load_luassert = true,
        game_speed = 100,
    })
end
