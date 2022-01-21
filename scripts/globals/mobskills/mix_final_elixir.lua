-----------------------------------
-- Mix: Final Elixir - Restores all HP/MP to party members.
-- Used once per elixir donation. He will need a refill to use it again.
-----------------------------------
require("scripts/settings/main")
require("scripts/globals/status")
require("scripts/globals/mobskills")
-----------------------------------
local mobskill_object = {}

mobskill_object.onMobSkillCheck = function(target, mob, skill)
    return 0
end

mobskill_object.onMobWeaponSkill = function(target, mob, skill)

    return 0
end

return mobskill_object
