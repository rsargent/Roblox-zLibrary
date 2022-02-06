-- ModuleScript ReplicatedStorage.zLibrary
--!strict
print('zLibrary v0.5.3 2022 Feb 6')

local z = {}

local signals = require(script.zLibrarySignal)
z.Signal = signals.Signal

local collectionService = game:GetService("CollectionService") :: CollectionService

function z.collectionService(): CollectionService
    return collectionService
end

function z.Players(): Players
    return game:GetService("Players")
end

function z.isServer(): boolean
    if z.Players().LocalPlayer then
        return false
    else
        return true
    end
end

function z.isLocal(): boolean
    return not z.isServer()    
end

function z.localPlayer(): Player
    local localPlayer = z.Players().LocalPlayer
    if localPlayer then
        return localPlayer
    else
        error("z.localPlayer() called from server Script.  Can only be called from LocalScript.")
    end
end

function z.localCharacter(): Model
    local localPlayer = z.localPlayer()
    local localCharacter = localPlayer.Character
    if localCharacter and localCharacter.Parent then
        return localCharacter
    else
        return localPlayer.CharacterAdded:Wait()
    end
end

function z.localHumanoid(): Humanoid
    return z.localCharacter():WaitForChild("Humanoid") :: Humanoid
end

-------------------------------------------
-- Events
local events: {[string]: RemoteEvent} = {}

function z._createEventIfNeeded(name: string)
    assert(z.isServer())
end

function z.getEvent(name: string): RemoteEvent
    if not events[name] then
        if z.isServer() then
            events[name] = Instance.new("RemoteEvent")
            events[name].Name = name
            events[name].Parent = game.ReplicatedStorage
        else
            if name ~= "toserver__zCreateEvent" then
                (z :: any).sendToServer("_zCreateEvent", name)
            end
            events[name] = game.ReplicatedStorage:WaitForChild(name)
        end
    end
    return events[name]
end

function z.receiveFromClient(name: string, func: (player: Player, ...any)->())
    z.getEvent("toserver_" .. name).OnServerEvent:Connect(func)
end

function z.sendToServer(name: string, ...)
    z.getEvent("toserver_" .. name):FireServer(...)
end

function z.sendToClient(name: string, player: Player, ...)
    z.getEvent("toclient_" .. name):FireClient(player, ...)
end

function z.receiveFromServer(name: string, func: (...any)->())
    z.getEvent("toclient_" .. name).OnClientEvent:Connect(func)
end

if z.isServer() then
    z.receiveFromClient("_zCreateEvent", function(_: Player, name: string)
        z.getEvent(name)
    end)
end

-------------------------------------------
-- Callbacks

local callbacks: {[number]: (player: Player, ...any)->()} = {}
local callbackCounter = 0
function z.registerCallback(callback: (player: Player, ...any)->())
    assert(z.isServer())
    callbackCounter = callbackCounter + 1
    callbacks[callbackCounter] = callback
    return callbackCounter
end

if z.isServer() then
    z.receiveFromClient("_zCallback", function(player: Player, callbackId: number, ...)
        callbacks[callbackId](player, ...)
    end)
end

-------------------------------------------
-- Mouse and Keyboard

function z.handleMouseButtonDown(player: Player, callback:(player: Player, ...any)->any)
    if z.isServer() then
        z.sendToClient("_zHandleMouseButton", player, z.registerCallback(callback))
    else
        error("TODO: implement registerMouseButtonDown for LocalScript")
    end
end

local keydownSignals = {} :: {[number]: signals.Signal}
local keyupSignals = {} :: {[number]: signals.Signal}

if z.isServer() then
    z.receiveFromClient("_zInputBegan", function(player: Player, gameProcessed: boolean, userInputType: Enum.UserInputType, keyCode: Enum.KeyCode)
        if not gameProcessed then
            if userInputType == Enum.UserInputType.Keyboard then
                print("Player", player, "keydown", keyCode)
                if (z :: any).receivePlayerKeydown then
                    (z :: any).receivePlayerKeydown(player, keyCode) 
                end
                local sig = keydownSignals[keyCode.Value]
                if sig then
                    sig:Fire(keyCode)
                end
            end
        end
    end)
    z.receiveFromClient("_zInputEnded", function(player: Player, gameProcessed: boolean, userInputType: Enum.UserInputType, keyCode: Enum.KeyCode)
        if not gameProcessed then
            if userInputType == Enum.UserInputType.Keyboard then
                print("Player", player, "keyup", keyCode)
                if (z :: any).receivePlayerKeyup then
                    (z :: any).receivePlayerKeyup(player, keyCode) 
                end
                local sig = keyupSignals[keyCode.Value]
                if sig then
                    sig:Fire(keyCode)
                end
            end
        end
    end)
end

function z.onKeydown(keyCode: Enum.KeyCode): signals.Signal
    if not keydownSignals[keyCode.Value] then
        keydownSignals[keyCode.Value] = z.Signal.new()
    end

    return keydownSignals[keyCode.Value]
end

if z.isLocal() then
    z.receiveFromServer("_zHandleMouseButton", function(callbackId)
        local mouse = z.localPlayer():GetMouse()
        mouse.Button1Down:Connect(function()
            local target = mouse.Target
            print('clicked mouse on target', target)
            z.sendToServer("_zCallback", callbackId, target)
        end)

    end)

    game:GetService("UserInputService").InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        z.sendToServer("_zInputBegan", gameProcessed, input.UserInputType, input.KeyCode)
    end)

    game:GetService("UserInputService").InputEnded:Connect(function(input: InputObject, gameProcessed: boolean)
        z.sendToServer("_zInputEnded", gameProcessed, input.UserInputType, input.KeyCode)
    end)
end


-------------------------------------------
-- Animation

local RemoteAnimationTrack = {}
RemoteAnimationTrack.__index = RemoteAnimationTrack

function RemoteAnimationTrack.new(player: Player, animationId: number)
    local self = {}
    self.player = player
    self.animationId = animationId

    return setmetatable(self, RemoteAnimationTrack)
end

function RemoteAnimationTrack:Play()
    z.sendToClient("_zAnimationTrackMethod", self.player, "Play", self.animationId)
end

function RemoteAnimationTrack:Stop()
    z.sendToClient("_zAnimationTrackMethod", self.player, "Stop", self.animationId)
end

function z.localAnimator(): Animator
    return z.localHumanoid():WaitForChild("Animator") :: Animator
end

type RemoteAnimationTrack = typeof(RemoteAnimationTrack.new(nil :: any, 0))

local tracks: {[string]: AnimationTrack|RemoteAnimationTrack} = {}

-- Old code for robot animation.  TODO: embed this below

--function z.getAnimationTrack(humanoid: Humanoid, id: number): AnimationTrack
--    if humanoid.RootPart and humanoid.RootPart.Anchored then
--        print("WARNING: SET "..humanoid:GetFullName()..".RootPart.Anchored to false or humanoid will not animate")
--    end
--    local key = humanoid:GetFullName() .. "|" .. id
--    if not tracks[key] then
--        local animation = Instance.new("Animation", humanoid)
--        animation.Name = "Animation_"..tostring(id)
--        animation.AnimationId = "rbxassetid://"..tostring(id)
--        tracks[key] = humanoid:LoadAnimation(animation)
--    end
--    return tracks[key]
--end

if z.isServer() then
    function z._animationCallback(player: Player, foo: number)
        -- TODO implement me
    end
end

function z._loadAnimationTrack(humanoid: Humanoid, id: number): AnimationTrack
    local animation = Instance.new("Animation", humanoid)
    animation.Name = "Animation_"..tostring(id)
    animation.AnimationId = "rbxassetid://"..tostring(id)
    local animator = humanoid:FindFirstChild("Animator") :: Animator

    if not animator then
        if z.isServer() then
            print('Creating Animator for NPC', humanoid:GetFullName())
            animator = Instance.new("Animator")
            animator.Parent = humanoid
        else
            animator = humanoid:WaitForChild("Animator") :: Animator
        end
    end

    local track = animator:LoadAnimation(animation)
    delay(1.0, function() 
        if track.Length == 0 then
            print('track.Length is zero')
            print('Animation is', track.Animation)
            print('IsPlaying is', track.IsPlaying)
            print('Looped is', track.Looped)
            print('Priority is', track.Priority)
            print('Speed is', track.Speed)
            print('TimePosition is', track.TimePosition)
            print('WeightCurrent is', track.WeightCurrent)


            --07:42:37.620  track.Length is zero  -  Client - zLibrary:222
            --07:42:37.621  Animation is Animation_8177212811  -  Client - zLibrary:223
            --07:42:37.621  IsPlaying is true  -  Client - zLibrary:224
            --07:42:37.621  Looped is true  -  Client - zLibrary:225
            --07:42:37.621  Priority is Enum.AnimationPriority.Action  -  Client - zLibrary:226
            --07:42:37.621  Speed is 1  -  Client - zLibrary:227
            --07:42:37.622  TimePosition is 0.95833307504654  -  Client - zLibrary:228
            --07:42:37.622  WeightCurrent is 1  -  Client - zLibrary:229


            error("Animation " .. tostring(id) .. " did not load, or has zero length.  Check permissions at https://www.roblox.com/library/" .. tostring(id))
        end
    end)
    return track
end

function z.getAnimationTrack(humanoid: Humanoid, animationId: number): AnimationTrack
    local key = humanoid:GetFullName() .. "|" .. animationId
    print('getAnimationTrack', key)
    if not tracks[key] then
        local player = z.Players():GetPlayerFromCharacter(humanoid.Parent :: Model)
        if not player then
            -- NPC
            if z.isServer() then
                tracks[key] = z._loadAnimationTrack(humanoid, animationId)
            else
                error("TODO: implement NPC animation for LocalScript")
            end
        else
            -- Player
            if z.isLocal() then
                tracks[key] = z._loadAnimationTrack(humanoid, animationId)
            else
                z.sendToClient("_zGetAnimationTrack", player, animationId)
                tracks[key] = RemoteAnimationTrack.new(player, animationId)
            end
        end
    end
    print('z.getAnimationTrack', humanoid, animationId, 'returns', tracks[key])
    return tracks[key] :: AnimationTrack
end

if z.isLocal() then
    z.receiveFromServer("_zGetAnimationTrack", function(animationId: number)
        -- Preload animation
        z.getAnimationTrack(z.localHumanoid(), animationId)
    end)
    z.receiveFromServer("_zAnimationTrackMethod", function(method: string, animationId: number)
        print("method", method)
        if method == "Play" then
            z.getAnimationTrack(z.localHumanoid(), animationId):Play()
        elseif method == "Stop" then
            z.getAnimationTrack(z.localHumanoid(), animationId):Stop()
        end
    end)
    z.receiveFromServer("_zCurrentCameraSetSubject", function(subject: Humanoid|BasePart)
        print("setting CurrentCamera.CameraSubject to ", subject)
        workspace.CurrentCamera.CameraSubject = subject
    end)
end

function z.playerCameraSetSubject(player: Player, subject: Humanoid|BasePart)
    z.sendToClient("_zCurrentCameraSetSubject", player, subject)
end

function z.findHumanoidFromPart(part: Instance): Humanoid?
    local targetModel = part:FindFirstAncestorOfClass("Model") :: Model?
    if targetModel then
        return targetModel:FindFirstChild("Humanoid") :: Humanoid
    else
        return nil
    end
end

export type Character = Model & { 
    Animate: Script, 
    HumanoidRootPart: Part, 
    Humanoid: Humanoid,
    Head: Part
}

function z.humanoidFromPlayer(player: Player)
    return (player.Character :: Character).Humanoid;
end

function z.playerFromGui(guiElement: GuiBase2d): Player
    local player: Player = guiElement:FindFirstAncestorOfClass("Player") :: Player
    assert(player)
    return player
end

-- More info on morphing characters from GnomeCode
-- https://www.youtube.com/watch?v=pVD-HBlfv4g
-- https://www.roblox.com/library/7137341387/Character-Changer-Morph

local disablePlayerRespawn = {} :: {[number]: boolean}

function z.setCharacter(player: Player, character: Model)
    character = character:Clone()
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then
        error("In z.setCharacter, character " .. character:GetFullName() .. " must have Humanoid")
    end
    local newCharacter = character :: Character

    local oldCharacter: Character = player.Character :: Character

    newCharacter.HumanoidRootPart.Anchored = false
    newCharacter:SetPrimaryPartCFrame((oldCharacter.PrimaryPart or oldCharacter.HumanoidRootPart).CFrame)
    print('newCharacter', newCharacter)
    print('humanoid', newCharacter.Humanoid, 'health', newCharacter.Humanoid.Health)

    local oldHumanoid = oldCharacter.Humanoid
    local newHumanoid = newCharacter.Humanoid

    disablePlayerRespawn[player.UserId] = true

    oldHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    oldHumanoid.BreakJointsOnDeath = false
    newHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    newHumanoid.BreakJointsOnDeath = false

    oldHumanoid.Parent = nil
    newHumanoid.Parent = nil

    player.Character = newCharacter
    newHumanoid.Parent = newCharacter

    -- Copy Animation script, if needed
    if not newCharacter:FindFirstChild("Animate") then
        print("Copying oldCharacter.Animate")
        -- TODO: complain if we're morphing between R6 and R15 because we'd get the wrong animation script
        local animateScript: Script = oldCharacter.Animate:Clone()
        animateScript.Parent = character
    else
        print("New character has Animate, not copying")
    end

    newCharacter.Parent = workspace

    newHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
    newHumanoid.BreakJointsOnDeath = true
    disablePlayerRespawn[player.UserId] = false

    z.playerCameraSetSubject(player, newCharacter.Humanoid)
end

--function z.setCharacter_new_v2(player: Player, character: Model)
--    print("***setCharacter")
--    local newHumanoid = character:FindFirstChild("Humanoid") :: Humanoid
--    if not newHumanoid then
--         error("In z.setCharacter, character " .. character:GetFullName() .. " must have Humanoid")
--    end
--    local playerCharacter = player.Character :: Character
--    local playerHumanoid = playerCharacter.Humanoid

--    playerHumanoid.HipHeight = newHumanoid.HipHeight

--    local newCharacter = character:Clone() :: Character
--    local newRootPart = newCharacter.PrimaryPart
--    newRootPart.CFrame = playerCharacter.HumanoidRootPart.CFrame

--    local oldChildren = playerCharacter:GetChildren()

--    --playerHumanoid:ReplaceBodyPartR15(Enum.BodyPartR15.LeftHand, newCharacter.LeftHand)

--    for i, partEnum in ipairs({Enum.BodyPartR15.Head}) do
--        playerHumanoid:ReplaceBodyPartR15(partEnum, newHumanoid:GetBodyPartR15(partEnum))
--        print("***", newChild.Name, "class", newChild.ClassName, "is limb", newHumanoid:GetBodyPartR15(newChild))
--    end


--    -- Move new character parts to 
--    --for i, newChild in ipairs(newCharacter:GetChildren()) do
--    --    if newChild:IsA("Humanoid") or not newChild:IsA("BasePart")  then
--    --        print("*** Not Adding", newChild.Name, "class", newChild.ClassName)
--    --    else
--    --        if newChild:IsA("BasePart") then
--    --            newChild.Anchored = false
--    --        end
--    --        print("*** Adding", newChild.Name, "class", newChild.ClassName)
--    --        newChild.Parent = playerCharacter
--    --        if newChild == newRootPart then
--    --            playerCharacter.PrimaryPart = newRootPart
--    --        end
--    --    end
--    --end

--    --for i, oldChild in ipairs(oldChildren) do
--    --    if oldChild:IsA("Humanoid") or not oldChild:IsA("BasePart") then
--    --        print("*** Not removing", oldChild.Name, "class", oldChild.ClassName)
--    --    else
--    --        print("*** Removing", oldChild.Name, "class", oldChild.ClassName)
--    --        oldChild.Parent = newCharacter
--    --    end
--    --end

--    newCharacter:Destroy()

--    --print('newCharacter', newCharacter)
--    --print('humanoid', newCharacter.Humanoid, 'health', newCharacter.Humanoid.Health)

--    --local oldHumanoid = oldCharacter.Humanoid
--    --local newHumanoid = newCharacter.Humanoid

--    ----oldHumanoid.Parent = workspace
--    --newHumanoid.Parent = workspace

--    --player.Character = newCharacter
--    --newHumanoid.Parent = newCharacter

--    ---- Copy Animation script, if needed
--    --if not newCharacter:FindFirstChild("Animate") then
--    --    print("Copying oldCharacter.Animate")
--    --    -- TODO: complain if we're morphing between R6 and R15 because we'd get the wrong animation script
--    --    local animateScript: Script = oldCharacter.Animate:Clone()
--    --    animateScript.Parent = character
--    --else
--    --    print("New character has Animate, not copying")
--    --end

--    --newCharacter.Parent = workspace

--    --z.playerCameraSetSubject(player, newCharacter.Humanoid)
--end



local cachedHttpService

function z.HttpService(): HttpService
    if not cachedHttpService then
        cachedHttpService = game:GetService('HttpService')
    end
    return cachedHttpService
end

function z.jsonEncode(object)
    return z.HttpService():JSONEncode(object)	
end

function z.jsonDecode(object)
    return z.HttpService():JSONDecode(object)
end


-------------------------------
--- Camera shake
-------------------------------

function z.shakeCamera(player: Player)
    z.sendToClient("_zShakeCamera", player)
end

if z.isLocal() then
    function epsilon()
        return 0.05 * (math.random() - 0.5)
    end
    z.receiveFromServer("_zShakeCamera", function()
        print("shakeCamera")
        local initialCFrame = workspace.Camera.CFrame
        for i = 1,20 do
            workspace.Camera.CFrame = initialCFrame * CFrame.Angles(epsilon(), epsilon(), epsilon())
            wait(0.02)
        end
        workspace.Camera.CFrame = initialCFrame
    end)
end

-----------

function z.humanoidsWithinDistance(position: Vector3, maxDist: number): {[number]: Humanoid}
    local ret = {} :: {[number]: Humanoid}
    for i,d in ipairs(game.Workspace:GetDescendants()) do
        if d:IsA("Humanoid") and (d.RootPart.Position - position).Magnitude <= maxDist then
            table.insert(ret, d)
        end
    end
    return ret
end

function z.sendPart(part: BasePart, direction: Vector3, speed: number, nseconds: number)
    direction = direction / direction.Magnitude

    local timer = 0
    while timer < nseconds do
        local delta = wait(0.01)
        timer = timer + delta
        part.CFrame = part.CFrame + direction * delta * speed
    end
end
-----------


local Players = game:GetService("Players")

local function onCharacterAdded(character)
end

local playerRespawnSignals = {} :: {[number]: signals.Signal}

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function (character)
        local player = Players:GetPlayerFromCharacter(character)
        if disablePlayerRespawn[player.UserId] then
            print(player.Name, "has spawned, but ignoring")
            return
        end
        print(player.Name, "has spawned")
        local sig = playerRespawnSignals[player.UserId]
        if sig then
            sig:Fire(player)
        end
    end)
    --player.CharacterRemoving:Connect(onCharacterRemoving)
end)

function z.onPlayerRespawn(player): signals.Signal
    if not playerRespawnSignals[player.UserId] then
        playerRespawnSignals[player.UserId] = z.Signal.new()

    end
    return playerRespawnSignals[player.UserId]
end

------------

if z.isServer() then
    function z.startFlying(player: Player)
        --local animation = Instance.new("Animation")
        --animation.AnimationId = "rbxassetid://3899964115"
        --local animation = script.IronManFlyAnimation
        --local track = player.Character.Humanoid:LoadAnimation(animation)
        --track:Play()

        z.sendToClient('zStartFlying', player)
    end

    function z.stopFlying(player: Player)
        z.sendToClient('zStopFlying', player)
    end
end


if z.isLocal() then
    local flying
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")


    z.receiveFromServer("zStartFlying", function()
        flying = true
        local myPlayer = z.localPlayer()

        local myChar = myPlayer.Character
        local myHRP = myChar:WaitForChild("HumanoidRootPart")
        local camera = game.Workspace.CurrentCamera


        local myHum = myChar.Humanoid

        local track = z.getAnimationTrack(myHum, 8240410453) -- Flight_8240410453
        --track.Looped = true
        track:Play()

        local bp = myHRP:FindFirstChild("zFlyingBodyPosition") :: BodyPosition
        if not bp then
            bp = Instance.new("BodyPosition")
            bp.Name ="zFlyingBodyPosition"
            bp.Parent = myHRP            
        end
        bp.MaxForce = Vector3.new(400000,400000,400000)
        bp.D = 10
        bp.P = 10000

        --bp.MaxForce = Vector3.new()

        local bg = myHRP:FindFirstChild("zFlyingBodyGyro") :: BodyGyro
        if not bg then
            bg = Instance.new("BodyGyro")
            bg.Name ="zFlyingBodyGyro"
            bg.Parent = myHRP   
        end

        bg.MaxTorque = Vector3.new(400000,400000,400000)
        bg.D = 10

        local startTime = time()

        -- Raise altitude for half a second	
        while flying and time() - startTime < 0.5 do
            RunService.RenderStepped:wait()
            bp.Position = myHRP.Position + Vector3.new(0,1,0)
            --bp.Position = myHRP.Position +((myHRP.Position - camera.CFrame.p).unit * speed)
            --bg.CFrame = CFrame.new(camera.CFrame.p, myHRP.Position)
        end

        --local spaceHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space)
        -- Hover, or fly forward when W is pressed
        while flying and myHum.FloorMaterial == Enum.Material.Air do
            RunService.RenderStepped:wait()
            if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                    speed = 5
                else
                    speed = 1
                end
            else
                speed = 0
            end
            -- todo: if pressing w, go fwd
            bp.Position = myHRP.Position +((myHRP.Position - camera.CFrame.p).unit * speed)
            bg.CFrame = CFrame.new(camera.CFrame.p, myHRP.Position)
        end

        track:Stop()
        bp.MaxForce = Vector3.new()
        bg.MaxTorque = Vector3.new()
        print('no longer flying in flying loop')
    end)

    z.receiveFromServer("zStopFlying", function()
        print('end flying')
        flying = false
    end)
end

-- must be called from server?
function z.scalePlayer(Player: Player, Percent: number)
    local Humanoid = Player.Character.Humanoid
    if Humanoid.RigType == Enum.HumanoidRigType.R6 then
        local Motors = {}
        table.insert(Motors, Player.Character.HumanoidRootPart.RootJoint)
        for i,Motor in pairs(Player.Character.Torso:GetChildren()) do
            if Motor:IsA("Motor6D") == false then continue end
            table.insert(Motors, Motor)
        end
        for i,v in pairs(Motors) do
            v.C0 = CFrame.new((v.C0.Position * Percent)) * (v.C0 - v.C0.Position)
            v.C1 = CFrame.new((v.C1.Position * Percent)) * (v.C1 - v.C1.Position)
        end


        for i,Part in pairs(Player.Character:GetChildren()) do
            if Part:IsA("BasePart") == false then continue end
            Part.Size = Part.Size * Percent
        end


        for i,Accessory in pairs(Player.Character:GetChildren()) do
            if Accessory:IsA("Accessory") == false then continue end

            Accessory.Handle.AccessoryWeld.C0 = CFrame.new((Accessory.Handle.AccessoryWeld.C0.Position * Percent)) * (Accessory.Handle.AccessoryWeld.C0 - Accessory.Handle.AccessoryWeld.C0.Position)
            Accessory.Handle.AccessoryWeld.C1 = CFrame.new((Accessory.Handle.AccessoryWeld.C1.Position * Percent)) * (Accessory.Handle.AccessoryWeld.C1 - Accessory.Handle.AccessoryWeld.C1.Position)
            Accessory.Handle:FindFirstChildOfClass("SpecialMesh").Scale *= Percent	
        end

    elseif Humanoid.RigType == Enum.HumanoidRigType.R15 then
        local HD = Humanoid:GetAppliedDescription()
        HD.DepthScale *= Percent
        HD.HeadScale *= Percent
        HD.HeightScale *= Percent
        HD.ProportionScale *= Percent
        HD.WidthScale *= Percent
        Humanoid:ApplyDescription(HD)
    end
end

return z

