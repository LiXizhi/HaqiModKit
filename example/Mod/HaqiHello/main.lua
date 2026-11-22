NPL.load("(gl)script/apps/Aries/Creator/Game/Mod/ModBase.lua")
local Hello=commonlib.inherit(Mod.ModBase,commonlib.gettable("Mod.HaqiHello"))
Hello:Property({"Name","HaqiHello"})

function Hello:OnWorldLoad()
    self:OnLeaveWorld()
    local banner=ParaUI.CreateUIObject("button","HaqiHello.banner","_ctt",0,48,220,34)
    banner.text="你好，哈奇设计师！"
    banner:AttachToRoot()
    log("HaqiHello ready\n")
end

function Hello:OnLeaveWorld()
    ParaUI.Destroy("HaqiHello.banner")
end
