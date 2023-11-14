local CH = locale == "zh" or locale == "zhr"
name = CH and "高亮显示/锁定攻击目标" or "Highlight/Lock Attack Target"
author = "川小胖"

version = "2.1"

description = CH and
[[
红色高亮显示攻击目标， 黄色高亮显示锁定目标， 绿色高亮显示排除目标

如有按键冲突请在配置页面修改：
锁定：
  Ctrl(强制攻击键绑定)+左键目标锁定，搜索范围内有锁定目标优先打锁定目标
排除：
  Shift(强制交易键绑定)+左键目标排除攻击，即攻击键F攻击和强制攻击Ctrl+F不会锁定该目标
  Shift双击目标快速标记同种生物，就像排队论
清除：
  Alt（强制检查键绑定）+左键任何地方清除所有标记
]]
or
[[
highlight the attack target in red, the locked target in yellow and the excluded in green

LOCK(YELLOW):
  Ctrl(Force_Attack)+LeftClick the entity to lock it and you will priorize the locked one if in range 
EXCLUDE(GREEN):
  Shift(Force_Trade)+LeftClick the entity to exclude attack it and you will not target it when holding F or Ctrl+F
  Shift+DoubleLeftClick the entity to quick mark all the same creatures nearby as excludes(just like actionqueue mod) 
CLEAR ALL:
  Alt(Force_Inspect)+LeftClick anywhere to clear all the marks
]]

api_version = 10
dst_compatible = true
dont_starve_compatible = false
shipwrecked_compatible = false
reign_of_giants_compatible = false

all_clients_require_mod = false
client_only_mod = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

local LMB, RMB, MMB = "\238\132\128","\238\132\129","\238\132\130"
local key_list = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"}
local key_default = {
						LOCK = {description = "Ctrl + \238\132\128", data = "default"},
						EXCLUD = {description = "Shift + \238\132\128", data = "default"},
						CLEAR = {description = "Alt + \238\132\128", data = "default"},
					}



local function generateKeyOpts(default_opt)
	local key_options = {{description = CH and "禁用" or "Disabled", data = "disabled"}, default_opt}
	local offset = default_opt and 2 or 1
	for i = 1, #key_list do
		key_options[i+offset] = { description = key_list[i], data = "KEY_"..key_list[i] }
	end
	return key_options
end
configuration_options = {
	{
		name = "TINT_PERCENT",	
		label = CH and "高亮颜色深浅" or "Shade of Color",
		hover = CH and "调节高亮的颜色强度" or "Adjusts the colour shade",
		options = {{description = CH and "深" or "Deep", data = 1},{description = CH and "中" or "Medium", data = 0.7}, {description = CH and "浅" or "Shallow", data = 0.4}},
		default = 1,
	},
	{
		name = "KEY_LOCK",	
		label = CH and "目标锁定" or "Lock Target",
		hover = CH and "在攻击范围内会优先以锁定单位为目标" or "You will priorize to target the locked one if in attack range",
		options = generateKeyOpts(key_default["LOCK"]),
		default = "default",
	},
	{
		name = "KEY_EXCLUD",	
		label = CH and "目标排除" or "Exclude Target",
		hover = CH and "在攻击范围内将不会作为目标" or "You will not target the excluded one",
		options = generateKeyOpts(key_default["EXCLUD"]),
		default = "default",
	},
	{
		name = "KEY_CLEAR",	
		label = CH and "清除所有标记" or "Clear All Marks",
		hover = CH and "清除所有标记的实体并取消高亮" or "Clear all the marks and highlight",
		options = generateKeyOpts(key_default["CLEAR"]),
		default = "default",
	},
}

