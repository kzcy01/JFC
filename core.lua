-- JFC/core.lua | universe 10767621216 | v6
-- single panel, minimal design system, config presets, perf module
if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 10767621216 then return end

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local Http    = game:GetService("HttpService")
local UIS     = game:GetService("UserInputService")
local Lighting= game:GetService("Lighting")
local TS      = game:GetService("TeleportService")
local player  = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local R = RS:WaitForChild("Remotes")

for _, g in ipairs(playerGui:GetChildren()) do
    if g.Name == "JFC" or g.Name == "JFC_OSU" then pcall(function() g:Destroy() end) end
end

-- hot-reload guard: re-executing this file bumps the generation and all
-- old loop threads see the mismatch and exit instead of stacking.
getgenv().JFC_GEN = (getgenv().JFC_GEN or 0) + 1
local MYGEN = getgenv().JFC_GEN
local function alive() return MYGEN == getgenv().JFC_GEN end

-- ============ config ============
local CFG = {
    -- throw
    autoThrow = true, throwMode = "perfect", throwBurst = 3, throwInterval = 0.30, jitter = 0.08,
    -- training
    autoTrain = true, alignTol = 0.12,
    -- economy (on by request)
    autoCollect = true, collectEvery = 2,
    autoPlaceBest = true, placeEvery = 18,
    autoBuyWeight = true, weightEvery = 12,
    autoEquipBest = true,    -- equip only when a purchase is strictly better
    autoBuySpeed = true, speedEvery = 22,
    autoBuyTrail = true, trailEvery = 30,
    autoPetUpgrade = true, petEvery = 18,
    autoFuse = true, fuseEvery = 9, fuseBurst = 1,
    autoRedeem = true, redeemEvery = 60,
    -- off by default
    autoRebirth = true,
    autoWorld = true,
    worldEvery = 8,
    worldThreshold = 1e15,   -- power needed before the next world gate is attempted
    worldBurst = 8,          -- throws fired right before travelling
    autoPad = false,         -- DISABLED: snapping back with CFrame kills the player
    padWalk = false,         -- walk back instead of teleporting (safer, untested)
    autoJump = false,        -- one TP to the pad, then walk back when the wave pushes you
    autoSteer = false,       -- steer the lane toward good orbs (CFrame, bound after the game update)
    padSpeed = 60,           -- walk speed used while recovering
    padLeash = 14,           -- studs off-pad before it starts walking back
    padFailsBeforeSpeed = 2, -- walk-backs that fail in a row before buying speed
    watchdog = true, stallLimit = 90,
    rejoinEvery = 3600,      -- never auto-rejoin more often than this (seconds)
    -- perf
    perfProfile = "low",   -- off | low | max
    fpsCap = 60,
    flatWorld = true,      -- one solid colour, no textures
    suppressMessages = true, -- kill the red toast spam
    -- session
    autoResume = true,
    key = Enum.KeyCode.RightControl,
    uiKey = Enum.KeyCode.RightShift,
    running = true,
}

local SAVE = "JFC_v6.json"

local function saveCfg()
    local t = {}
    for k, v in pairs(CFG) do
        if type(v) ~= "userdata" then t[k] = v end
    end
    pcall(writefile, SAVE, Http:JSONEncode(t))
end

local function loadCfg()
if CFG.autoLane ~= nil then CFG.autoSteer = CFG.autoLane end
    local ok, raw = pcall(readfile, SAVE)
    if not (ok and type(raw) == "string" and #raw > 0) then return false end
    local ok2, t = pcall(Http.JSONDecode, Http, raw)
    if not (ok2 and type(t) == "table") then return false end
    for k, v in pairs(t) do
        if CFG[k] ~= nil and type(v) == type(CFG[k]) then CFG[k] = v end
    end
    return true
end
loadCfg()
if CFG.autoLane ~= nil then CFG.autoSteer = CFG.autoLane end

local PRESETS = {
    safe = { autoThrow = false, throwMode = "off", autoTrain = false, autoCollect = true, autoPlaceBest = true,
             autoBuyWeight = true, autoBuySpeed = true, autoBuyTrail = true, autoPetUpgrade = true,
             autoRebirth = false, autoWorld = false, watchdog = false, perfProfile = "off" },
    balanced = { autoThrow = true, throwMode = "perfect", autoTrain = true, autoCollect = true, autoPlaceBest = true,
             autoBuyWeight = true, autoBuySpeed = true, autoBuyTrail = true, autoPetUpgrade = true,
             autoRebirth = true, autoWorld = false, watchdog = true, perfProfile = "low" },
    max = { autoThrow = true, throwMode = "perfect", autoTrain = true, autoCollect = true, autoPlaceBest = true,
             autoBuyWeight = true, autoBuySpeed = true, autoBuyTrail = true, autoPetUpgrade = true,
             autoRebirth = true, autoWorld = true, watchdog = true, perfProfile = "max" },
}

local function applyPreset(name)
    local p = PRESETS[name]
    if not p then return false end
    for k, v in pairs(p) do if CFG[k] ~= nil and type(v) == type(CFG[k]) then CFG[k] = v end end
    saveCfg()
    return true
end

-- ============ state ============
local S = {}
local function A(n) return player:GetAttribute(n) end
function S.power() return tonumber(A("Strength")) or 0 end
function S.kick() return tonumber(A("KickPower")) or 0 end
function S.weight() return tonumber(A("Weight")) or 0 end
function S.cash() return tonumber(A("Cash")) or 0 end
function S.gems() return tonumber(A("Gems")) or 0 end
function S.reb() return tonumber(A("Rebirths")) or 0 end
function S.world() return tostring(A("World") or "Default") end
function S.lift() return tonumber(A("_LiftMult")) or 0 end
function S.ready() return A("_ProfileReady") == true end

local WORLDS = { Default="TechWorld", TechWorld="HauntedWorld", HauntedWorld="GodWorld", GodWorld="DemonWorld", DemonWorld="HellWorld" }
local WFLAG  = { TechWorld="_World2Unlocked", HauntedWorld="_World3Unlocked", GodWorld="_World4Unlocked", DemonWorld="_World5Unlocked", HellWorld="_World6Unlocked" }
local WIDX   = { TechWorld=2, HauntedWorld=3, GodWorld=4, DemonWorld=5, HellWorld=6 }
function S.nextWorld()
    local n = WORLDS[S.world()]
    if not n then return nil, false end
    return n, A(WFLAG[n]) == true
end

-- ============ helpers ============
local function fire(name, ...)
    local r = R:FindFirstChild(name)
    if not r or r:IsA("RemoteFunction") then return false end
    local a = table.pack(...)
    return pcall(function() r:FireServer(table.unpack(a, 1, a.n)) end)
end
local function frame(...)
    local node = playerGui
    for _, n in ipairs({ ... }) do node = node and node:FindFirstChild(n) end
    return node
end
local function press(btn)
    if not btn or not btn:IsA("GuiButton") then return false end
    local ok = pcall(firesignal, btn.Activated)
    if not ok then ok = pcall(firesignal, btn.MouseButton1Click) end
    return ok
end

local LOG = {}
local function log(m)
    table.insert(LOG, 1, os.date("%H:%M") .. "  " .. tostring(m))
    while #LOG > 40 do table.remove(LOG) end
end

-- ============ perf ============
local PERF = { applied = "off", removed = 0 }

local function setQuality(level)
    pcall(function() settings().Rendering.QualityLevel = level end)
end

local function sweepEffects()
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Smoke") or d:IsA("Fire")
            or d:IsA("Sparkles") or d:IsA("Explosion") or d:IsA("PointLight") or d:IsA("SpotLight") then
            if d.Enabled then pcall(function() d.Enabled = false end) n = n + 1 end
        end
    end
    return n
end

-- strip surface textures/decals: the single biggest draw-call cost in this scene
local function stripTextures()
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Decal") or d:IsA("Texture") then
            local ok, tr = pcall(function() return d.Transparency end)
            if ok and tr < 1 then
                if pcall(function() d.Transparency = 1 end) then n = n + 1 end
            end
        elseif d:IsA("SurfaceAppearance") then
            if pcall(function() d.AlphaMode = Enum.SurfaceAppearanceAlphaMode.Overlay end) then n = n + 1 end
        end
    end
    return n
end

-- flatten everything to one solid tone: no textures, no materials, no reflectance
local FLAT_COLOR = Color3.fromRGB(86, 96, 112)
local function flattenWorld()
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("MeshPart") then
            pcall(function()
                d.TextureID = ""
                d.Material = Enum.Material.Plastic
                d.Color = FLAT_COLOR
                d.Reflectance = 0
            end)
            local sa = d:FindFirstChildOfClass("SurfaceAppearance")
            if sa then pcall(function() sa:Destroy() end) end
            n = n + 1
        elseif d:IsA("BasePart") then
            pcall(function()
                d.Material = Enum.Material.Plastic
                d.Color = FLAT_COLOR
                d.Reflectance = 0
            end)
            n = n + 1
        end
    end
    return n
end

-- the red toast stack: 18 live labels at peak, all spawning in one container
-- kill post-processing + full-screen overlays: blur smears and the wave blur are pure cost
local function stripPost()
    local n = 0
    for _, d in ipairs(Lighting:GetChildren()) do
        if d:IsA("BlurEffect") or d:IsA("DepthOfFieldEffect") or d:IsA("SunRaysEffect")
            or d:IsA("BloomEffect") or d:IsA("ColorCorrectionEffect") then
            if pcall(function() d.Enabled = false end) then n = n + 1 end
        end
    end
    local pg = playerGui
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("ImageLabel") or d:IsA("Frame") then
            local nm = string.lower(d.Name)
            if (string.find(nm, "waveblur", 1, true) or string.find(nm, "blur", 1, true))
                and d.Visible then
                pcall(function() d.Visible = false end)
                n = n + 1
            end
        end
    end
    return n
end

local MSG = { killed = 0, roots = {} }
local function messageRoots()
    local pg = playerGui
    local roots = {}
    local game_ = pg:FindFirstChild("Game")
    local frames = game_ and game_:FindFirstChild("Frames")
    local notif = frames and frames:FindFirstChild("Notifications")
    if notif then roots[#roots + 1] = notif end
    for _, name in ipairs({ "GlobalBrainrotMessage", "PopupGate", "MilestonePrompt", "RespawnPrompt" }) do
        local g = pg:FindFirstChild(name)
        if g then roots[#roots + 1] = g end
    end
    return roots
end

function MSG.kill()
    local n = 0
    for _, root in ipairs(messageRoots()) do
        if root:IsA("ScreenGui") then
            if root.Enabled then pcall(function() root.Enabled = false end) end
        elseif root:IsA("GuiObject") then
            if root.Visible then pcall(function() root.Visible = false end) end
        end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("GuiObject") then
                pcall(function() d.Visible = false end)
                n = n + 1
            elseif d:IsA("ScreenGui") then
                pcall(function() d.Enabled = false end)
                n = n + 1
            end
        end
    end
    MSG.killed = MSG.killed + n
    return n
end

local hooked = false
function MSG.watch()
    MSG.kill()
    if not hooked then
        hooked = true
        local game_ = playerGui:FindFirstChild("Game")
        local frames = game_ and game_:FindFirstChild("Frames")
        local notif = frames and frames:FindFirstChild("Notifications")
        if notif then
            -- kill toasts the instant they spawn, before they paint
            notif.DescendantAdded:Connect(function(d)
                if CFG.suppressMessages and d:IsA("GuiObject") then
                    pcall(function() d.Visible = false end)
                end
            end)
        end
    end
    task.spawn(function()
        while alive() do
            if CFG.suppressMessages then MSG.kill() end
            task.wait(0.25)
        end
    end)
end

function PERF.apply(profile)
    CFG.perfProfile = profile
    if profile == "off" then
        setQuality(Enum.QualityLevel.Automatic)
        PERF.applied = "off"
        log("perf off")
        return
    end
    if profile == "low" then
        setQuality(Enum.QualityLevel.Level01)
        pcall(function() pcall(function() setfpscap(CFG.fpsCap) end) end)
        PERF.applied = "low"
        log("perf low")
        return
    end
    -- max
    setQuality(Enum.QualityLevel.Level01)
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 220
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.Outlines = false
    end)
    local removed = sweepEffects()
    local tex = stripTextures()
    local flat = 0
    if CFG.flatWorld then flat = flattenWorld() end
    local post = stripPost()
    local msgs = MSG.kill()
    pcall(function() setfpscap(240) end)
    PERF.removed = removed
    PERF.textures = tex
    PERF.flat = flat
    PERF.applied = "max"
    log("perf max fx " .. removed .. " tex " .. tex .. " flat " .. flat .. " post " .. post .. " msg " .. msgs)
end

-- ============ actions ============
local ACT = {}
local EQUIP_FIXED_AT = {}
local HITS = { throw=0, osu=0, collect=0, place=0, weight=0, speed=0, trail=0, pet=0, rebirth=0, world=0 }

function ACT.throw()
    fire("RequestKick", { tier = "Perfect" })
    HITS.throw = HITS.throw + 1
end

function ACT.osu()
    local ot = frame("OsuTrain")
    local root = ot and ot:FindFirstChild("Circles")
    if not root then return false end
    local live = false
    for _, node in ipairs(root:GetChildren()) do
        if node:IsA("GuiButton") and node.Visible then
            live = true
            local suffix = string.match(node.Name, "^Circle(.+)$")
            local ring = suffix and root:FindFirstChild("Ring" .. suffix)
            if ring then
                local bw, rw = node.AbsoluteSize.X, ring.AbsoluteSize.X
                if bw > 0 and rw > 0 and math.abs(rw - bw) / bw <= CFG.alignTol then
                    if press(node) then HITS.osu = HITS.osu + 1 end
                end
            end
        end
    end
    return live
end

function ACT.collect()
    fire("RequestBasePad", "Collect", true)
    fire("RequestCollect")
    HITS.collect = HITS.collect + 1
end

-- PlaceBest is the game's own valuation pass: it ranks held pets by the money
-- each one prints and drops the highest earners onto the base slots.
function ACT.placeBest()
    fire("BasePetsRequest", "PlaceBest")
    HITS.place = HITS.place + 1
end

local WMULT = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qa = 1e15, Qi = 1e18,
                Sp = 1e21, Sx = 1e21, S = 1e21, Oc = 1e27, No = 1e30, Dc = 1e33, p = 1e24 }
local function parseNum(s)
    local n, suf = string.match(tostring(s), "([%d%.]+)%s*([KMBTQaSpOxNocD]*)")
    if not n then return 0 end
    return (tonumber(n) or 0) * (WMULT[suf] or 1)
end

function ACT.buyWeight()
    -- server-truth weights: config gives exact StrengthGain/Price per item,
    -- SoldInWorld filters to this world's stock, and a passive state-sync
    -- listener tells us owned + equipped. no shop UI reading at all --
    -- the cards lie when the shop is closed and miss suffixes anyway.
    local okW, W = pcall(require, RS:FindFirstChild("WeightsConfig"))
    if not okW or type(W) ~= "table" or type(W.Weights) ~= "table" then return false end
    if WSTATE_REFRESH == nil then WSTATE_REFRESH = false end
    if not WSTATE_REFRESH then
        WSTATE_REFRESH = true
        local r = R:FindFirstChild("WeightShopStateSync")
        if r then
            r.OnClientEvent:Connect(function(s)
                if type(s) == "table" then
                    if type(s.owned) == "table" then WSTATE_OWNED = s.owned end
                    if s.equipped ~= nil then WSTATE_EQUIPPED = s.equipped end
                end
            end)
        end
    end
    if not WSTATE_OWNED then
        -- one no-op equip to make the server push a full state sync
        local r = R:FindFirstChild("RequestEquipWeight")
        if r then
            pcall(function() r:FireServer({ key = WSTATE_EQUIPPED or "Wooden Stick" }) end)
            task.wait(1.5)
        end
    end
    if not WSTATE_OWNED then return false end
    local world, cash = S.world(), S.cash()
    local buy, buyStr = nil, 0
    for name, e in pairs(W.Weights) do
        if type(e) == "table" and not WSTATE_OWNED[name] then
            local okSold, sold = pcall(function() return W.SoldInWorld(name, world) end)
            local str, price = tonumber(e.StrengthGain) or 0, tonumber(e.Price) or math.huge
            if okSold and sold and price <= cash and str > buyStr then
                buy, buyStr = name, str
            end
        end
    end
    local bought = false
    if buy then
        local r = R:FindFirstChild("RequestBuyWeight")
        if r and pcall(function() r:FireServer({ key = buy }) end) then
            bought = true
            HITS.weight = HITS.weight + 1
            log(string.format("buying %s (%.3g)", buy, buyStr))
        end
    end
    -- equip the strongest owned barbell. combo-gated (a swap wipes it)
    -- and latched (one press per power level, never repeats, never walks
    -- back down). server answers alreadyequipped on no-ops.
    if CFG.autoEquipBest and (tonumber(A("_RushCombo")) or 0) == 0 then
        local best, bestStr = nil, 0
        for name in pairs(WSTATE_OWNED) do
            local e = W.Weights[name]
            local str = (type(e) == "table" and tonumber(e.StrengthGain)) or 0
            if str > bestStr then best, bestStr = name, str end
        end
        EQUIP_LATCH = EQUIP_LATCH or 0
        if best and best ~= WSTATE_EQUIPPED and bestStr > EQUIP_LATCH then
            local r = R:FindFirstChild("RequestEquipWeight")
            if r and pcall(function() r:FireServer({ key = best }) end) then
                EQUIP_LATCH = bestStr
                WSTATE_EQUIPPED = best
                log(string.format("equip %s (%.3g)", best, bestStr))
                return true
            end
        end
    end
    return bought
end

function ACT.buySpeed()
    local fr = frame("Game", "Frames", "SpeedUI") or frame("Game", "Frames", "SpeedUpgrade")
    local n = 0
    if fr then
        for _, d in ipairs(fr:GetDescendants()) do
            if d:IsA("GuiButton") and d.Visible then
                local nm = string.lower(d.Name)
                if string.find(nm, "buy", 1, true) or string.find(nm, "upgrade", 1, true) then
                    if press(d) then n = n + 1 end
                end
            end
        end
    end
    if n == 0 then
        for i = 1, 4 do fire("RequestSpeedUpgrade", i) end
        n = 1
    end
    HITS.speed = HITS.speed + n
    return true
end

function ACT.buyTrail()
    local fr = frame("Game", "Frames", "TrailShop")
    if not fr then return false end
    local n = 0
    for _, d in ipairs(fr:GetDescendants()) do
        if d:IsA("GuiButton") and d.Visible then
            local nm = string.lower(d.Name)
            if string.find(nm, "buy", 1, true) or string.find(nm, "purchase", 1, true) then
                if press(d) then n = n + 1 end
            end
        end
    end
    HITS.trail = HITS.trail + n
    return n > 0
end

local FUSE_MACHINE = Vector3.new(85, 21, 43)
local FUSE_TRIP_UNTIL = 0

function ACT.fuse()
    -- fuse runs AT the machine (85,21,43): the server rejects remote
    -- fuses ("Walk up to the Fuse Machine") and rate-limits to ~1 per 6s
    -- ("The machine is still running"). so: one precise attempt per
    -- cycle, every 7s, weakest-first pair. auto-trips to the machine
    -- when far (pad loop yields via FUSE_TRIP_UNTIL), stays while chaining.
    local r = R:FindFirstChild("FuseGetPets")
    local fr = R:FindFirstChild("FuseRequest")
    if not (r and fr) then return 0 end
    local ok, pets = pcall(function() return r:InvokeServer() end)
    if not ok or type(pets) ~= "table" or #pets < 2 then return 0 end
    table.sort(pets, function(a, b) return (tonumber(a.stat) or 0) < (tonumber(b.stat) or 0) end)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    if (hrp.Position - FUSE_MACHINE).Magnitude > 14 then
        FUSE_TRIP_UNTIL = os.clock() + 25
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum.Jump = true end)
            task.wait(0.2)
            pcall(function() hum:MoveTo(FUSE_MACHINE) end)
        end
        return 0
    end
    local a, b = pets[1], pets[2]
    if not (a.uid and b.uid) then return 0 end
    -- cut the machine's charge-up visuals; pure client-side, server unaffected
    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name == "FuseMachine" then
                for _, c in ipairs(d:GetDescendants()) do
                    if c:IsA("ParticleEmitter") or c:IsA("Beam") or c:IsA("Trail") then
                        if c.Enabled then c.Enabled = false end
                    end
                end
                break
            end
        end
    end)
    local ok2, res = pcall(function() return fr:InvokeServer({ a.uid, b.uid }) end)
    if ok2 and type(res) == "table" and res.ok == true then
        FUSE_TRIP_UNTIL = os.clock() + 8
        HITS.fuse = (HITS.fuse or 0) + 1
        log("fused 1")
        return 1
    end
    -- "still running" = cooldown not expired yet: stay put, retry next cycle
    if ok2 and type(res) == "table" and string.find(tostring(res.message), "still running", 1, true) then
        FUSE_TRIP_UNTIL = os.clock() + 8
        return 0
    end
    return 0
end

local CODES_TRIED_FILE = "JFC_codes_tried.txt"
local CODES_TRIED = {}
do
    local ok, raw = pcall(readfile, CODES_TRIED_FILE)
    if ok and type(raw) == "string" then
        for line in string.gmatch(raw, "[^\r\n]+") do
            local c = line:gsub("^%s+", ""):gsub("%s+$", "")
            if #c > 0 then CODES_TRIED[string.lower(c)] = true end
        end
    end
end

function ACT.redeem(code)
    -- official promo codes only: plain string in -> {ok, message} out.
    -- each code is tried once ever (tracked in JFC_codes_tried.txt).
    local c = tostring(code or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #c == 0 then return false end
    if CODES_TRIED[string.lower(c)] then return false end
    CODES_TRIED[string.lower(c)] = true
    pcall(appendfile, CODES_TRIED_FILE, c .. "\n")
    local r = R:FindFirstChild("RedeemCode")
    if not r then log("redeem: no remote") return false end
    local ok, res = pcall(function() return r:InvokeServer(c) end)
    if ok and type(res) == "table" and res.ok == true then
        log("code " .. c .. ": " .. tostring(res.message or "claimed"))
        return true
    end
    log("code " .. c .. ": " .. tostring(type(res) == "table" and res.message or res))
    return false
end

function ACT.redeemFile()
    -- one code per line in JFC_codes.txt (Workspace root, # = comment).
    -- skips anything already tried; 0.6s between attempts.
    local ok, raw = pcall(readfile, "JFC_codes.txt")
    if not (ok and type(raw) == "string") then return 0 end
    local n = 0
    for line in string.gmatch(raw, "[^\r\n]+") do
        local c = line:gsub("^%s+", ""):gsub("%s+$", "")
        if #c > 0 and string.sub(c, 1, 1) ~= "#" and not CODES_TRIED[string.lower(c)] then
            if ACT.redeem(c) then n = n + 1 end
            task.wait(0.6)
        end
    end
    return n
end

function ACT.petUpgrade()
    -- walk every SlotUpgradeSign on my plot, read its price, pair it with the pet's
    -- pay, then upgrade the richest non-MAX slots first.
    local plots = workspace:FindFirstChild("Plots")
    local plotName = "Plot" .. tostring(A("BasePlot") or "")
    local mine = plots and (plots:FindFirstChild(plotName) or plots:FindFirstChild("Plot" .. tostring(A("BasePlot"))))
    if not mine then
        if CFG.autoPlaceBest then fire("BasePetsRequest", "PlaceBest") end
        HITS.pet = HITS.pet + 1
        return 0
    end

    -- rank slots two ways: the payout shown on the slot, and (when that reads $0)
    -- the pet's own stat from the server, strongest first.
    local pay = {}
    local slotList = {}
    local floors = mine:FindFirstChild("Floors")
    if floors then
        for _, fl in ipairs(floors:GetChildren()) do
            local sm = fl:FindFirstChild("SlotModels")
            if sm then
                for _, slot in ipairs(sm:GetChildren()) do
                    slotList[#slotList + 1] = slot
                    local sg = slot:FindFirstChild("SurfaceGui", true)
                    local tl = sg and sg:FindFirstChild("TextLabel", true)
                    if tl then
                        pay[slot] = parseNum(tl.Text)
                    end
                end
            end
        end
    end

    -- if the slot labels are empty, use the server's pet stats instead
    local anyPay = false
    for _, v in pairs(pay) do if v > 0 then anyPay = true break end end
    if not anyPay then
        local fr = R:FindFirstChild("FuseGetPets")
        if fr then
            local okp, pets = pcall(function() return fr:InvokeServer() end)
            if okp and type(pets) == "table" and #pets > 0 then
                table.sort(pets, function(a, b) return (tonumber(a.stat) or 0) > (tonumber(b.stat) or 0) end)
                table.sort(slotList, function(a, b) return a.Name < b.Name end)
                for i, slot in ipairs(slotList) do
                    pay[slot] = tonumber(pets[i] and pets[i].stat) or 0
                end
            end
        end
    end

    -- gather every upgrade sign
    local signs = {}
    for _, d in ipairs(mine:GetDescendants()) do
        if d.Name == "SlotUpgradeSign" or (d:IsA("SurfaceGui") and d.Parent and d.Parent.Name == "SlotUpgradeSign") then
            local priceLbl = d:FindFirstChild("PriceLabel", true)
            local btn = d:FindFirstChild("Button", true)
            if btn and priceLbl then
                local maxed = string.find(string.upper(priceLbl.Text or ""), "MAX", 1, true) ~= nil
                -- attach the payout of the nearest slot model
                local bestPay, bestD = 0, nil
                local part = d:IsA("BasePart") and d or (d.Parent and d.Parent:IsA("BasePart") and d.Parent or nil)
                if part then
                    for slot, v in pairs(pay) do
                        local sp = slot:FindFirstChild("Model") and slot.Model:FindFirstChild("Slot1")
                        local pos = (sp and sp:IsA("BasePart") and sp.Position) or nil
                        if pos then
                            local dist = (pos - part.Position).Magnitude
                            if bestD == nil or dist < bestD then bestD, bestPay = dist, v end
                        end
                    end
                end
                signs[#signs + 1] = { btn = btn, price = priceLbl.Text, maxed = maxed, pay = bestPay }
            end
        end
    end

    table.sort(signs, function(a, b) return (a.pay or 0) > (b.pay or 0) end)

    local pressed, skipped = 0, 0
    for _, sg in ipairs(signs) do
        if sg.maxed then
            skipped = skipped + 1
        else
            if pcall(firesignal, sg.btn.Activated) then pressed = pressed + 1 end
        end
    end

    if CFG.autoPlaceBest then fire("BasePetsRequest", "PlaceBest") end
    HITS.pet = HITS.pet + 1
    if pressed > 0 then log("upgraded " .. pressed .. " slots") end
    return pressed, #signs, skipped
end

function ACT.rebirth()
    local reb = frame("Game", "Frames", "Rebirth")
    if reb then
        local auto = reb:FindFirstChild("Header") and reb.Header:FindFirstChild("AutoRebirthButton")
        if auto then
            local tl = auto:FindFirstChildOfClass("TextLabel")
            local t = string.upper(tostring(tl and tl.Text or auto.Text or ""))
            if string.find(t, "OFF", 1, true) then press(auto) end
        end
    end
    fire("RequestRebirth", { mode = "rebirth" })
    HITS.rebirth = HITS.rebirth + 1
end

function ACT.travel(key)
    local frames = frame("Game", "Frames")
    local tp = frames and frames:FindFirstChild("WorldTp")
    local idx = WIDX[key]
    if tp and idx then
        tp.Visible = true
        task.wait(0.35)
        local body = tp:FindFirstChild("Body")
        local dests = body and body:FindFirstChild("Destinations")
        local list = dests and dests:FindFirstChild("List")
        local dest = list and list:FindFirstChild("Dest_world" .. idx)
        local ok = dest and press(dest)
        task.wait(0.6)
        tp.Visible = false
        if ok then HITS.world = HITS.world + 1 return key end
    end
    fire("RequestTopHubTeleport")
    return false
end

-- jump ferry: walks to the pad, waits for the game's own launch, ferries
-- back after landing. zero charge presses (proven useless live -- only real
-- input or game auto-jump can charge), zero manual teleports, zero speed
-- writes. movement is MoveTo + Jump only; returns use the game's own
-- Tp Home button. the Jump Zone button is NEVER pressed: proven live to
-- launch instead of recalling, which flings you around.
local PAD = { last = 0, snaps = 0, fails = 0, tpDone = false,
              state = "TO_PAD", since = os.clock(), loops = 0,
              retLast = nil, retStuck = 0, lastTp = 0, lastAuto = 0,
              offdir = 0, manualUntil = 0, cmdDir = nil, dead = false }
local PAD_POS = Vector3.new(207.25, 23.8, 104.95)

function PAD.coords()
    local raw = tostring(A("_HubTp_jumpzone") or "")
    local n = {}
    for v in string.gmatch(raw, "-?[%d%.]+") do n[#n + 1] = tonumber(v) end
    if #n < 3 then return PAD_POS end
    return Vector3.new(n[1], n[2] + 4, n[3])
end

function PAD.reset()
    PAD.tpDone = false
    PAD.fails = 0
    PAD.snaps = 0
    PAD.state, PAD.since = "TO_PAD", os.clock()
    PAD.retLast, PAD.retStuck = nil, 0
    PAD.offdir, PAD.manualUntil, PAD.cmdDir = 0, 0, nil
    PAD.dead = false
end

local function distXZ(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- water scan: slow swim zones on the pad corridor are routed around,
-- never through. rescan periodically -- the world streams in after boot.
local JFWATER, JFWATER_SCANNED = {}, 0
local function scanJumpWater()
    JFWATER = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and string.lower(d.Name) == "water" then
            local p, s = d.Position, d.Size
            JFWATER[#JFWATER + 1] = {
                x1 = math.min(p.X - s.X / 2, p.X + s.X / 2) - 4,
                x2 = math.max(p.X - s.X / 2, p.X + s.X / 2) + 4,
                z1 = math.min(p.Z - s.Z / 2, p.Z + s.Z / 2) - 4,
                z2 = math.max(p.Z - s.Z / 2, p.Z + s.Z / 2) + 4,
            }
        end
    end
    JFWATER_SCANNED = os.clock()
    return #JFWATER
end

local function inJumpWater(x, z)
    for _, b in ipairs(JFWATER) do
        if x > b.x1 and x < b.x2 and z > b.z1 and z < b.z2 then return b end
    end
    return nil
end

local JFPFS = game:GetService("PathfindingService")
local JFPATH = { legs = nil, legIdx = 1, dest = nil, lastComp = 0 }

local function jumpWalkTo(target)
    if PAD.manualUntil and os.clock() < PAD.manualUntil then return true end
    if os.clock() < (FUSE_TRIP_UNTIL or 0) then return true end
    local c = player.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not (c and hum) then return false end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    -- water first: nearest edge + jump-spam; currents can't stalemate it
    do
        if #JFWATER == 0 or os.clock() - JFWATER_SCANNED > 60 then scanJumpWater() end
        local hx, hz = hrp.Position.X, hrp.Position.Z
        local box = inJumpWater(hx, hz)
        if box then
            local edgeX = (math.abs(hx - box.x1) < math.abs(hx - box.x2)) and (box.x1 - 2) or (box.x2 + 2)
            pcall(function() hum.Jump = true end)
            pcall(function() hum:MoveTo(Vector3.new(edgeX, hrp.Position.Y, hz)) end)
            PAD.cmdDir = { X = (edgeX > hx) and 1 or -1, Z = 0 }
            return true
        end
    end
    if not JFPATH.legs or not JFPATH.dest or (JFPATH.dest - target).Magnitude > 6
        or os.clock() - JFPATH.lastComp > 20 or (JFPATH.legIdx or 1) > #JFPATH.legs then
        local legs = { target }
        local hx, hz = hrp.Position.X, hrp.Position.Z
        for _, b in ipairs(JFWATER) do
            local function crosses(x1, z1, x2, z2)
                for _, t in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
                    local x, z = x1 + (x2 - x1) * t, z1 + (z2 - z1) * t
                    if x > b.x1 and x < b.x2 and z > b.z1 and z < b.z2 then return true end
                end
                return false
            end
            if crosses(hx, hz, target.X, target.Z) then
                local edgeX = (math.abs(hx - b.x1) < math.abs(hx - b.x2)) and (b.x1 - 2) or (b.x2 + 2)
                local cornerZ = (math.abs(hz - b.z1) < math.abs(hz - b.z2)) and (b.z1 - 2) or (b.z2 + 2)
                legs = { Vector3.new(edgeX, hrp.Position.Y, hz),
                         Vector3.new(edgeX, hrp.Position.Y, cornerZ), target }
                break
            end
        end
        JFPATH.legs, JFPATH.legIdx, JFPATH.dest, JFPATH.lastComp = legs, 1, target, os.clock()
    end
    local legs, li = JFPATH.legs, JFPATH.legIdx or 1
    while li <= #legs and (legs[li] - hrp.Position).Magnitude < 6 do li = li + 1 end
    JFPATH.legIdx = li
    if li > #legs then
        pcall(function() hum:MoveTo(target) end)
        return true
    end
    local leg = legs[li]
    local ok, p = pcall(function()
        local np = JFPFS:CreatePath({ AgentRadius = 2, AgentHeight = 5,
            AgentCanJump = true, AgentCanClimb = false })
        np:ComputeAsync(hrp.Position, leg)
        return np
    end)
    if ok and p and p.Status == Enum.PathStatus.Success then
        for _, wp in ipairs(p:GetWaypoints()) do
            if (wp.Position - hrp.Position).Magnitude > 5 then
                if wp.Action == Enum.PathWaypointAction.Jump then
                    pcall(function() hum.Jump = true end)
                end
                pcall(function() hum:MoveTo(wp.Position) end)
                do
                    local dx, dz = wp.Position.X - hrp.Position.X, wp.Position.Z - hrp.Position.Z
                    local m = math.sqrt(dx * dx + dz * dz)
                    if m > 0.5 then PAD.cmdDir = { X = dx / m, Z = dz / m } end
                end
                return true
            end
        end
    end
    pcall(function() hum:MoveTo(leg) end)
    do
        local dx, dz = leg.X - hrp.Position.X, leg.Z - hrp.Position.Z
        local m = math.sqrt(dx * dx + dz * dz)
        if m > 0.5 then PAD.cmdDir = { X = dx / m, Z = dz / m } end
    end
    return true
end

-- Tp Home: the game's own one-shot return button. needs no held input,
-- so a single synthetic press works (proven live: 371m in one press).
local function jumpTpHome()
    if PAD.manualUntil and os.clock() < PAD.manualUntil then return false end
    if os.clock() < (FUSE_TRIP_UNTIL or 0) then return false end
    if os.clock() - (PAD.lastTp or 0) < 10 then return false end
    local hud = frame("Game", "HUD", "HUDFrame")
    local tp = hud and hud:FindFirstChild("TpHome")
    if not (tp and tp.Visible) then return false end
    local cc = tp:FindFirstChild("ClickCatcher")
    if not (cc and cc:IsA("GuiButton")) then return false end
    PAD.lastTp = os.clock()
    local ok = pcall(firesignal, cc.MouseButton1Down)
    if not ok then pcall(firesignal, cc.Activated) end
    return true
end

-- popup sweeper: gift / trade / invite prompts steal focus and stall the
-- run. decline or close them the moment any becomes visible.
local function sweepJumpPopups()
    local frames = frame("Game", "Frames")
    if not frames then return end
    local gift = frames:FindFirstChild("GiftFrame")
    if gift and gift.Visible then
        for _, n in ipairs({ "Decline", "CloseButton" }) do
            local b = gift:FindFirstChild(n, true)
            if b and b:IsA("GuiButton") and b.Visible then
                if pcall(firesignal, b.MouseButton1Click) then log("dismissed gift popup") end
                break
            end
        end
    end
    local trade = frames:FindFirstChild("TradeRequestFrame")
    if trade and trade.Visible then
        for _, n in ipairs({ "CancelButton", "ExitButton" }) do
            local b = trade:FindFirstChild(n, true)
            if b and b:IsA("GuiButton") and b.Visible then
                if pcall(firesignal, b.MouseButton1Click) then log("dismissed trade popup") end
                break
            end
        end
    end
    local inv = frames:FindFirstChild("InviteFrame")
    if inv and inv.Visible then
        local b = inv:FindFirstChild("CloseButton", true)
        if b and b:IsA("GuiButton") and b.Visible then
            if pcall(firesignal, b.MouseButton1Click) then log("dismissed invite popup") end
        end
    end
end

-- fuse reveal: the Result card pops after every fuse and sits until
-- claimed. "Nice" claims + closes, "Again" re-fuses into cooldown.
-- tap Nice the moment it shows so the screen never waits on it.
local function sweepFuseReveal()
    local fg = playerGui and playerGui:FindFirstChild("FuseMachineGui")
    local res = fg and fg:FindFirstChild("Result")
    if not (res and res.Visible) then return end
    for _, n in ipairs({ "Nice", "Again" }) do
        local b = res:FindFirstChild(n)
        if b and b:IsA("GuiButton") and b.Visible then
            if press(b) then log("claimed fuse reveal") end
            return
        end
    end
end

-- jump pad: never moves the player. it only reacts when the game shows the jump
-- meter, which it signals by relabelling KickButton to "JUMP!".
function PAD.meterActive()
    local hud = frame("Game", "HUD", "HUDFrame")
    local kb = hud and hud:FindFirstChild("KickButton")
    if not kb then return nil end
    local tl = kb:FindFirstChildOfClass("TextLabel")
    local txt = string.upper(tostring(tl and tl.Text or ""))
    return string.find(txt, "JUMP", 1, true) ~= nil, kb
end

function PAD.hold()
    -- retired: synthetic charge presses were proven useless live (bar frozen
    -- through Click, Down-hold and VirtualUser). the game itself launches
    -- (auto-jump or your hold); this only watches.
    return "idle"
end

local function padLoop()
    while alive() do
        if CFG.running and CFG.autoJump then
            sweepJumpPopups()
            local c = player.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            if not (c and hum and hrp) then
                PAD.dead = true
                task.wait(1)
            else
                if PAD.dead then PAD.dead = false PAD.reset() end
                local pos = hrp.Position
                local pad = PAD.coords() or PAD_POS
                -- manual-drive detection: fast movement against our command
                -- means your finger is on the keys: yield so we never fight.
                -- skipped in water, where currents (not fingers) push back.
                do
                    local vel = hrp.AssemblyLinearVelocity
                    local sp = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
                    local wet = inJumpWater(pos.X, pos.Z) ~= nil
                    if sp > 10 and PAD.cmdDir and not wet then
                        local dot = (vel.X * PAD.cmdDir.X + vel.Z * PAD.cmdDir.Z) / sp
                        if dot < 0.5 then PAD.offdir = (PAD.offdir or 0) + 1
                        else PAD.offdir = 0 end
                        if (PAD.offdir or 0) >= 6 then
                            PAD.offdir = 0
                            PAD.manualUntil = os.clock() + 20
                            log("you drive, I'll wait")
                        end
                    else
                        PAD.offdir = 0
                    end
                end
                if PAD.manualUntil and os.clock() < PAD.manualUntil then
                    task.wait(0.5)
                elseif os.clock() - PAD.since > 45 then
                    PAD.reset()
                elseif PAD.state == "TO_PAD" then
                    local d = distXZ(pos, pad)
                    if d > 60 then
                        if jumpTpHome() then
                            log("Tp Home pressed")
                            task.wait(2)
                        else
                            jumpWalkTo(pad)
                        end
                    else
                        jumpWalkTo(pad)
                    end
                    if distXZ(pos, pad) <= 9 then
                        PAD.loops = PAD.loops + 1
                        HITS.jump = (HITS.jump or 0) + 1
                        PAD.state, PAD.since = "ON_PAD", os.clock()
                        log("on jump pad (loop " .. PAD.loops .. ")")
                    end
                elseif PAD.state == "ON_PAD" then
                    if distXZ(pos, pad) > 15 then
                        PAD.state, PAD.since = "TO_PAD", os.clock()
                    else
                        jumpWalkTo(pad)
                        local auto = player:GetAttribute("_AutoKick")
                        if not auto then
                            if os.clock() - (PAD.lastAuto or 0) > 5 then
                                PAD.lastAuto = os.clock()
                                local hud = frame("Game", "HUD", "HUDFrame")
                                local ak = hud and hud:FindFirstChild("AutoKickButton")
                                if ak and ak:IsA("GuiButton") then
                                    pcall(firesignal, ak.MouseButton1Click)
                                end
                                log("enabling auto-jump")
                            end
                        end
                        if distXZ(pos, pad) > 40 or pos.Y > pad.Y + 40 then
                            PAD.state, PAD.since = "AIRBORNE", os.clock()
                            log("launched!")
                        end
                    end
                elseif PAD.state == "AIRBORNE" then
                    if distXZ(pos, pad) > 40 then
                        PAD.state, PAD.since = "RIDING", os.clock()
                    elseif os.clock() - PAD.since > 12 then
                        PAD.state, PAD.since = "TO_PAD", os.clock()
                    end
                elseif PAD.state == "RIDING" then
                    local floored = hum.FloorMaterial ~= Enum.Material.Air
                    if (floored and os.clock() - PAD.since > 3) or pos.Y < 60 then
                        PAD.state, PAD.since = "CHEST", os.clock()
                    elseif os.clock() - PAD.since > 40 then
                        PAD.state, PAD.since = "CHEST", os.clock()
                    end
                elseif PAD.state == "CHEST" then
                    if os.clock() - PAD.since > 2.5 then
                        PAD.state, PAD.since = "RETURN", os.clock()
                    end
                elseif PAD.state == "RETURN" then
                    local d = distXZ(pos, pad)
                    if d > 60 then
                        if jumpTpHome() then
                            log("Tp Home pressed")
                            task.wait(2)
                        else
                            jumpWalkTo(pad)
                        end
                    else
                        jumpWalkTo(pad)
                    end
                    if d <= 9 then
                        PAD.state, PAD.since = "TO_PAD", os.clock()
                    end
                end
                task.wait(0.3)
            end
        else
            PAD.tpDone = false
            task.wait(1.0)
        end
    end
end

-- lane runner: steer left/right toward green/blue orbs, away from red
local LANE = { target = nil, seen = 0, picks = 0, last = 0 }

local function orbText(part)
    local bb = part:FindFirstChildOfClass("BillboardGui") or part:FindFirstChildOfClass("SurfaceGui")
    if not bb then return nil end
    local txt = ""
    for _, x in ipairs(bb:GetDescendants()) do
        if x:IsA("TextLabel") and x.Text ~= "" then txt = txt .. " " .. x.Text end
    end
    if txt == "" then return nil end
    return txt
end

-- good: contains a "+" or a multiplier >= 1. bad: x0.x, minus, or trap wording
local function scoreOrb(txt, col)
    local t = string.lower(txt)
    if string.find(t, "trap", 1, true) or string.find(t, "damage", 1, true) or string.find(t, "curse", 1, true) then
        return -1
    end
    local mul = string.match(t, "x%s*(%d+%.?%d*)")
    if mul then
        local v = tonumber(mul) or 1
        return v >= 1 and v or -1
    end
    if string.find(t, "%+") then return 1 end
    -- colour fallback: red = avoid, green/blue = take
    if col then
        local r, g, b = col.R, col.G, col.B
        if r > 0.55 and g < 0.35 and b < 0.35 then return -1 end
        if g > 0.5 or b > 0.55 then return 1 end
    end
    return nil
end

function LANE.pick()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local pos = hrp.Position
    local best, bestScore, bestDz = nil, -9, -1e9
    local avoid = {}
    LANE.lastOrbs = 0
    -- scan descendants, not just children: orbs can live inside folders
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") and not d:IsDescendantOf(char) then
            local v = d.Position - pos
            if v.Z < 8 and v.Z > -260 and math.abs(v.X) < 130 and math.abs(v.Y) < 40 then
                local bb = d:FindFirstChildOfClass("BillboardGui")
                local sg = d:FindFirstChildOfClass("SurfaceGui")
                if bb or sg then
                    local txt = orbText(d) or ""
                    local s = scoreOrb(txt, d.Color)
                    if s then
                        LANE.lastOrbs = LANE.lastOrbs + 1
                        if s < 0 then
                            avoid[#avoid + 1] = d.Position.X
                        elseif s > bestScore or (s == bestScore and v.Z > bestDz) then
                            bestScore, bestDz, best = s, v.Z, d.Position.X
                        end
                    end
                end
            end
        end
    end
    if best then return best, avoid, pos end
    return nil, avoid, pos
end

function LANE.steer()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end
    local tx, avoid, pos = LANE.pick()
    if not tx then return end
    -- if a bad orb is nearly on our X, bias away from it
    for _, ax in ipairs(avoid) do
        if math.abs(tx - ax) < 12 then
            tx = tx + (tx >= ax and 16 or -16)
        end
    end
    local goal = Vector3.new(tx, pos.Y, pos.Z - 45)
    pcall(function()
        hum.WalkSpeed = math.max(hum.WalkSpeed, 60)
        hum:MoveTo(goal)
    end)
    LANE.picks = LANE.picks + 1
    LANE.target = tx
end

function LANE.publish()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local tx, avoid, pos = LANE.pick()
    LANE.target = tx
    local payload = string.format('{"on":%s,"x":%.2f,"t":%.2f,"orbs":%d,"avoid":%d}',
        tostring(CFG.running and CFG.autoSteer and tx ~= nil),
        pos.X, tx or pos.X, LANE.lastOrbs or 0, #(avoid or {}))
    pcall(writefile, "lanetarget.json", payload)
end

-- direct CFrame steering bound AFTER the game's own update, so ours wins the frame
local RUN = game:GetService("RunService")
local steerBound = false

function LANE.bind()
    if steerBound then return end
    steerBound = true
    RUN:BindToRenderStep("JFC_steer", Enum.RenderPriority.Camera.Value + 25, function()
        if not alive() then
            pcall(function() RUN:UnbindFromRenderStep("JFC_steer") end)
            return
        end
        if not (CFG.running and CFG.autoSteer) then return end
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local tx = LANE.target
        if not tx then return end
        local dx = tx - hrp.Position.X
        if math.abs(dx) < 2 then return end
        local step = math.clamp(dx, -10, 10)
        pcall(function()
            hrp.CFrame = hrp.CFrame + Vector3.new(step, 0, 0)
        end)
        LANE.picks = (LANE.picks or 0) + 1
    end)
end

local function laneLoop()
    LANE.bind()
    while alive() do
        if CFG.running and CFG.autoSteer then
            LANE.publish()
            task.wait(0.08)
        else
            LANE.target = nil
            pcall(writefile, "lanetarget.json", '{"on":false,"x":0,"t":0,"orbs":0,"avoid":0}')
            task.wait(0.4)
        end
    end
end

-- try every steering method, keep the one that actually moves X
local LANE_TRY = { mode = 1, lastX = 0, tested = 0 }
local LANE_MODES = { "moveto", "walkspeed", "jumppower", "click-left-right" }

local function laneProbe()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end
    local x0 = hrp.Position.X
    local mode = LANE_MODES[LANE_TRY.mode] or "moveto"
    local tx = LANE.target or (x0 + 20)
    local dir = tx > x0 and 1 or -1

    if mode == "moveto" then
        hum:MoveTo(Vector3.new(x0 + dir * 30, hrp.Position.Y, hrp.Position.Z - 40))
    elseif mode == "walkspeed" then
        hum.WalkSpeed = 90
        hum:Move(Vector3.new(dir, 0, -0.8), false)
    elseif mode == "jumppower" then
        hum.JumpPower = 120
        hum.Jump = true
        hum:Move(Vector3.new(dir, 0, 0), false)
    else
        local vu = game:GetService("VirtualUser")
        local cam = workspace.CurrentCamera
        local vp = cam.ViewportSize
        local pt = Vector2.new(dir > 0 and vp.X * 0.68 or vp.X * 0.32, vp.Y * 0.78)
        pcall(function() vu:ClickButton1(pt) end)
    end

    task.wait(0.7)
    local x1 = hrp.Position.X
    local moved = math.abs(x1 - x0)
    if moved > 3 then
        log(string.format("lane mode '%s' works (moved %.0f)", mode, moved))
    else
        LANE_TRY.mode = (LANE_TRY.mode % #LANE_MODES) + 1
        LANE_TRY.tested = LANE_TRY.tested + 1
        if LANE_TRY.tested % #LANE_MODES == 0 then
            log("lane: no mode moved X yet, cycling")
        end
    end
end

function ACT.resume()    pcall(function()
        local s = readfile("JFC_core.lua")
        if s then queue_on_teleport(s) end
    end)
    fire("RequestSetSetting", { key = "AutoRejoin", value = "true" })
end

function ACT.hardReset(why)
    local now = os.time()
    if now - (LAST_RESET or 0) < (CFG.rejoinEvery or 3600) then
        log("rejoin blocked (" .. tostring((CFG.rejoinEvery or 3600) - (now - (LAST_RESET or 0))) .. "s left)")
        return
    end
    LAST_RESET = now
    log("reset " .. tostring(why))
    task.wait(0.8)
    pcall(function() TS:Teleport(game.PlaceId, player) end)
end

-- ============ loops ============
local thr = { i = CFG.throwInterval, stall = 0 }
local L = { rebirth=0, world=0, collect=0, place=0, weight=0, speed=0, trail=0, pet=0, save=0 }

local function throwLoop()
    while alive() do
        if not CFG.running or not CFG.autoThrow or CFG.throwMode == "off" or not S.ready() then
            task.wait(0.4)
        else
            local before = S.power()
            local n = 0
            while n < math.max(1, math.floor(CFG.throwBurst)) do
                ACT.throw()
                n = n + 1
                task.wait(math.max(0.05, thr.i + (math.random() * 2 - 1) * CFG.jitter))
            end
            if S.power() > before then
                thr.stall = 0
                thr.i = math.max(CFG.throwInterval, thr.i * 0.93)
            else
                thr.stall = thr.stall + 1
                if thr.stall >= 3 then thr.stall = 0 thr.i = math.min(4, thr.i * 1.3) end
            end
        end
    end
end

local function trainLoop()
    local last = 0
    while alive() do
        if CFG.running and CFG.autoTrain and S.ready() then
            local live = ACT.osu()
            if not live and os.clock() - last > 1.2 then
                last = os.clock()
                local hud = frame("Game", "HUD", "HUDFrame")
                local kb = hud and hud:FindFirstChild("KickButton")
                if kb then press(kb) end
            end
            task.wait(0.02)
        else
            task.wait(0.3)
        end
    end
end

local function mainLoop()
    while alive() do
        if CFG.running and S.ready() then
            local t = os.clock()
            if CFG.autoWorld then
                local nxt, open = S.nextWorld()
                if nxt and t - L.world > CFG.worldEvery then
                    local power = S.power()
                    local armed = open or (power >= CFG.worldThreshold)
                    if armed then
                        L.world = t
                        -- burst of perfect throws: clears the gate before the hop
                        local burst = math.max(1, math.floor(CFG.worldBurst))
                        for i = 1, burst do
                            ACT.throw()
                            task.wait(0.16)
                        end
                        local r = ACT.travel(nxt)
                        if r then
                            log(string.format("world %s | %.3g >= %.3g", r, power, CFG.worldThreshold))
                        else
                            log("world blocked " .. nxt)
                        end
                    end
                end
            end
            if CFG.autoRebirth and t - L.rebirth > 45 then
                L.rebirth = t
                -- rebirth re-rolls equipment and kills the combo, so it waits its turn
                if (tonumber(A("_RushCombo")) or 0) <= 0 then
                    ACT.rebirth()
                end
            end
            if CFG.autoCollect and t - L.collect > CFG.collectEvery then L.collect = t ACT.collect() end
            if CFG.autoPlaceBest and t - L.place > CFG.placeEvery then L.place = t ACT.placeBest() end
            if CFG.autoBuyWeight and t - L.weight > CFG.weightEvery then
                L.weight = t
                if ACT.buyWeight() then log("weight") end
            end
            if CFG.autoBuyTrail and t - L.trail > CFG.trailEvery then
                L.trail = t
                if ACT.buyTrail() then log("trail") end
            end
            if CFG.autoBuySpeed and t - L.speed > CFG.speedEvery then L.speed = t ACT.buySpeed() end
            if CFG.autoPetUpgrade and t - L.pet > CFG.petEvery then L.pet = t ACT.petUpgrade() end
            if CFG.autoFuse and t - (L.fuse or 0) > CFG.fuseEvery then
                L.fuse = t
                local n = ACT.fuse()
                if n and n > 0 then log("fused " .. n) end
            end
            if CFG.autoRedeem and t - (L.redeem or 0) > CFG.redeemEvery then
                L.redeem = t
                ACT.redeemFile()
            end
            sweepFuseReveal()
            if t - L.save > 30 then L.save = t saveCfg() end
        end
        task.wait(0.4)
    end
end

local watch = { p = 0, tick = os.clock(), pps = 0, last = os.clock() }
local function watchdogLoop()
    while alive() do
        task.wait(5)
        if CFG.watchdog and CFG.running then
            local p, now = S.power(), os.clock()
            local dt = now - watch.last
            if dt > 0 then
                watch.pps = (p - watch.p) / dt
                watch.last, watch.p = now, p
            end
            if not S.ready() then
                if now - watch.tick > 45 then ACT.hardReset("profile") end
            elseif p > 0 and math.abs(watch.pps) < 1 and now - watch.tick > CFG.stallLimit then
                ACT.hardReset("stalled")
                watch.tick = now
            elseif math.abs(watch.pps) >= 1 then
                watch.tick = now
            end
        end
    end
end

-- ============ design tokens ============
local T = {
    bg      = Color3.fromRGB(12, 14, 18),
    panel   = Color3.fromRGB(16, 19, 24),
    raised  = Color3.fromRGB(22, 26, 33),
    line    = Color3.fromRGB(32, 38, 48),
    text    = Color3.fromRGB(226, 232, 240),
    dim     = Color3.fromRGB(120, 132, 148),
    accent  = Color3.fromRGB(74, 222, 128),
    warn    = Color3.fromRGB(248, 180, 80),
    radius  = 6,
    pad     = 10,
    rowH    = 26,
    font    = Enum.Font.GothamMedium,
    fontMono= Enum.Font.Code,
}

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or T.radius)
    c.Parent = obj
end
local function hairline(obj, col, tr)
    local s = Instance.new("UIStroke")
    s.Color = col or T.line
    s.Transparency = tr or 0
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

-- ============ gui ============
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "JFC", false, 9999
pcall(function() if protectgui then protectgui(gui) end end)
gui.Parent = playerGui

local ROOT = Instance.new("Frame")
ROOT.Name = "Main"
ROOT.Size = UDim2.fromOffset(392, 372)
ROOT.Position = UDim2.fromOffset(22, 84)
ROOT.BackgroundColor3 = T.panel
ROOT.BorderSizePixel = 0
ROOT.Active = true
ROOT.Parent = gui
corner(ROOT, 8)
hairline(ROOT, T.line, 0)

-- header
local HEAD = Instance.new("Frame")
HEAD.Size = UDim2.new(1, 0, 0, 34)
HEAD.BackgroundTransparency = 1
HEAD.Parent = ROOT

local MARK = Instance.new("Frame")
MARK.Size = UDim2.fromOffset(3, 14)
MARK.Position = UDim2.fromOffset(12, 10)
MARK.BackgroundColor3 = T.accent
MARK.BorderSizePixel = 0
MARK.Parent = HEAD
corner(MARK, 2)

local NAME = Instance.new("TextLabel")
NAME.Position = UDim2.fromOffset(23, 8)
NAME.Size = UDim2.fromOffset(120, 18)
NAME.BackgroundTransparency = 1
NAME.Font, NAME.TextSize = T.font, 12
NAME.TextColor3 = T.text
NAME.TextXAlignment = Enum.TextXAlignment.Left
NAME.Text = "JFC"
NAME.Parent = HEAD

local STATE = Instance.new("TextLabel")
STATE.Position = UDim2.fromOffset(50, 9)
STATE.Size = UDim2.fromOffset(70, 16)
STATE.BackgroundTransparency = 1
STATE.Font, STATE.TextSize = T.fontMono, 10
STATE.TextColor3 = T.accent
STATE.TextXAlignment = Enum.TextXAlignment.Left
STATE.Text = "run"
STATE.Parent = HEAD

local function headBtn(txt, x, w, fn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, 20)
    b.Position = UDim2.fromOffset(x, 7)
    b.BackgroundColor3 = T.raised
    b.BorderSizePixel = 0
    b.Font, b.TextSize = T.fontMono, 10
    b.TextColor3 = T.dim
    b.Text = txt
    b.AutoButtonColor = false
    b.Parent = HEAD
    corner(b, 5)
    b.MouseEnter:Connect(function() b.TextColor3 = T.text end)
    b.MouseLeave:Connect(function() b.TextColor3 = T.dim end)
    b.MouseButton1Click:Connect(function() fn(b) end)
    return b
end

local BTN_SAVE  = headBtn("save", 288, 34, function() saveCfg() log("saved") end)
local BTN_FOLD  = headBtn("-", 326, 22, function() end)
local BTN_HIDE  = headBtn("x", 352, 22, function() gui.Enabled = false end)

-- segmented tabs
local TABS = Instance.new("Frame")
TABS.Position = UDim2.fromOffset(10, 34)
TABS.Size = UDim2.new(1, -20, 0, 26)
TABS.BackgroundColor3 = T.bg
TABS.BorderSizePixel = 0
TABS.Parent = ROOT
corner(TABS, 6)

local pages, tabBtns, activeTab = {}, {}, nil

local function makeTab(name, width, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(width, -4, 1, -4)
    b.Position = UDim2.fromOffset(x, 2)
    b.BackgroundColor3 = T.bg
    b.BorderSizePixel = 0
    b.Font, b.TextSize = T.font, 11
    b.TextColor3 = T.dim
    b.Text = name
    b.AutoButtonColor = false
    b.Parent = TABS
    corner(b, 5)
    b.MouseButton1Click:Connect(function()
        for n, p in pairs(pages) do p.Visible = (n == name) end
        for n, t in pairs(tabBtns) do
            t.BackgroundColor3 = (n == name) and T.raised or T.bg
            t.TextColor3 = (n == name) and T.text or T.dim
        end
        activeTab = name
    end)
    tabBtns[name] = b
    return b
end

local BODY = Instance.new("Frame")
BODY.Position = UDim2.fromOffset(0, 62)
BODY.Size = UDim2.new(1, 0, 1, -62)
BODY.BackgroundTransparency = 1
BODY.Parent = ROOT

local function makePage(name)
    local p = Instance.new("ScrollingFrame")
    p.Name = name
    p.Size = UDim2.new(1, -20, 1, -34)
    p.Position = UDim2.fromOffset(10, 6)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 2
    p.ScrollBarImageColor3 = T.line
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.Visible = false
    p.Parent = BODY
    p:SetAttribute("cursor", 0)
    pages[name] = p
    return p
end

-- manual vertical stack: deterministic, no UIListLayout reflow quirks
local function stack(page, obj, h)
    local y = page:GetAttribute("cursor") or 0
    obj.Position = UDim2.fromOffset(0, y)
    obj.Size = UDim2.new(1, 0, 0, h)
    page:SetAttribute("cursor", y + h + 6)
    page.CanvasSize = UDim2.new(0, 0, 0, y + h + 14)
    return obj
end

local function sectionLabel(parent, text)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font, l.TextSize = T.font, 10
    l.TextColor3 = T.dim
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = string.upper(text)
    l.Parent = parent
    stack(parent, l, 14)
    return l
end

-- switch row: label left, pill right
local function switchRow(parent, label, key, onChange)
    local row = Instance.new("Frame")
    row.BackgroundColor3 = T.bg
    row.BorderSizePixel = 0
    row.Parent = parent
    stack(parent, row, T.rowH)
    corner(row, 5)

    local lbl = Instance.new("TextLabel")
    lbl.Position = UDim2.fromOffset(9, 0)
    lbl.Size = UDim2.new(1, -62, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font, lbl.TextSize = T.font, 11
    lbl.TextColor3 = T.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = label
    lbl.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.fromOffset(30, 16)
    track.Position = UDim2.new(1, -38, 0.5, -8)
    track.BackgroundColor3 = T.line
    track.BorderSizePixel = 0
    track.Parent = row
    corner(track, 8)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.Position = UDim2.fromOffset(2, 2)
    knob.BackgroundColor3 = T.dim
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 6)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = row

    local function paint()
        local on = CFG[key] == true
        track.BackgroundColor3 = on and T.accent or T.line
        knob.Position = UDim2.fromOffset(on and 16 or 2, 2)
        knob.BackgroundColor3 = on and T.bg or T.dim
        lbl.TextColor3 = on and T.text or T.dim
    end
    btn.MouseButton1Click:Connect(function()
        CFG[key] = not (CFG[key] == true)
        paint()
        log(label .. (CFG[key] and " on" or " off"))
        if onChange then onChange(CFG[key]) end
    end)
    paint()
    row:SetAttribute("Key", key)
    row:SetAttribute("Paint", true)
    return { row = row, paint = paint }
end

local function buttonRow(parent, items)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Parent = parent
    stack(parent, row, 24)
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0, 6)
    l.Parent = row
    for _, it in ipairs(items) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(it[2] or 78, 24)
        b.BackgroundColor3 = T.raised
        b.BorderSizePixel = 0
        b.Font, b.TextSize = T.font, 11
        b.TextColor3 = T.dim
        b.Text = it[1]
        b.AutoButtonColor = false
        b.Parent = row
        corner(b, 5)
        b.MouseEnter:Connect(function() b.TextColor3 = T.text end)
        b.MouseLeave:Connect(function() b.TextColor3 = T.dim end)
        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(it[3])
            log(it[1] .. (ok and " ok" or (" err")))
            if not ok then warn("[JFC] " .. tostring(err)) end
        end)
    end
    return row
end

-- code row: textbox left, redeem button right
local CODEBOX = nil
local function codeRow(parent)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Parent = parent
    stack(parent, row, 24)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -84, 1, 0)
    box.BackgroundColor3 = T.raised
    box.BorderSizePixel = 0
    box.Font, box.TextSize = T.font, 11
    box.TextColor3 = T.text
    box.PlaceholderText = "paste code..."
    box.Text = ""
    box.ClearTextOnFocus = false
    box.Parent = row
    corner(box, 5)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(78, 24)
    b.Position = UDim2.new(1, -78, 0, 0)
    b.BackgroundColor3 = T.raised
    b.BorderSizePixel = 0
    b.Font, b.TextSize = T.font, 11
    b.TextColor3 = T.dim
    b.Text = "redeem"
    b.AutoButtonColor = false
    b.Parent = row
    corner(b, 5)
    b.MouseButton1Click:Connect(function()
        local c = tostring(box.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #c > 0 then ACT.redeem(c) end
    end)
    CODEBOX = box
    return row
end

-- pages
makeTab("auto",  0.28, 0)
makeTab("shops", 0.28, 0)
makeTab("perf",  0.22, 0)
makeTab("cfg",   0.22, 0)
tabBtns["auto"].Position = UDim2.new(0, 2, 0, 2)
tabBtns["shops"].Position = UDim2.new(0.27, 2, 0, 2)
tabBtns["perf"].Position = UDim2.new(0.54, 2, 0, 2)
tabBtns["cfg"].Position = UDim2.new(0.76, 2, 0, 2)

makePage("auto"); makePage("shops"); makePage("perf"); makePage("cfg")

do
    local p = pages["auto"]
    sectionLabel(p, "training")
    switchRow(p, "auto perfect kick", "autoThrow", function(on) CFG.throwMode = on and "perfect" or "off" end)
    switchRow(p, "auto tap circles", "autoTrain")
    switchRow(p, "auto jump pad", "autoJump", function(on)
        if on then
            PAD.reset()
            log("auto jump armed")
        else
            log("auto jump off")
        end
    end)
    switchRow(p, "auto rebirth", "autoRebirth")
    sectionLabel(p, "economy")
    switchRow(p, "auto collect cash", "autoCollect")
    switchRow(p, "auto place best pets", "autoPlaceBest")
    buttonRow(p, { {"throw x5", 72, function() for i=1,5 do ACT.throw() end end},
                   {"collect", 66, ACT.collect},
                   {"place", 62, ACT.placeBest},
                   {"rebirth", 66, ACT.rebirth} })
end

do
    local p = pages["shops"]
    sectionLabel(p, "autobuy")
    switchRow(p, "auto buy weights", "autoBuyWeight")
    switchRow(p, "auto equip best", "autoEquipBest")
    switchRow(p, "auto buy speed", "autoBuySpeed")
    switchRow(p, "auto buy trails", "autoBuyTrail")
    switchRow(p, "auto upgrade pets", "autoPetUpgrade")
    switchRow(p, "auto fuse pets", "autoFuse")
    sectionLabel(p, "buy now")
    buttonRow(p, { {"weights", 74, function() ACT.buyWeight() end},
                   {"speed", 62, function() ACT.buySpeed() end},
                   {"trails", 62, function() ACT.buyTrail() end},
                   {"pets", 54, function() ACT.petUpgrade() end},
                   {"fuse", 54, function() local n = ACT.fuse(); log("fused " .. tostring(n)) end} })
    sectionLabel(p, "codes")
    codeRow(p)
    buttonRow(p, { {"redeem file", 96, function() local n = ACT.redeemFile(); log("codes claimed " .. n) end} })
    switchRow(p, "auto redeem file", "autoRedeem")
end

do
    local p = pages["perf"]
    sectionLabel(p, "graphics")
    buttonRow(p, { {"low", 62, function() PERF.apply("low") end},
                   {"max fps", 70, function() PERF.apply("max") end},
                   {"off", 54, function() PERF.apply("off") end} })
    sectionLabel(p, "fps cap")
    buttonRow(p, { {"30", 40, function() CFG.fpsCap = 30 pcall(function() setfpscap(30) end) log("cap 30") end},
                   {"60", 40, function() CFG.fpsCap = 60 pcall(function() setfpscap(60) end) log("cap 60") end},
                   {"144", 46, function() CFG.fpsCap = 144 pcall(function() setfpscap(144) end) log("cap 144") end},
                   {"240", 46, function() CFG.fpsCap = 240 pcall(function() setfpscap(240) end) log("cap 240") end} })
    sectionLabel(p, "world")
    switchRow(p, "auto next world", "autoWorld")
    switchRow(p, "auto rejoin if stuck", "watchdog")
    buttonRow(p, { {"speed +10", 70, function()
                        CFG.padSpeed = math.min(400, CFG.padSpeed + 10)
                        log("pad speed " .. CFG.padSpeed)
                   end},
                   {"leash -4", 66, function()
                        CFG.padLeash = math.max(6, CFG.padLeash - 4)
                        log("leash " .. CFG.padLeash)
                   end},
                   {"retp pad", 68, function()
                        PAD.reset()
                        log("tp re-armed for next check")
                   end} })    buttonRow(p, { {"gate /10", 66, function()
                        CFG.worldThreshold = CFG.worldThreshold / 10
                        log("gate " .. string.format("%.2g", CFG.worldThreshold))
                   end},
                   {"gate x10", 66, function()
                        CFG.worldThreshold = CFG.worldThreshold * 10
                        log("gate " .. string.format("%.2g", CFG.worldThreshold))
                   end},
                   {"hop now", 68, function()
                        local nxt = S.nextWorld()
                        if nxt then
                            for i = 1, CFG.worldBurst do ACT.throw() end
                            log("-> " .. tostring(ACT.travel(nxt)))
                        end
                   end} })
    sectionLabel(p, "look")
    switchRow(p, "flat colours", "flatWorld", function(on)
        if on then flattenWorld() end
    end)
    switchRow(p, "hide red toasts", "suppressMessages", function(on)
        if on then MSG.kill() end
    end)
end

do
    local p = pages["cfg"]
    sectionLabel(p, "presets")
    buttonRow(p, { {"safe", 60, function() applyPreset("safe") end},
                   {"balanced", 78, function() applyPreset("balanced") end},
                   {"max", 54, function() applyPreset("max") end} })
    sectionLabel(p, "config")
    buttonRow(p, { {"save", 60, saveCfg},
                   {"load", 60, function() if loadCfg() then log("loaded") end end},
                   {"reset", 62, function()
                        pcall(function() if isfile(SAVE) then delfile(SAVE) end end)
                        log("config cleared")
                   end} })
    sectionLabel(p, "session")
    buttonRow(p, { {"resume", 66, ACT.resume},
                   {"rejoin", 66, function() ACT.hardReset("manual") end} })
end

-- status footer
local FOOT = Instance.new("Frame")
FOOT.Position = UDim2.new(0, 10, 1, -30)
FOOT.Size = UDim2.new(1, -20, 0, 22)
FOOT.BackgroundTransparency = 1
FOOT.Parent = ROOT

local STAT = Instance.new("TextLabel")
STAT.Size = UDim2.new(1, 0, 0, 12)
STAT.BackgroundTransparency = 1
STAT.Font, STAT.TextSize = T.fontMono, 9
STAT.TextColor3 = T.dim
STAT.TextXAlignment = Enum.TextXAlignment.Left
STAT.Text = ""
STAT.Parent = FOOT

local LOGB = Instance.new("TextLabel")
LOGB.Position = UDim2.fromOffset(0, 12)
LOGB.Size = UDim2.new(1, 0, 0, 10)
LOGB.BackgroundTransparency = 1
LOGB.Font, LOGB.TextSize = T.fontMono, 9
LOGB.TextColor3 = T.line
LOGB.TextXAlignment = Enum.TextXAlignment.Left
LOGB.Text = ""
LOGB.Parent = FOOT

-- resize grip
local GRIP = Instance.new("TextButton")
GRIP.Size = UDim2.fromOffset(14, 14)
GRIP.Position = UDim2.new(1, -18, 1, -18)
GRIP.BackgroundTransparency = 1
GRIP.Text = ""
GRIP.Parent = ROOT

local GRIP_DOT = Instance.new("Frame")
GRIP_DOT.Size = UDim2.fromOffset(6, 6)
GRIP_DOT.Position = UDim2.new(0.5, -3, 0.5, -3)
GRIP_DOT.BackgroundColor3 = T.line
GRIP_DOT.BorderSizePixel = 0
GRIP_DOT.Parent = GRIP
corner(GRIP_DOT, 3)

-- ============ interaction ============
local drag, dragStart, startPos = false, nil, nil
HEAD.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        drag, dragStart, startPos = true, i.Position, ROOT.Position
    end
end)

local rsz, rszStart, rszSize = false, nil, nil
GRIP.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        rsz, rszStart, rszSize = true, i.Position, ROOT.AbsoluteSize
    end
end)

UIS.InputChanged:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    if drag then
        local d = i.Position - dragStart
        ROOT.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
    elseif rsz then
        local d = i.Position - rszStart
        ROOT.Size = UDim2.fromOffset(math.clamp(rszSize.X + d.X, 320, 760), math.clamp(rszSize.Y + d.Y, 200, 760))
    end
end)

UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag, rsz = false, false end
end)

local folded = false
BTN_FOLD.MouseButton1Click:Connect(function()
    folded = not folded
    TABS.Visible = not folded
    BODY.Visible = not folded
    FOOT.Visible = not folded
    GRIP.Visible = not folded
    ROOT.Size = UDim2.fromOffset(ROOT.AbsoluteSize.X, folded and 34 or 372)
    BTN_FOLD.Text = folded and "+" or "-"
end)

if not getgenv().JFC_KEYS then
getgenv().JFC_KEYS = true
UIS.InputBegan:Connect(function(i, processed)
    if processed then return end
    if i.KeyCode == Enum.KeyCode.Escape then
        -- marks an intentional quit so the watchdog lets the game stay closed
        pcall(writefile, "JFC_QUIT", tostring(os.time()))
        return
    end
    if i.KeyCode == CFG.uiKey then
        gui.Enabled = not gui.Enabled
        return
    end
    if i.KeyCode == CFG.key then
        CFG.running = not CFG.running
        log(CFG.running and "resumed" or "paused")
    end
end)
end

local function repaintAll()
    for _, page in pairs(pages) do
        for _, row in ipairs(page:GetChildren()) do
            if row:IsA("Frame") and row:GetAttribute("Paint") then
                local key = row:GetAttribute("Key")
                local on = CFG[key] == true
                local track = row:FindFirstChild("Frame")
                local lbl = row:FindFirstChild("TextLabel")
                if track then
                    track.BackgroundColor3 = on and T.accent or T.line
                    local knob = track:FindFirstChild("Frame")
                    if knob then
                        knob.Position = UDim2.fromOffset(on and 16 or 2, 2)
                        knob.BackgroundColor3 = on and T.bg or T.dim
                    end
                end
                if lbl then lbl.TextColor3 = on and T.text or T.dim end
            end
        end
    end
end

local function fmt(n)
    local a = math.abs(n)
    local function scaled(v, suffix)
        if v >= 1000 then return string.format("%.0f%s", v, suffix) end
        if v >= 100 then return string.format("%.0f%s", v, suffix) end
        return string.format("%.1f%s", v, suffix)
    end
    if a >= 1e21 then return scaled(n / 1e21, "e21") end
    if a >= 1e18 then return scaled(n / 1e18, "Qi") end
    if a >= 1e15 then return scaled(n / 1e15, "Qa") end
    if a >= 1e12 then return scaled(n / 1e12, "T") end
    if a >= 1e9 then return scaled(n / 1e9, "B") end
    if a >= 1e6 then return scaled(n / 1e6, "M") end
    if a >= 1e3 then return scaled(n / 1e3, "K") end
    return string.format("%.0f", n)
end

local function repaintSwitches()
    for _, page in pairs(pages) do
        for _, row in ipairs(page:GetChildren()) do
            if row:IsA("Frame") and row:GetAttribute("Key") then
                local key = row:GetAttribute("Key")
                local lbl = row:FindFirstChild("TextLabel")
                local track = row:FindFirstChild("Frame")
                local on = CFG[key] == true
                if lbl then lbl.TextColor3 = on and T.text or T.dim end
                if track then
                    track.BackgroundColor3 = on and T.accent or T.line
                    local knob = track:FindFirstChild("Frame")
                    if knob then
                        knob.Position = UDim2.fromOffset(on and 16 or 2, 2)
                        knob.BackgroundColor3 = on and T.bg or T.dim
                    end
                end
            end
        end
    end
end

local function renderLoop()
    local tick = 0
    while alive() do
        STATE.Text = CFG.running and "run" or "pause"
        STATE.TextColor3 = CFG.running and T.accent or T.warn
        STAT.Text = string.format("%s  |  pps %s/s  |  lift %.1f  |  %s",
            fmt(S.power()), fmt(watch.pps), S.lift(), S.world())
        LOGB.Text = LOG[1] or "ready"
        repaintSwitches()
        -- debug: expose live CFG so toggles can be verified from outside
        if os.clock() - (lastDbg or 0) > 1 then
            lastDbg = os.clock()
            pcall(function()
                local parts = {}
                for k, v in pairs(CFG) do
                    if type(v) == "boolean" then parts[#parts+1] = k .. "=" .. tostring(v) end
                end
                table.sort(parts)
                writefile("JFC_debug.txt", table.concat(parts, "\n"))
            end)
        end
        tick = tick + 1
        task.wait(0.4)
    end
end

pages["auto"].Visible = true
tabBtns["auto"].BackgroundColor3 = T.raised
tabBtns["auto"].TextColor3 = T.text

task.spawn(throwLoop)
task.spawn(trainLoop)
task.spawn(mainLoop)
task.spawn(watchdogLoop)
task.spawn(renderLoop)
task.spawn(padLoop)
task.spawn(laneLoop)
MSG.watch()
if CFG.autoResume then task.spawn(ACT.resume) end
if CFG.perfProfile ~= "off" then task.spawn(function() task.wait(2) PERF.apply(CFG.perfProfile) end) end
watch.p = S.power()
log("v6 ready")
print("[JFC] v6 ready | perf=" .. CFG.perfProfile)
