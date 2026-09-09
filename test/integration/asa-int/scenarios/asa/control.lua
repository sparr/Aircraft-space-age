-- Drives the mod with real input and reports what happened.
--
-- The headless suite checks that the module sets minable_flag. This checks the thing the
-- flag is for: that a vehicle you have driven can afterwards be mined by hand, including
-- a plane that has taken off and landed, which is the case that produced the flag in the
-- first place.
--
-- The scenario cannot press keys and the shell cannot see the screen, so they take turns.
-- The scenario prints an AWAIT line when it wants input and the shell answers with
-- xdotool. Everything the shell needs to aim is in the line it is answering.

local function say(s) log("ASA " .. s) end

local function describe(e)
    if not (e and e.valid) then return "gone" end
    return e.name .. " minable_flag=" .. tostring(e.minable_flag) .. " minable=" .. tostring(e.minable)
end

local function counts(player)
    local inv = player.get_main_inventory()
    return "car=" .. inv.get_item_count("car") .. " gunship=" .. inv.get_item_count("gunship")
end

--- Put the player next to the target and tell the shell where it ended up.
---
--- At zoom 1 a tile is 32 screen pixels and the camera is centred on the player, so an
--- offset in tiles is all the shell needs to aim. It still checks with SEL before
--- clicking, because a stale assumption about the scale would otherwise mine nothing and
--- look like a mod failure.
local function line_up(player, target)
    -- West of the target's own footprint rather than a fixed offset, because a plane is
    -- several tiles across and standing at a fixed distance either lands inside it, which
    -- makes the teleport fail silently, or ends up out of mining reach.
    local box = target.bounding_box
    player.teleport({ x = box.left_top.x - 1.2, y = target.position.y }, target.surface)
    player.zoom = 1
    local dx = target.position.x - player.position.x
    local dy = target.position.y - player.position.y
    return string.format("dx=%.2f dy=%.2f", dx, dy)
end

script.on_event(defines.events.on_player_mined_entity, function(e)
    storage.mined = true
    say("MINED " .. e.entity.name .. " -- inventory now " .. counts(game.get_player(e.player_index)))
end)

script.on_event(defines.events.on_player_driving_changed_state, function(e)
    local player = game.get_player(e.player_index)
    say((player.driving and "ENTERED " or "EXITED ")
        .. describe(player.driving and player.vehicle or storage.target))
end)

local function ask_to_mine(player)
    local aim = line_up(player, storage.target)
    say("BEFORE-MINE " .. describe(storage.target) .. " inventory " .. counts(player))
    say("AWAIT-MINE " .. storage.target.name .. " " .. aim)
end

local function build_plane(player)
    local plane = player.surface.create_entity {
        name = "gunship", position = { x = 0, y = 0 }, force = "player",
        create_build_effect_smoke = false,
    }
    if not plane then say("NO-GUNSHIP"); say("COMPLETE"); return false end
    plane.insert { name = "rocket-fuel", count = 100 }
    storage.target = plane
    storage.mined = nil
    line_up(player, plane)
    say("READY " .. describe(plane))
    say("AWAIT-ENTER-PLANE")
    return true
end

local function setup(player)
    local surface = player.surface
    surface.request_to_generate_chunks({ x = 60, y = 0 }, 6)
    surface.force_generate_chunk_requests()
    if not player.character then
        local c = surface.create_entity { name = "character", position = { x = 0, y = 0 }, force = "player" }
        player.set_controller { type = defines.controllers.character, character = c }
    end
    player.cheat_mode = true
    -- A long strip of refined concrete: somewhere for the plane to roll, and nothing for
    -- the landing collision check to object to.
    local tiles = {}
    for x = -30, 220 do
        for y = -12, 12 do tiles[#tiles + 1] = { name = "refined-concrete", position = { x, y } } end
    end
    surface.set_tiles(tiles)
    for _, e in pairs(surface.find_entities_filtered {
        area = { { -35, -16 }, { 225, 16 } }, type = { "tree", "simple-entity", "cliff" }
    }) do e.destroy() end
end

script.on_event(defines.events.on_tick, function(e)
    local player = game.players[1]
    if not player then return end

    -- What the pointer is over, so the shell can confirm its aim before clicking.
    if e.tick % 15 == 0 then
        local s = player.selected
        say("SEL " .. ((s and s.valid) and s.name or "nothing"))
    end

    if e.tick == 60 then
        setup(player)
        local car = player.surface.create_entity {
            name = "car", position = { x = 0, y = 0 }, force = "player", create_build_effect_smoke = false,
        }
        car.insert { name = "solid-fuel", count = 20 }
        storage.target = car
        storage.stage = "car"
        line_up(player, car)
        say("READY " .. describe(car))
        say("AWAIT-ENTER-CAR")
        return
    end

    if e.tick < 90 or e.tick % 15 ~= 0 then return end

    -- State driven rather than on a timer: a slow frame rate cannot march past a step.
    local t = storage.target
    if storage.stage == "car" and t and t.valid and not player.driving and not storage.mined then
        if storage.drove then
            storage.stage = "car-mine"
            ask_to_mine(player)
        end
    elseif storage.stage == "car" and player.driving then
        storage.drove = true
    elseif storage.stage == "car-mine" and storage.mined then
        storage.stage = "plane"
        say("AFTER-MINE car-still-there=" .. tostring(t ~= nil and t.valid)
            .. " inventory " .. counts(player))
        if not build_plane(player) then storage.stage = "done" end
    elseif storage.stage == "plane" and player.driving and t and t.valid
           and t.name == "gunship-flying" then
        storage.stage = "airborne"
        say("AIRBORNE-CONFIRMED " .. describe(t))
    elseif storage.stage == "plane" and player.driving and player.vehicle then
        storage.target = player.vehicle
    elseif storage.stage == "airborne" then
        storage.target = player.vehicle or storage.target
        local p = storage.target
        if player.driving and p and p.valid and p.name == "gunship"
           and math.abs(p.speed or 0) < 0.02 then
            storage.stage = "landed"
            say("LANDED " .. describe(p))
            say("AWAIT-EXIT")
        end
    elseif storage.stage == "landed" and not player.driving then
        storage.stage = "plane-mine"
        ask_to_mine(player)
    elseif storage.stage == "plane-mine" and storage.mined then
        storage.stage = "done"
        say("AFTER-MINE-PLANE plane-still-there=" .. tostring(t ~= nil and t.valid)
            .. " inventory " .. counts(player))
        say("COMPLETE")
    end
end)
