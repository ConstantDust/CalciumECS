ecs = require("CalciumECS")

ecs_world = ecs.world()

local exampleChatSystem = tiny.processingSystem()
exampleChatSystem.filter = tiny.requireAll("name", "msg")
function exampleChatSystem:process(e, dt)
    print(("%s says: %q."):format(e.name, e.msg))
end

local joe = {
    name = "Joe",
    msg = "I'm a plumber.",
    mass = 150,
    hairColor = "brown"
}

local bob = {
    name = "Bob",
    msg = "I need a plumber.",
    mass = 145,
    hairColor = "black"
}

ecs.add(ecs_world, bob, joe)

-- update calcium every tick
local lastTimeStep = client:getSystemTime() / 1000
events.RENDER:register(function ()
    local currentTimeStep = client:getSystemTime() / 1000
    local deltaTime = currentTimeStep - lastTimeStep
    ecs.update(ecs_world, deltaTime)
    lastTimeStep = currentTimeStep
end)
