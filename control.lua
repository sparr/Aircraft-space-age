require("control.assert-minable") --Asserts that vehicles are minable. Causes crash when entering all vehicles.

if script.active_mods["factorio-test"] and script.active_mods["asa-tests"] then
    require("__factorio-test__/init")({
        "test.ft.minable",
    }, {
        load_luassert = true,
        game_speed = 100,
    })
end
