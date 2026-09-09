--- That a vehicle somebody is driving stays flagged minable.
---
--- control/assert-minable.lua sets the flag every tick for whoever is driving. It spent
--- its whole life commented out because of the assertion that used to sit under that
--- line, and the reason is a piece of engine behavior worth pinning down here rather
--- than rediscovering later:
---
--- LuaEntity::minable answers whether the entity can be mined right now, and a vehicle
--- with somebody in it cannot be. minable_flag is the prototype flag, which stays set
--- either way. The two are not the same question, and only one of them is something a
--- module that runs while you are driving can assert.
---
--- Factorio 2.1 made minable read only as well, so the write had to move to minable_flag
--- regardless.

local POSITION = { x = 180, y = 180 }

local function surface() return game.surfaces["nauvis"] end

local function prepare()
    -- create_entity needs the chunk to exist, and a fresh headless save has generated
    -- almost nothing.
    surface().request_to_generate_chunks(POSITION, 2)
    surface().force_generate_chunk_requests()
    for _, entity in pairs(surface().find_entities_filtered { name = "car" }) do
        entity.destroy()
    end
end

local function car()
    local entity = surface().create_entity {
        name = "car",
        position = POSITION,
        force = "player",
        create_build_effect_smoke = false,
    }
    assert.is_truthy(entity, "the surface refused to build a car")
    return entity
end

--- The module only looks at vehicles a connected player is driving, so a fixture that
--- leaves the seat empty passes without the module having run at all.
local function driven()
    local entity = car()
    local player = game.players[1]
    assert.is_truthy(player, "the test game has no player to drive with")
    player.teleport(POSITION, surface())
    entity.set_driver(player)
    assert.is_true(player.driving, "the player would not get into the car")
    return entity, player
end

describe("the minable flag on a driven vehicle", function()
    before_each(prepare)

    test("is set by the module", function()
        -- Cleared first, so the fixture watches the module put it back rather than
        -- reading a default that was already true.
        local entity = driven()
        entity.minable_flag = false
        async()
        after_ticks(3, function()
            assert.is_true(entity.minable_flag, "the module did not set minable_flag")
            done()
        end)
    end)

    test("keeps being set, tick after tick", function()
        -- The module runs on every tick, so a fault in it shows up as the game dying
        -- partway through rather than as a failed assertion. Ticking well past the first
        -- one is the check, and the run completing at all is most of the result.
        local entity = driven()
        async(600)
        after_ticks(120, function()
            assert.is_true(entity.valid, "the car did not survive")
            assert.is_true(entity.minable_flag)
            done()
        end)
    end)

    test("is not what LuaEntity::minable reports while somebody is aboard", function()
        -- The distinction the removed assertion got wrong. This is engine behavior, not
        -- something this mod controls, and it is the same on 2.0.77 and 2.1.17.
        local entity, player = driven()
        entity.minable_flag = true
        assert.is_false(entity.minable, "a vehicle with a driver should not be mineable")
        entity.set_driver(nil)
        assert.is_false(player.driving)
        assert.is_true(entity.minable, "an empty car with the flag set should be mineable")
    end)
end)

describe("a vehicle nobody is driving", function()
    before_each(prepare)

    test("is left alone by the module", function()
        -- Pins the scope. If it ever grew to every vehicle on the map it would be writing
        -- to every car, tank and spidertron in the game, once a tick.
        local entity = car()
        entity.minable_flag = false
        async()
        after_ticks(3, function()
            assert.is_false(entity.minable_flag, "the module touched a vehicle with no driver")
            done()
        end)
    end)
end)
