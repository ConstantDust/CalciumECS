-------------------------------------------------------------------------------
--  _____     __  __     ______     ______   __         ______     __  __    --
-- /\  __-.  /\ \/\ \   /\  ___\   /\__  _\ /\ \       /\  ___\   /\ \_\ \   --
-- \ \ \/\ \ \ \ \_\ \  \ \___  \  \/_/\ \/ \ \ \____  \ \  __\   \ \____ \  --
--  \ \____-  \ \_____\  \/\_____\    \ \_\  \ \_____\  \ \_____\  \/\_____\ --
--   \/____/   \/_____/   \/_____/     \/_/   \/_____/   \/_____/   \/_____/ --
-------------------------------------------------------------------------------
local calcium = {}

local calcium_manageEntities
local calcium_manageSystems

local calcium_addEntity
local calcium_addSystem
local calcium_add

local calcium_removeEntity
local calcium_removeSystem

local filterJoin
local filterBuildString

function calcium.requireAll(...) return filterJoin('', ' and ', ...) end
function calcium.requireAny(...) return filterJoin('', ' or ', ...) end
function calcium.rejectAll(...) return filterJoin('not', ' and ', ...) end
function calcium.rejectAny(...) return filterJoin('not', ' or ', ...) end
function calcium.filter(pattern)
    local state, value = pcall(filterBuildString, pattern)
    if state then return value else return nil, value end
end

local systemKey = {"SYS_KEY"}
local function isSystem(table) return table[systemKey] end

local function processingSystemUpdate(system, dt)
    local preProcess = system.preProcess
    local process = system.process
    local postProcess = system.postProcess

    if (preProcess) then preProcess(system, dt) end

    if (process) then
        if (system.nocache) then
            local entities = system.world.entities
            local filter = system.filter
            if (filter) then
                for i = 1, #entities do
                    local entity = entities[i]
                    if filter(system, entity) then
                        process(system, entity, dt)
                    end
                end
            end
        else
            local entities = system.entities
            for i = 1, #entities do
                process(system, entities[i], dt)
            end
        end
    end

    if (postProcess) then postProcess(system, dt) end
end

local function sortedSystemOnModify(system)
    local entities = system.entities
    local indices = system.indices
    local sortDelegate = system.sortDelegate
    if not sortDelegate then
        local compare = system.compare
        sortDelegate = function(e1, e2)
            return compare(system, e1, e2)
        end
        system.sortDelegate = sortDelegate
    end
    table.sort(entities, sortDelegate)
    for i = 1, #entities do
        indices[entities[i]] = i
    end
end

function calcium.system(table)
    table = table or {}
    table[systemKey] = true
    return table
end

function calcium.processingSystem(table)
    table = table or {}
    table[systemKey] = true
    table.update = processingSystemUpdate
    return table
end

function calcium.sortedSystem(table)
    table = table or {}
    table[systemKey] = true
    table.onModify = sortedSystemOnModify
    return table
end

function calcium.sortedProcessingSystem(table)
    table = table or {}
    table[systemKey] = true
    table.update = processingSystemUpdate
    table.onModify = sortedSystemOnModify
    return table
end

local worldMetaTable
function calcium.world(...)
    local ret = setmetatable({
        entityRemovalCache = {},
        dirtyEntities = {},
        systemsToAdd = {},
        systemsToRemove = {},
        entities = {},
        systems = {}
    }, worldMetaTable)

    calcium_add(ret, ...)
    calcium_manageSystems(ret)
    calcium_manageEntities(ret)

    return ret, ...
end

function calcium.addEntity(world, entity)
    local dirtyEntities = world.dirtyEntities
    dirtyEntities[#dirtyEntities + 1] = entity

    return entity
end
calcium_addEntity = calcium.addEntity

function calcium.addSystem(world, system)
    assert(system.world == nil, "System already belongs to a World.")

    local systemToAdd = world.systemsToAdd
    systemToAdd[#systemToAdd + 1] = system
    system.world = world

    return system
end
calcium_addSystem = calcium.addSystem

function calcium.add(world, ...)
    for i = 1, select("#", ...) do
        local obj = select(i, ...)
        if obj then
            if isSystem(obj) then calcium_addSystem(world, obj)
            else calcium_addEntity(world, obj) end
        end
    end
    return ...
end
calcium_add = calcium.add

function calcium.removeEntity(world, entity)
    local entityToRemove = world.entityRemovalCache
    entityToRemove[#entityToRemove + 1] = entity
    return entity
end
calcium_removeEntity = calcium.removeEntity

function calcium.removeSystem(world, system)
    assert(system.world == world, "System does not belong to this World.")
    local systemToRemove = world.systemsToRemove
    systemToRemove[#systemToRemove + 1] = system
    return system
end
calcium_removeSystem = calcium.removeSystem

function calcium.remove(world, ...)
    for i = 1, select("#", ...) do
        local obj = select(i, ...)

        if (obj) then
            if isSystem(obj) then calcium_removeSystem(world, obj)
            else calcium_removeEntity(world, obj) end
        end
    end
    return ...
end

function calcium_manageSystems(world)
    local systemToAdd, systemToRemove = world.systemsToAdd, world.systemsToRemove

    -- Early exit
    if (#systemToAdd == 0 and #systemToRemove == 0) then return end

    world.systemsToAdd = {}
    world.systemsToRemove = {}

    local worldEntityList = world.entities
    local systems = world.systems

    -- Remove Systems
    for i = 1, #systemToRemove do
        local system = systemToRemove[i]
        local id = system.id

        local onRemove = system.onRemove
        if (onRemove) and not system.nocache then
            local entityList = system.entities
            for j = 1, #entityList do
                onRemove(system, entityList[j])
            end
        end

        table.remove(systems, id)
        for j = id, #systems do
            systems[j].id = j
        end

        local onRemoveFromWorld = system.onRemoveFromWorld
        if (onRemoveFromWorld) then onRemoveFromWorld(system, world) end
        systemToRemove[i] = nil

        -- Clean up System
        system.world = nil
        system.entities = nil
        system.indices = nil
        system.id = nil
    end

    -- Add Systems
    for i = 1, #systemToAdd do
        local system = systemToAdd[i]
        if systems[system.id or 0] ~= system then
            if not system.nocache then
                system.entities = {}
                system.indices = {}
            end
            if system.active == nil then
                system.active = true
            end
            system.modified = true
            system.world = world
            local id = #systems + 1
            system.id = id
            systems[id] = system
            local onAddToWorld = system.onAddToWorld
            if onAddToWorld then
                onAddToWorld(system, world)
            end

            -- Try to add Entities
            if not system.nocache then
                local entityList = system.entities
                local entityIndices = system.indices
                local onAdd = system.onAdd
                local filter = system.filter
                if filter then
                    for j = 1, #worldEntityList do
                        local entity = worldEntityList[j]
                        if filter(system, entity) then
                            local entityId = #entityList + 1
                            entityList[entityId] = entity
                            entityIndices[entity] = entityId
                            if onAdd then
                                onAdd(system, entity)
                            end
                        end
                    end
                end
            end
        end
        systemToAdd[i] = nil
    end
end

function calcium_manageEntities(world)

    local entityToRemove = world.entityRemovalCache
    local dirtyEntities = world.dirtyEntities

    -- Early exit
    if #entityToRemove == 0 and #dirtyEntities == 0 then
        return
    end

    world.dirtyEntities = {}
    world.entityRemovalCache = {}

    local entities = world.entities
    local systems = world.systems

    -- Change Entities
    for i = 1, #dirtyEntities do
        local entity = dirtyEntities[i]
        -- Add if needed
        if not entities[entity] then
            local id = #entities + 1
            entities[entity] = id
            entities[id] = entity
        end
        for j = 1, #systems do
            local system = systems[j]
            if not system.nocache then
                local systemEntities = system.entities
                local systemIndicies = system.indices
                local id = systemIndicies[entity]
                local filter = system.filter
                if filter and filter(system, entity) then
                    if not id then
                        system.modified = true
                        id = #systemEntities + 1
                        systemEntities[id] = entity
                        systemIndicies[entity] = id
                        local onAdd = system.onAdd
                        if onAdd then
                            onAdd(system, entity)
                        end
                    end
                elseif id then
                    system.modified = true
                    local tmpEntity = systemEntities[#systemEntities]
                    systemEntities[id] = tmpEntity
                    systemIndicies[tmpEntity] = id
                    systemIndicies[entity] = nil
                    systemEntities[#systemEntities] = nil
                    local onRemove = system.onRemove
                    if onRemove then
                        onRemove(system, entity)
                    end
                end
            end
        end
        dirtyEntities[i] = nil
    end

    -- Remove Entities
    for i = 1, #entityToRemove do
        local entity = entityToRemove[i]
        entityToRemove[i] = nil
        local listId = entities[entity]
        if listId then
            -- Remove Entity from world state
            local lastEntity = entities[#entities]
            entities[lastEntity] = listId
            entities[entity] = nil
            entities[listId] = lastEntity
            entities[#entities] = nil
            -- Remove from cached systems
            for j = 1, #systems do
                local system = systems[j]
                if not system.nocache then
                    local systemEntities = system.entities
                    local systemIndicies = system.indices
                    local id = systemIndicies[entity]
                    if id then
                        system.modified = true
                        local tmpEntity = systemEntities[#systemEntities]
                        systemEntities[id] = tmpEntity
                        systemIndicies[tmpEntity] = id
                        systemIndicies[entity] = nil
                        systemEntities[#systemEntities] = nil
                        local onRemove = system.onRemove
                        if onRemove then
                            onRemove(system, entity)
                        end
                    end
                end
            end
        end
    end
end

-- Manages things marked for deletion or addition.
-- Do not call this every update.. it is expensive
function calcium.refresh(world)
    calcium_manageSystems(world)
    calcium_manageEntities(world)
    local systems = world.systems
    for i = #systems, 1, -1 do
        local system = systems[i]
        if system.active then
            local onModify = system.onModify
            if onModify and system.modified then
                onModify(system, 0)
            end
            system.modified = false
        end
    end
end

--- Updates the world by dt
function calcium.update(world, dt, filter)

    calcium_manageSystems(world)
    calcium_manageEntities(world)

    local systems = world.systems

    -- Iterate through Systems IN REVERSE ORDER
    for i = #systems, 1, -1 do
        local system = systems[i]
        if system.active then
            -- Call the modify callback on Systems that have been modified.
            local onModify = system.onModify
            if onModify and system.modified then
                onModify(system, dt)
            end
            local preWrap = system.preWrap
            if preWrap and ((not filter) or filter(world, system)) then
                preWrap(system, dt)
            end
        end
    end

    --  Iterate through Systems IN ORDER ( was broke before i remeber :[ )
    for i = 1, #systems do
        local system = systems[i]
        if system.active and ((not filter) or filter(world, system)) then

            -- Update Systems that have an update method (most Systems)
            local update = system.update
            if update then
                local interval = system.interval
                if interval then
                    local bufferedTime = (system.bufferedTime or 0) + dt
                    while bufferedTime >= interval do
                        bufferedTime = bufferedTime - interval
                        update(system, interval)
                    end
                    system.bufferedTime = bufferedTime
                else
                    update(system, dt)
                end
            end

            system.modified = false
        end
    end

    -- Iterate through Systems IN ORDER AGAIN
    for i = 1, #systems do
        local system = systems[i]
        local postWrap = system.postWrap
        if postWrap and system.active and ((not filter) or filter(world, system)) then
            postWrap(system, dt)
        end
    end

end

function calcium.clearEntities(world)
    local entities = world.entities
    for i = 1, #entities do
        calcium_removeEntity(world, entities[i])
    end
end
function calcium.clearSystems(world)
    local systems = world.systems
    for i = #systems, 1, -1 do
        calcium_removeSystem(world, systems[i])
    end
end

function calcium.setSystemId(world, system, id)
    calcium_manageSystems(world)
    local oldId = system.id
    local systems = world.systems

    if (id < 0) then id = #world.systems + 1 + id end

    table.remove(systems, oldId)
    table.insert(systems, id, system)

    for i = oldId, id, id >= oldId and 1 or -1 do
        systems[i].id = i
    end

    return oldId
end

-- Construct world metatable.
worldMetaTable = {
    __id = {
        add = calcium.add,
        addEntity = calcium.addEntity,
        addSystem = calcium.addSystem,
        remove = calcium.remove,
        removeEntity = calcium.removeEntity,
        removeSystem = calcium.removeSystem,
        refresh = calcium.refresh,
        update = calcium.update,
        clearEntities = calcium.clearEntities,
        clearSystems = calcium.clearSystems,
        setSystemId = calcium.setSystemId
    },
    __tostring = function()
        return "<calcium-ecs_World>"
    end
}

do
    local loadstring = loadstring or load

    local function getchr(c) return "\\" .. c:byte() end
    local function make_safe(text) return ("%q"):format(text):gsub('\n', 'n'):gsub("[\128-\255]", getchr) end

    local function filterJoinRaw(prefix, seperator, ...)
        local accum = {}
        local build = {}
        for i = 1, select('#', ...) do
            local item = select(i, ...)

            if type(item) == 'string' then
                accum[#accum + 1] = ("(e[%s] ~= nil)"):format(make_safe(item))
            elseif type(item) == 'function' then
                build[#build + 1] = ('local subfilter_%d_ = select(%d, ...)'):format(i, i)
                accum[#accum + 1] = ('(subfilter_%d_(system, e))'):format(i)
            else
                print('ERR: Filter must be a string or a filter function.')
            end

        end
        local source = ('%s\nreturn function(system, e) return %s(%s) end'):format(table.concat(build, '\n'), prefix,
            table.concat(accum, seperator))
        local loader, error = loadstring(source)
        if error then
            print('ERR:'.. (error))
        end
        return loader(...)
    end

    function filterJoin(...)
        local state, value = pcall(filterJoinRaw, ...)
        if state then return value else return nil, value end
    end

    local function buildPart(str)
        local accum = {}
        local subParts = {}

        str = str:gsub('%b()', function(p)
            subParts[#subParts + 1] = buildPart(p:sub(2, -2))
            return ('\255%d'):format(#subParts)
        end)

        for invert, part, sep in str:gmatch('(%!?)([^%|%&%!]+)([%|%&]?)') do
            if part:match('^\255%d+$') then
                local partId = tonumber(part:match(part:sub(2)))
                accum[#accum + 1] = ('%s(%s)'):format(invert == '' and '' or 'not', subParts[partId])
            else
                accum[#accum + 1] = ("(e[%s] %s nil)"):format(make_safe(part), invert == '' and '~=' or '==')
            end
            if (sep ~= '') then
                accum[#accum + 1] = (sep == '|' and ' or ' or ' and ')
            end
        end
        return table.concat(accum)
    end

    function filterBuildString(str)
        local source = ("return function(_, e) return %s end"):format(buildPart(str))
        local loader, error = loadstring(source)
        if error then
            print("ERR:".. error)
        end
        return loader()
    end
end

return calcium