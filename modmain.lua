GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})
if TheNet:IsDedicated()  then  return end

local last_attacktarget = nil --上一个攻击目标
local last_lockedtarget = nil --上一个锁定的目标

local attack_target = nil --记录locomotor的攻击目标，意味着需要移动靠近的攻击目标，由SendRPCToServer触发（关延迟补偿时）或者locomotor的GoToEntity触发（开延迟补偿时），由方向按键停止
--local combat_target = nil --记录combat_replica的攻击目标，在攻击范围内触发攻击才会有值, 弃用 deprecated
local locked_target = nil --锁定的目标
local excludtarget_list = {} -- 排除列表

local highlight_access = false -- highlight组件更改的权限，防止以及加上highlight的目标被鼠标聚焦覆盖或移除

-- highlight消逝倒计时,弃用 deprecated
local TIMEOUT = 0.5
local countdown_clear = TIMEOUT

local tint_percent = GetModConfigData("TINT_PERCENT") or 1
local attack_tint = {0.8*tint_percent,	0  				,	0 } --攻击目标变红色
local locked_tint = {0.6*tint_percent,	0.6*tint_percent,	0 } --锁定目标变黄色
local exclud_tint = {0  			 ,	0.8				,	0 } --排除目标变绿色

-- GLOBAL.atkdebug = function()
-- 	print("combat target: last:",last_attacktarget or "nil", "current:", attack_target or "nil")
-- 	print("locked target: last:",last_lockedtarget or "nil", "current:", locked_target or "nil")
-- 	dumptable(excludtarget_list)
-- end

--------------------------- unhighlight the last target and highlight the new target -------------------------------

local function hookHighlight(self)
	local old_Highlight = self.Highlight
	self.Highlight = function(self, ...)
		if ((attack_target ~= nil and attack_target == self.inst) or
				(locked_target ~= nil and locked_target == self.inst) or
					excludtarget_list ~= nil and excludtarget_list[self.inst]) and
						highlight_access == false then
			return
		else
			return old_Highlight and old_Highlight(self, ...)
		end
	end

	local old_UnHighlight = self.UnHighlight
	self.UnHighlight = function(self, ...)
		if ((attack_target ~= nil and attack_target == self.inst) or
				(locked_target ~= nil and locked_target == self.inst) or
					excludtarget_list ~= nil and excludtarget_list[self.inst]) and
						highlight_access == false then
			return
		else
			return old_UnHighlight and old_UnHighlight(self, ...)
		end
	end
	
end
AddComponentPostInit("highlight", hookHighlight)

local function ToggleHighlight(inst, tint)
	if inst and inst:IsValid() and inst.AnimState then
		if type(tint) == "table" then
			if inst.components.highlight == nil then
				inst:AddComponent("highlight")
			end
			inst.components.highlight:Highlight(unpack(tint))
			inst.AnimState:SetLightOverride(1) -- make it can be seen clearly in dark
		elseif tint == false and inst.components.highlight then
			inst.components.highlight:UnHighlight()
			inst.AnimState:SetLightOverride(0)
		end
	end
end

-- deprecated
local function updateAtkTargetHighlight()
	--print(combat_target or "nil", attack_target or "nil")
	local target = attack_target
	if last_attacktarget ~= target then
		local is_lasttarget_locked = last_attacktarget == locked_target
		local is_lasttarget_exclud = last_attacktarget == exclud_target
		highlight_access = true

		ToggleHighlight(last_attacktarget, (is_lasttarget_locked and locked_tint) or (is_lasttarget_exclud and exclud_tint) or false)
		ToggleHighlight(target, attack_tint)
		--print(last_attacktarget or "nil" , target or "nil")

		highlight_access = false

		last_attacktarget = target
	end
end

local function setAttackTargetRecord(target)
	last_attacktarget = attack_target
	attack_target = target
end

local function setLockedTargetRecord(target)
	last_lockedtarget = locked_target
	locked_target = target
end

local function AddToExcludTargetList(target)
	if excludtarget_list and not excludtarget_list[target] then
		excludtarget_list[target] = true
	end
end

local function RemoveFromExcludTargetList(target)
	if excludtarget_list and excludtarget_list[target] then
		excludtarget_list[target] = false
	end
end

local function ClearAllExcludTargetList()
	excludtarget_list = {}
end

local function updateTargetHighlight(target)
	if target == nil or not target:IsValid() then return end
	local is_atking = target == attack_target
	local is_locked = target == locked_target
	local is_exclud = excludtarget_list and excludtarget_list[target]
	local tint = (is_atking and attack_tint) or
				 (is_locked and locked_tint) or 
				 (is_exclud and exclud_tint) or
				 false
	highlight_access = true

	ToggleHighlight(target, tint)

	highlight_access = false
end

------------------------ get locomotor attack target via hook RPC and Locomotor ----------------
local old_SendRPCToServer = SendRPCToServer

local forceattack_override = false  -- override the forceattack param in SendAttackButtonRPC, order to success to launch an attack to locked_target
--- for lag compensation OFF, hook the RPC
-- hook all the RPC about ATTACK action
GLOBAL.SendRPCToServer = function(rpc, param1, param2, param3, param4, ...)
	local actioncode, target
	if rpc == RPC.AttackButton then -- for RPC.AttackButton: rpc, target, forceattack, noforce(no force is used for controller)
		actioncode = ACTIONS.ATTACK.code
		target = param1
		if forceattack_override then
			param2 = true
		end
	elseif rpc == RPC.LeftClick then -- for RPC.LeftClick: rpc, actioncode, x, z, target, isreleased, controlmods, noforce
		actioncode = param1
		target = param4
	end

	if actioncode == ACTIONS.ATTACK.code and target ~= nil then
		setAttackTargetRecord(target)
		updateTargetHighlight(last_attacktarget)
		updateTargetHighlight(attack_target)
	end

	return old_SendRPCToServer(rpc, param1, param2, param3, param4, ...)
end

---- for lag compensation ON, hook the bufferedaction in LocoMotor:GoToEntity
local function hookLocoMotorForPlayer(self, inst)
	if not inst:HasTag("player") then return end -- only for player

	local old_GoToEntity = self.GoToEntity
	self.GoToEntity = function(self, target, bufferedaction, ...)
		if target ~= nil and bufferedaction.action == ACTIONS.ATTACK then
			setAttackTargetRecord(target)
			updateTargetHighlight(last_attacktarget)
			updateTargetHighlight(attack_target)
		end
		--print(target or "nil target", bufferedaction or "nil action")
		return old_GoToEntity and old_GoToEntity(self, target, bufferedaction, ...)
	end

end
AddComponentPostInit("locomotor", hookLocoMotorForPlayer)


----------------------------clear the locomtor attack target via walk buttons ----------------------------------
local walk_controls = {}
for control = CONTROL_MOVE_UP, CONTROL_MOVE_RIGHT do
    walk_controls[control] = true
end

local function AddWalkBtnHook(self)
	local old_OnControl = self.OnControl
	 self.OnControl = function(self, control, down)

		if attack_target ~= nil then

			if walk_controls[control] or ((control == CONTROL_PRIMARY) and TheInput:GetWorldEntityUnderMouse() == nil) then
				setAttackTargetRecord(nil)
				updateTargetHighlight(last_attacktarget)
				--updateTargetHighlight(attack_target) -- attack_target = nil  when we reach here
			end
		end
		return old_OnControl and old_OnControl(self, control, down)
	end
end

--------------------- lock the attack target via Ctrl+LeftClick, exclude the target via Shift+LeftClick, unlock the attack target via Alt+LeftClick ------------------------
-- a modify of ValidateAttackTarget in PlayerController, it check the target of ActionButton
local function ValidateForceAttackTarget(combat, target, with_checkdist, x, z, reach)
    if not combat:CanTarget(target) or (combat.hal_OldIsAlly and combat:hal_OldIsAlly(target))  then
        return false
    end
	-- no need the forceattack check since we has overrided the forceattack = true

	if with_checkdist and x and z and reach then
		reach = reach + target:GetPhysicsRadius(0)
		return target:GetDistanceSqToPoint(x, 0, z) <= reach * reach
	else -- without_checkdist
		return true
	end
end

-- deprecated
local function updateLockedTargetHighlight()
	if last_lockedtarget ~= locked_target then
		local is_lastlocked_atktarget = attack_target == last_lockedtarget
		
		highlight_access = true

		ToggleHighlight(last_lockedtarget, is_lastlocked_atktarget and attack_tint or false)
		ToggleHighlight(locked_target, locked_tint)

		highlight_access = false

		last_lockedtarget = locked_target
	end
end

local last_excludclick_time = nil
local DBCLICK_TIME_THRESHOLD = 0.3

local function DoTargetLock(ent)
	if ThePlayer and ThePlayer.replica.combat and ent and ent:IsValid() then
		if not IsEntityDead(ent) and CanEntitySeeTarget(ThePlayer, ent) and ValidateForceAttackTarget(ThePlayer.replica.combat, ent) then
			-- to avoid exclude and locked target conflict each other
			if excludtarget_list and excludtarget_list[ent] then
				RemoveFromExcludTargetList(ent)
			end
			setLockedTargetRecord(ent)
			updateTargetHighlight(last_lockedtarget)
			updateTargetHighlight(locked_target)
		end
	end
end

local function DoTargetExclude(ent)
	if ThePlayer and ThePlayer.replica.combat and ent and ent:IsValid() then
		if ent ~= ThePlayer and ent:HasTag("_combat") and ent:HasTag("_health") then -- looser condition because we are not need really able to target it
			local targets = nil
			local curtime = GetStaticTime()
			if last_excludclick_time and curtime - last_excludclick_time < DBCLICK_TIME_THRESHOLD then -- doubleclick
				local x, y, z = ThePlayer.Transform:GetWorldPosition()
				targets = TheSim:FindEntities(x, 0, z, 30, {"_combat", "_health"}, {"FX", "NOCLICK", "DECOR", "INLIMBO"}) -- we will do prefab name check follow up
			else -- singleclick
				targets = {ent}
			end
			--dumptable(targets)
			
			for k,target in ipairs(targets) do 
				-- to avoid exclude and locked target conflict each other
				if target.prefab == ent.prefab then
					if locked_target == target then
						setLockedTargetRecord(nil)
					end
					AddToExcludTargetList(target)
					updateTargetHighlight(target)
				end	
			end
			last_excludclick_time = curtime
		end
	end
end

local function DoExcludeListClear()
	setAttackTargetRecord(nil)
	setLockedTargetRecord(nil)
	local cached_excludtarget_list = shallowcopy(excludtarget_list)
	ClearAllExcludTargetList()
	updateTargetHighlight(last_attacktarget)
	updateTargetHighlight(last_lockedtarget)
	for k,v in pairs(cached_excludtarget_list) do 
		updateTargetHighlight(k)
	end	
end

local function KeystrToKeyNum(str)
	if str and type(str) == "string" then
		local upper = string.upper(str)
		if upper == "DEFAULT" then
			return 0
		elseif upper == "DISABLED" then
			return -1
		else
			return GLOBAL.rawget(GLOBAL, upper) or 0
		end
	end
	return 0 -- default trigger if invalid str
end

local KEY_FNS = {
					LOCK 	= { key = KeystrToKeyNum(GetModConfigData("KEY_LOCK")), 	fn = DoTargetLock,			need_target = true},
					EXCLUD 	= { key = KeystrToKeyNum(GetModConfigData("KEY_EXCLUD")), 	fn = DoTargetExclude,		need_target = true},
					CLEAR 	= { key = KeystrToKeyNum(GetModConfigData("KEY_CLEAR")), 	fn = DoExcludeListClear,	need_target = false},
				}

-- GLOBAL.key_fn = KEY_FNS

local function IsDefaultTrigger(k)
	local key = KEY_FNS[k] and KEY_FNS[k].key
	return key and type(key) == "number" and key == 0
end

local function IsCustomTrigger(k)
	local key = KEY_FNS[k] and KEY_FNS[k].key
	return key and type(key) == "number" and key > 0
end

local controls_include = {CONTROL_FORCE_ATTACK, CONTROL_FORCE_TRADE, CONTROL_FORCE_INSPECT}
local function IsControlPressedSingly(control)
	if TheInput and TheInput:IsControlPressed(control) then
		for k,v in ipairs(controls_include) do
			if v ~= control and TheInput:IsControlPressed(v) then
				return false
			end
		end
		return true
	end

end

local function AddDefaultTrigger(self)
	-- lock trigger
	local old_OnLeftUp = self.OnLeftUp -- note that has changed to OnLeftUp because holding for a shortwhile will trigger many times OnLeftClick and will effects doubleclick checks
	self.OnLeftUp = function(self, ...)
		local act = self:GetLeftMouseAction()
		local target = act and act.target or TheInput:GetWorldEntityUnderMouse()
		-- lock
		if IsDefaultTrigger("LOCK") and act and act.action == ACTIONS.ATTACK and act.target ~= nil and IsControlPressedSingly(CONTROL_FORCE_ATTACK) then
			DoTargetLock(target)
		-- exclude
		elseif IsDefaultTrigger("EXCLUD") and target ~= nil and IsControlPressedSingly(CONTROL_FORCE_TRADE) then --looser condition because we are not need really able to target it
			DoTargetExclude(target)
		--clear all
		elseif IsDefaultTrigger("CLEAR") and IsControlPressedSingly(CONTROL_FORCE_INSPECT) then -- no target limit
			DoExcludeListClear()
		end
		return old_OnLeftUp and old_OnLeftUp(self, ...)
	end
end

local function AddCustomTrigger(self)
	local function AddStandardKeyUpHandler(key, do_fn, need_target)
		TheInput:AddKeyUpHandler(key, function()
			if ThePlayer and ThePlayer.HUD and not ThePlayer.HUD:HasInputFocus() then
				local ent = TheInput:GetWorldEntityUnderMouse()
				if not need_target or ent ~= nil and do_fn ~= nil and type(do_fn) == "function" then
					do_fn(need_target and ent or nil)
				end
			end
		end)
	end

	for k, v in pairs(KEY_FNS) do
		if IsCustomTrigger(k) then
			AddStandardKeyUpHandler(v.key, v.fn, v.need_target)
		end
	end

end

local function AddAtkBtnHook(self)
	local old_DoAttackButton = self.DoAttackButton
	self.DoAttackButton = function(self, retareget)
		--print("enter DoAtkBtn")

		-- 从 PlayerController:GetAttackTarget 抄了一部分
		local function GetSearchRad(self)
			local attackrange = self.inst and self.inst.replica.combat and self.inst.replica.combat:GetAttackRangeWithWeapon()
			return self.directwalking and attackrange or attackrange + 6
			--return attackrange
		end

		if retareget == nil and locked_target ~= nil then
			if not IsEntityDead(locked_target) and ValidateForceAttackTarget(self.inst.replica.combat, locked_target) then
				local x, y, z = self.inst.Transform:GetWorldPosition()
				local rad = GetSearchRad(self)
				local reach = self.inst:GetPhysicsRadius(0) + rad + .1
				if CanEntitySeeTarget(self.inst, locked_target) and ValidateForceAttackTarget(self.inst.replica.combat, locked_target, true, x, z, reach) then
					--print(reach)
					forceattack_override = true -- override the param of forceattack in sendAttackButtonRPC, which works just like with holding CONTROL_FORCE_ATTACK
					old_DoAttackButton(self, locked_target)
					forceattack_override = false			-- cancel the override
				else
					return old_DoAttackButton and old_DoAttackButton(self, retareget)
				end
			else -- locked_target became invalid , clear it
				setLockedTargetRecord(nil)
				updateTargetHighlight(last_lockedtarget)
			end
		else
			return old_DoAttackButton and old_DoAttackButton(self, retareget)
		end
	end
end

AddComponentPostInit("playercontroller", function (self)
	AddWalkBtnHook(self)
	AddDefaultTrigger(self) -- do config key check inside
	AddCustomTrigger(self)	-- do config key check inside
	AddAtkBtnHook(self)
end)

--------- apply the exclude target list via hook IsAlly method -------
local function AddAllyHook(self)
	if self.inst then
		self.inst:DoTaskInTime(0, function()
			if self.inst ~= ThePlayer then return end
			local old_IsAlly = self.IsAlly
			self.IsAlly = function(self, guy)
				return (excludtarget_list and excludtarget_list[guy]) or (old_IsAlly and old_IsAlly(self, guy))
			end
			self.hal_OldIsAlly = old_IsAlly -- save a replica of old_IsAlly to do check in ValidateForceAttackTarget function
		end)
	end

end	
AddClassPostConstruct("components/combat_replica", AddAllyHook)




