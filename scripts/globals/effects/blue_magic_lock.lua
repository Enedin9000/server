-----------------------------------
-- xi.effect.BLUE_MAGIC_LOCK
-----------------------------------
local effectObject = {}

effectObject.onEffectGain = function(target, effect)
    -- target:PrintToPlayer("Blue Magic Omerta in effect for one minute.", xi.msg.channel.SYSTEM_3, "")
    -- Not bad to have a message, but it shows every time a spell is set, so it's not practical
end

effectObject.onEffectTick = function(target, effect)
end

effectObject.onEffectLose = function(target, effect)
end

return effectObject