-- The fitting room persists only garment IDs. Apply exclusively to the local render actor.
NPL.load("(gl)Mod/HaqiWardrobe/Wardrobe.lua")
NPL.load("(gl)Mod/HaqiWardrobe/Mix.lua")
if ParaIO.DoesFileExist("Mod/HaqiWardrobe/EngineFeatureGate.lua",true) then
    NPL.load("(gl)Mod/HaqiWardrobe/EngineFeatureGate.lua")
else
    NPL.load("(gl)script/apps/Aries/Service/EngineFeatureGate.lua")
end
local M=Mod.HaqiWardrobe
local Local=commonlib.gettable("Mod.HaqiWardrobe.LocalLook")
local directory=ParaIO.GetWritablePath().."config/"
local filename=directory.."haqi-wardrobe-local.json"
local wearer, retry
local generation=0

function Local.read(ids)
    local f=ParaIO.open(filename,"r")
    if not f:IsValid() then return end
    local raw=f:GetText(0,-1)
    f:close()
    local ok,record=pcall(commonlib.Json.Decode,raw)
    if ok and type(record)=="table" and record.version==1 and type(record.parts)=="table" then
        if pcall(M.Mix.resolve,record.parts,ids) then return record.parts end
    end
end

function Local.stop()
    generation=generation+1
    if retry then retry:Change(); retry=nil end
    if wearer then M.Wardrobe.Clear(wearer); wearer=nil end
end

local function currentElf()
    local actor=ParaScene.GetPlayer()
    if actor and actor:IsValid() and actor:GetPrimaryAsset():GetKeyName():lower():find("/elf/",1,true) then return actor end
end

function Local.apply(parts,ids,callback)
    local actor=currentElf()
    if not actor then if callback then callback(true,false) end; return end
    if wearer and wearer:GetID()~=actor:GetID() then Local.stop() end
    wearer=actor
    M.Wardrobe.TryOn(actor,M.Mix.resolve(parts,ids),function(ok,err)
        if callback then callback(ok,true,err) end
    end)
end

function Local.save(parts,ids,callback)
    M.Mix.resolve(parts,ids)
    local json=commonlib.Json.Encode({version=1,parts=parts})
    ParaIO.CreateDirectory(directory)
    local temp=filename.."."..ParaGlobal.GenerateUniqueID()..".tmp"
    local f=ParaIO.open(temp,"w")
    if not f:IsValid() then callback(false,false,"无法保存本机搭配"); return end
    f:write(json,#json)
    f:close()
    if not ParaIO.MoveFile(temp,filename) then
        ParaIO.DeleteFile(temp)
        callback(false,false,"无法保存本机搭配")
        return
    end
    Local.apply(parts,ids,callback)
end

function Local.reset()
    Local.stop()
    if ParaIO.DoesFileExist(filename,false) then ParaIO.DeleteFile(filename) end
end

local function restore()
    local _,ids=M.Wardrobe.Load()
    local parts=Local.read(ids)
    if not parts then return end
    local attempts=0
    retry=commonlib.Timer:new({callbackFunc=function(t)
        attempts=attempts+1
        if currentElf() then t:Change(); Local.apply(parts,ids)
        elseif attempts>=60 then t:Change() end
    end})
    retry:Change(100,500)
end

function Local.feature()
    local gate=MyCompany.Aries.EngineFeatureGate
    local f=ParaIO.open("Mod/HaqiWardrobe/requirements.json","r")
    local minimum=gate.wardrobe.minimum
    if f:IsValid() then
        local raw=f:GetText(0,-1);f:close()
        minimum=commonlib.Json.Decode(raw).minimum
    end
    return {name=gate.wardrobe.name,minimum=minimum,capability="glb"}
end
function Local.enterWorld()
    Local.stop()
    if not ParaIO.DoesFileExist(filename,false) then return end
    local token=generation
    MyCompany.Aries.EngineFeatureGate.Run(Local.feature(),restore,function() return generation==token end,true)
end
