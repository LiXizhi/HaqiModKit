NPL.load("(gl)script/apps/Aries/Creator/Game/Mod/ModBase.lua")
local Plugin=commonlib.inherit(commonlib.gettable("Mod.ModBase"),commonlib.gettable("Mod.HaqiWardrobe"))
Plugin:Property({"Name","HaqiWardrobe"})
Plugin:Property({"Desc","Haqi Wardrobe"})
function Plugin:init()
    NPL.load("(gl)script/apps/Aries/SlashCommand/SlashCommand.lua")
    local command={name="haqiwardrobe",quick_ref="/haqiwardrobe [outfit ID]",IsLocal=function() return true end,
        desc="Open the Haqi fitting room",handler=function(_,text)
            NPL.load("(gl)Mod/HaqiWardrobe/Studio.lua")
            Plugin.Open(text and text:match("%S+"))
        end}
    commonlib.gettable("MyCompany.Aries.Game.Commands").haqiwardrobe=command
    MyCompany.Aries.SlashCommand.SlashCommand:RegisterSlashCommand(command)
end

function Plugin:OnWorldLoad()
    NPL.load("(gl)Mod/HaqiWardrobe/LocalLook.lua")
    Plugin.LocalLook.enterWorld()
end
function Plugin:OnLeaveWorld()
    if Plugin.Close then Plugin.Close() end
    if Plugin.LocalLook then Plugin.LocalLook.stop() end
end
