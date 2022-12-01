require("scripts/globals/status")
require("scripts/globals/magic")

-- The TP modifier
TPMOD_NONE = 0
TPMOD_CRITICAL = 1
TPMOD_DAMAGE = 2
TPMOD_ACC = 3
TPMOD_ATTACK = 4
TPMOD_DURATION = 5

INT_BASED = 1
CHR_BASED = 2
MND_BASED = 3

-----------------------------------
-- Utility functions below
-----------------------------------

-- Get alpha (level-dependent multiplier on WSC)
local function BlueGetAlpha(level)
    if level < 61 then
        return math.ceil(100 - (level / 6)) / 100
    elseif level <= 75 then
        return math.ceil(100 - (level - 40) / 2) / 100
    elseif level <= 99 then
        return 0.83
    end
end

-- Get WSC
local function BlueGetWsc(attacker, params)
    local wsc = (attacker:getStat(xi.mod.STR) * params.str_wsc + attacker:getStat(xi.mod.DEX) * params.dex_wsc +
        attacker:getStat(xi.mod.VIT) * params.vit_wsc + attacker:getStat(xi.mod.AGI) * params.agi_wsc +
        attacker:getStat(xi.mod.INT) * params.int_wsc + attacker:getStat(xi.mod.MND) * params.mnd_wsc +
        attacker:getStat(xi.mod.CHR) * params.chr_wsc) * BlueGetAlpha(attacker:getMainLvl())
    return wsc
end

-- Get cRatio
local function BluecRatio(ratio, atk_lvl, def_lvl)

    -- Apply level penalty
    local levelcor = 0
    if atk_lvl < def_lvl then
        levelcor = 0.05 * (def_lvl - atk_lvl)
    end
    ratio = ratio - levelcor

    -- Clamp
    ratio = utils.clamp(ratio,0,2)

    -- Obtain cRatiomin
    local cratiomin = 0
    if ratio < 1.25 then
        cratiomin = 1.2 * ratio - 0.5
    elseif ratio >= 1.25 and ratio <= 1.5 then
        cratiomin = 1
    elseif ratio > 1.5 and ratio <= 2 then
        cratiomin = 1.2 * ratio - 0.8
    end

    -- Obtain cRatiomax
    local cratiomax = 0
    if ratio < 0.5 then
        cratiomax = 0.4 + 1.2 * ratio
    elseif ratio <= 0.833 and ratio >= 0.5 then
        cratiomax = 1
    elseif ratio <= 2 and ratio > 0.833 then
        cratiomax = 1.2 * ratio
    end
    local cratio = {}
    if cratiomin < 0 then
        cratiomin = 0
    end

    -- Return data
    cratio[1] = cratiomin
    cratio[2] = cratiomax
    return cratio

end

-- Get the fTP multiplier (by applying 2 straight lines between ftp0-ftp1500 and ftp1500-ftp3000)
local function BluefTP(tp, ftp0, ftp1500, ftp3000)
    tp = utils.clamp(tp,0,3000)
    if tp >= 0 and tp < 1500 then
        return ftp0 + ((ftp1500 - ftp0) * (tp / 1500))
    elseif tp >= 1500 then
        return ftp1500 + ((ftp3000 - ftp1500) * ((tp - 1500) / 1500))
    else -- unreachable
        return 1
    end
end

-- Get fSTR
local function BluefSTR(dSTR)
    local fSTR2 = nil
    if dSTR >= 12 then
        fSTR2 = (dSTR + 4) / 2
    elseif dSTR >= 6 then
        fSTR2 = (dSTR + 6) / 2
    elseif dSTR >= 1 then
        fSTR2 = (dSTR + 7) / 2
    elseif dSTR >= -2 then
        fSTR2 = (dSTR + 8) / 2
    elseif dSTR >= -7 then
        fSTR2 = (dSTR + 9) / 2
    elseif dSTR >= -15 then
        fSTR2 = (dSTR + 10) / 2
    elseif dSTR >= -21 then
        fSTR2 = (dSTR + 12) / 2
    else
        fSTR2 = (dSTR + 13) / 2
    end
    return fSTR2
end

-- Get hitrate
local function BlueGetHitRate(attacker, target)
    local acc = attacker:getACC() + 2 * attacker:getMerit(xi.merit.PHYSICAL_POTENCY)
    local eva = target:getEVA()
    acc = acc + ((attacker:getMainLvl() - target:getMainLvl()) * 4)

    local hitrate = 75 + (acc - eva) / 2
    hitrate = hitrate / 100
    hitrate = utils.clamp(hitrate, 0.2, 0.95)

    --attacker:PrintToPlayer(string.format("Hitrate %s", hitrate))

    return hitrate
end

function BlueGetCorrelation(spellEcosystem, monsterEcosystem, merits)
    local effect = 0
    local weak = {
        [xi.ecosystem.BEAST] = xi.ecosystem.PLANTOID,
        [xi.ecosystem.LIZARD] = xi.ecosystem.BEAST,
        [xi.ecosystem.VERMIN] = xi.ecosystem.LIZARD,
        [xi.ecosystem.PLANTOID] = xi.ecosystem.VERMIN,
        [xi.ecosystem.BIRD] = xi.ecosystem.AMORPH,
        [xi.ecosystem.AQUAN] = xi.ecosystem.BIRD,
        [xi.ecosystem.AMORPH] = xi.ecosystem.AQUAN,
    }
    local strong = {
        [xi.ecosystem.BEAST] = xi.ecosystem.LIZARD,
        [xi.ecosystem.LIZARD] = xi.ecosystem.VERMIN,
        [xi.ecosystem.VERMIN] = xi.ecosystem.PLANTOID,
        [xi.ecosystem.PLANTOID] = xi.ecosystem.BEAST,
        [xi.ecosystem.BIRD] = xi.ecosystem.AQUAN,
        [xi.ecosystem.AQUAN] = xi.ecosystem.AMORPH,
        [xi.ecosystem.AMORPH] = xi.ecosystem.BIRD,
        [xi.ecosystem.UNDEAD] = xi.ecosystem.ARCANA,
        [xi.ecosystem.ARCANA] = xi.ecosystem.UNDEAD,
        [xi.ecosystem.DEMON] = xi.ecosystem.DRAGON,
        [xi.ecosystem.DRAGON] = xi.ecosystem.DEMON,
        [xi.ecosystem.LUMINIAN] = xi.ecosystem.LUMINION,
        [xi.ecosystem.LUMINION] = xi.ecosystem.LUMINIAN,
    }
    if weak[spellEcosystem] == monsterEcosystem then
        effect = -0.25
    elseif strong[spellEcosystem] == monsterEcosystem then
        effect = 0.25 + 0.01 * merits
    end
    return effect
end

-- Get the damage for a physical Blue Magic spell
function BluePhysicalSpell(caster, target, spell, params)

    -- TODO: Under Chain affinity?
    -- TODO: Under Efflux?
    -- TODO: Under Azure Lore.

    -----------------------
    -- Get final D value --
    -----------------------

    -- Initial D value
    local initialD = math.floor(caster:getSkillLevel(xi.skill.BLUE_MAGIC) * 0.11) * 2 + 3
    initialD = utils.clamp(initialD,0,params.duppercap)

    -- fSTR
    local fStr = BluefSTR(caster:getStat(xi.mod.STR) - target:getStat(xi.mod.VIT))
    if fStr > 22 then
        if params.ignorefstrcap == nil then -- Smite of Rage / Grand Slam don't have this cap applied
            fStr = 22
        end
    end

    -- Multiplier, bonus WSC
    local multiplier = 1
    local bonusWSC = 0

    -- BLU AF3 bonus (triples the base WSC when it procs)
    if caster:getMod(xi.mod.AUGMENT_BLU_MAGIC) > math.random(0, 99) then
        bonusWSC = 2
    end

    -- Chain Affinity -- TODO: add "Damage/Accuracy/Critical Hit Chance varies with TP"
    if caster:getStatusEffect(xi.effect.CHAIN_AFFINITY) then
        local tp = caster:getTP() + 100 * caster:getMerit(xi.merit.ENCHAINMENT) -- Total TP available
        tp = utils.clamp(tp,0,3000)
        multiplier = BluefTP(tp, params.multiplier, params.tp150, params.tp300)
        bonusWSC = bonusWSC + 1 -- Chain Affinity doubles base WSC
    end

    -- WSC
    local wsc = BlueGetWsc(caster, params)
    wsc = wsc + (wsc * bonusWSC) -- Bonus WSC from AF3/CA

    -- Monster correlation -- TODO: add Monster Correlation effect to Magus Keffiyeh and reference that effect here (adds another 0.02)
    local correlationMultiplier = BlueGetCorrelation(params.ecosystem, target:getSystem(), caster:getMerit(xi.merit.MONSTER_CORRELATION))

    -- Azure Lore
    if caster:getStatusEffect(xi.effect.AZURE_LORE) then
        multiplier = params.azuretp
    end

    -- Final D
    local finalD = math.floor(initialD + fStr + wsc)

    ----------------------------------------------
    -- Get the possible pDIF range and hit rate --
    ----------------------------------------------

    if params.offcratiomod == nil then -- For all spells except Cannonball, which uses a DEF mod
        params.offcratiomod = caster:getStat(xi.mod.ATT)
    end

    local cratio = BluecRatio(params.offcratiomod / target:getStat(xi.mod.DEF), caster:getMainLvl(), target:getMainLvl())
    local hitrate = BlueGetHitRate(caster, target)

    -------------------------
    -- Perform the attacks --
    -------------------------

    local hitsdone = 0
    local hitslanded = 0
    local finaldmg = 0

    while hitsdone < params.numhits do
        local chance = math.random()
        if chance <= hitrate then -- it hit
            -- TODO: Check for shadow absorbs. Right now the whole spell will be absorbed by one shadow before it even gets here.

            -- Generate a random pDIF between min and max
            local pdif = math.random(cratio[1] * 1000, cratio[2] * 1000)
            pdif = pdif / 1000

            -- Apply it to our final D
            if hitsdone == 0 then
                finaldmg = finaldmg + (finalD * (multiplier + correlationMultiplier) * pdif) -- first hit gets full multiplier
            else
                finaldmg = finaldmg + (finalD * (1 + correlationMultiplier) * pdif)
            end

            hitslanded = hitslanded + 1

            -- increment target's TP (100TP per hit landed)
            if finaldmg > 0 then
                target:addTP(100)
            end
        end

        hitsdone = hitsdone + 1
    end

    return finaldmg
end

-- Blue Magical type spells
function BlueMagicalSpell(caster, target, spell, params, statMod)
    local D = caster:getMainLvl() + 2

    if D > params.duppercap then
        D = params.duppercap
    end

    local st = BlueGetWsc(caster, params) -- According to Wiki ST is the same as WSC, essentially Blue mage spells that are magical use the dmg formula of Magical type Weapon skills

    if caster:hasStatusEffect(xi.effect.BURST_AFFINITY) then
        st = st * 2
    end

    local convergenceBonus = 1.0
    if caster:hasStatusEffect(xi.effect.CONVERGENCE) then
        local convergenceEffect = caster:getStatusEffect(xi.effect.CONVERGENCE)
        local convLvl = convergenceEffect:getPower()
        if convLvl == 1 then
            convergenceBonus = 1.05
        elseif convLvl == 2 then
            convergenceBonus = 1.1
        elseif convLvl == 3 then
            convergenceBonus = 1.15
        end
    end

    local statBonus = 0
    local dStat = 0 -- Please make sure to add an additional stat check if there is to be a spell that uses neither INT, MND, or CHR. None currently exist.
    if statMod == INT_BASED then -- Stat mod is INT
        dStat = caster:getStat(xi.mod.INT) - target:getStat(xi.mod.INT)
        statBonus = dStat * params.tMultiplier
    elseif statMod == CHR_BASED then -- Stat mod is CHR
        dStat = caster:getStat(xi.mod.CHR) - target:getStat(xi.mod.CHR)
        statBonus = dStat * params.tMultiplier
    elseif statMod == MND_BASED then -- Stat mod is MND
        dStat = caster:getStat(xi.mod.MND) - target:getStat(xi.mod.MND)
        statBonus = dStat * params.tMultiplier
    end

    D = ((D + st) * params.multiplier * convergenceBonus) + statBonus

    -- At this point according to wiki we apply standard magic attack calculations

    local magicAttack = 1.0
    local multTargetReduction = 1.0 -- TODO: Make this dynamically change, temp static till implemented.
    magicAttack = math.floor(D * multTargetReduction)

    local rparams = {}
    rparams.diff = dStat
    rparams.skillType = xi.skill.BLUE_MAGIC
    magicAttack = math.floor(magicAttack * applyResistance(caster, target, spell, rparams))

    local dmg = math.floor(addBonuses(caster, spell, target, magicAttack))

    caster:delStatusEffectSilent(xi.effect.BURST_AFFINITY)

    return dmg
end

function BlueFinalAdjustments(caster, target, spell, dmg, params)
    if dmg < 0 then
        dmg = 0
    end

    dmg = dmg * xi.settings.main.BLUE_POWER

    local attackType = params.attackType or xi.attackType.NONE
    local damageType = params.damageType or xi.damageType.NONE

    if attackType == xi.attackType.NONE then
        printf("BlueFinalAdjustments: spell id %d has attackType set to xi.attackType.NONE", spell:getID())
    end

    if damageType == xi.damageType.NONE then
        printf("BlueFinalAdjustments: spell id %d has damageType set to xi.damageType.NONE", spell:getID())
    end

    -- handle One For All, Liement
    if attackType == xi.attackType.MAGICAL then

        local targetMagicDamageAdjustment = xi.spells.damage.calculateTMDA(caster, target, damageType) -- Apply checks for Liement, MDT/MDTII/DT
        dmg = math.floor(dmg * targetMagicDamageAdjustment)
        if dmg < 0 then
            target:takeSpellDamage(caster, spell, dmg, attackType, damageType)
            -- TODO: verify Afflatus/enmity from absorb?
            return dmg
        end
        dmg = utils.oneforall(target, dmg)
    end

    -- Handle Phalanx
    if dmg > 0 then
        dmg = utils.clamp(dmg - target:getMod(xi.mod.PHALANX), 0, 99999)
    end

    -- handling stoneskin
    dmg = utils.stoneskin(target, dmg)

    target:takeSpellDamage(caster, spell, dmg, attackType, damageType)
    target:updateEnmityFromDamage(caster, dmg)
    target:handleAfflatusMiseryDamage(dmg)
    -- TP has already been dealt with.
    return dmg
end

-- Function to stagger duration of effects by using the resistance to change the value
-- Intend to render this obsolete, do a find once you've gone through all spells
function getBlueEffectDuration(caster, resist, effect)
    local duration = 0

    if resist == 0.125 then
        resist = 1
    elseif resist == 0.25 then
        resist = 2
    elseif resist == 0.5 then
        resist = 3
    else
        resist = 4
    end

    if effect == xi.effect.BIND then
        duration = math.random(0, 5) + resist * 5
    elseif effect == xi.effect.STUN then
        duration = math.random(2, 3) + resist
    elseif effect == xi.effect.WEIGHT then
        duration = math.random(20, 24) + resist * 9 -- 20-24
    elseif effect == xi.effect.PARALYSIS then
        duration = math.random(50, 60) + resist * 15 -- 50- 60
    elseif effect == xi.effect.SLOW then
        duration = math.random(60, 120) + resist * 15 -- 60- 120 -- Needs confirmation but capped max duration based on White Magic Spell Slow
    elseif effect == xi.effect.SILENCE then
        duration = math.random(60, 180) + resist * 15 -- 60- 180 -- Needs confirmation but capped max duration based on White Magic Spell Silence
    elseif effect == xi.effect.POISON then
        duration = math.random(20, 30) + resist * 9 -- 20-30 -- based on magic spell poison
    else
        duration = math.random(10,30) + resist * 8
    end

    return duration
end

--[[

+-------+
| NOTES |
+-------+

_____________
GENERAL NOTES

- Spell values (multiplier, TP, D, WSC, TP etc) are gotten from:
    - https://www.bg-wiki.com/ffxi/Calculating_Blue_Magic_Damage
    - https://ffxiclopedia.fandom.com/wiki/Calculating_Blue_Magic_Damage
    - BG-wiki spell pages
    - Blue Gartr threads with data, such as
        https://www.bluegartr.com/threads/37619-Blue-Mage-Best-thread-ever?p=5832112&viewfull=1#post5832112
        https://www.bluegartr.com/threads/37619-Blue-Mage-Best-thread-ever?p=5437135&viewfull=1#post5437135
        https://www.bluegartr.com/threads/107650-Random-Question-Thread-XXIV-Occupy-the-RQT?p=4906565&viewfull=1#post4906565
    - When values were absent, spell values were decided based on Blue Gartr threads and Wiki page discussions.

- Assumed INT as the main magic accuracy modifier for physical spells' additional effects (when no data was found).

____________________
SPELL-SPECIFIC NOTES

- Head Butt, Frypan and Tail Slap Stun will overwrite existing Stun. Blitzstrahl/Temporal Shift won't.

---------------------------
changes in blu_fixes branch
---------------------------

- Individual spell changes
    - Updated TP values. A lot of spells had lower TP values for 150/300/Azure, which doesnt't make sense.
    - Updated WSC values, though most were correct.
    - Added spell ecosystem.
    - Updated added effect values.
        - All physical spells now need to hit before the AE can kick in.
        - All physical spells with an AE get a resistance check for the AE.
        - Resistance now influences duration properly.
        - Decaying effects now work, such as DEX and VIT down.
        - Some spells had 0 duration.

- Physical Blue Magic spell changes:
    - Simplified some functions.
    - Added Physical Potency merits effect.
    - Added monster correlation effects, including merits.
    - Added Azure Lore effect on multiplier.

- General BLU changes:
    - Azure Lore will now allow Physical spells to always skillchain, and Magical spells to always magic burst.

- General changes:
    - Changed all (wrongly named) LUMORIAN and LUMORIAN_KILLER to LUMINIAN and LUMINIAN_KILLER

- TODOs
    - "Damage/Accuracy/Critical Hit Rate/Effect Duration varies with TP" is not implemented
    - Missed physical spells should not be 0 dmg, but there's currently no way to make spells "miss"
    - Sneak Attack / Trick Attack in combination with spells doesn't work atm
    - Add 75+ spells. I didn't bother personally since we're on a 75 server and I have no knowledge of these spells at all.

- END RESULT
    - Physical dmg: acc/att/modifiers
    - Physical AE: acc/bluemagicskill/macc/INT
    - Physical Potency = +2 acc per merit
    - Correlation = multiplier +- 0.25
    - Correlation = multiplier +0.01 per merit (only for strengths, not weaknesses)


CLEANUP*********************

- Getstats, put back
- Magic, remove prints

]]
