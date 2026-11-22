-- On-demand kids boutique. Only this small launcher ships with the shop.
NPL.load("(gl)script/ide/commonlib.lua")
NPL.load("(gl)script/ide/Json.lua")
NPL.load("(gl)script/ide/timer.lua")
local Channel = commonlib.gettable("MyCompany.Aries.HaqiShop.WardrobeChannel")
NPL.load("(gl)script/apps/Aries/Service/EngineFeatureGate.lua")
local Gate=MyCompany.Aries.EngineFeatureGate
local worldGeneration=0
local origin = "https://cdn.keepwork.com/haqi/wardrobe/v1/"
local cache = ParaIO.GetWritablePath().."temp/haqi-wardrobe/packages/"
local pointer = cache.."installed.json"
local prepared = cache.."prepared.json"
local current, runtime, transfer, request
local serial = 0

local function read(path, limit)
    local file = ParaIO.open(path, "r")
    if not file:IsValid() then return end
    local data
    if file:GetFileSize() <= limit then data = file:GetText(0,-1) end
    file:close()
    return data
end

local function isHash(id)
    return type(id)=="string" and #id==40 and id:match("^[0-9a-f]+$")
end

local function descriptor(path)
    local raw = read(path, 4096)
    if not raw then return end
    local ok, d = pcall(commonlib.Json.Decode,raw)
    if ok and type(d)=="table" and d.schema==1 and isHash(d.revision) and isHash(d.digest) then return d end
end

local function matches(path,d)
    local data = read(path, 8*1024*1024)
    return data and ParaMisc.sha1(data)==d.digest
end

local function remember(d,target)
    target=target or pointer
    local tmp = target.."."..ParaGlobal.GenerateUniqueID()
    local f = ParaIO.open(tmp,"w")
    if not f:IsValid() then return end
    local data = commonlib.Json.Encode(d)
    f:write(data,#data)
    f:close()
    if not ParaIO.MoveFile(tmp,target) then ParaIO.DeleteFile(tmp);return false end
    return true
end

-- Older channel manifests identify a build by its original ZIP digest.
local versions={
    c9c0b940bf3fa82d1156126f0c84517f7216ec0b="1.0.0",
    ef957a20f7d3f2739f1602ed559e8c72a7138db1="2.0.0",
    ["4e8d0ae82b074868f0d9756cf61c195eda58dd4b"]="2.1.0",
    ["6a0b9819033be04215b2745b80281e41578b5e78"]="2.2.0",
    c3569993e3647efc9c9033587b60cda6e64502f1="2.2.1"
}
function Channel.Release(path)
    local d=descriptor(path)
    if d then
        d.version=type(d.version)=="string" and d.version:match("^%d+%.%d+%.%d+$") or versions[d.revision]
        return d
    end
end
function Channel.Installed()
    return Channel.Release(prepared) or Channel.Release(pointer)
end
function Channel.UpdateSource()
    return origin.."current.json"
end
function Channel.Prepare(d,tmp)
    if d.minimum and not Gate.AtLeast(ParaEngine.GetVersion(),d.minimum) then return false,"请先更新客户端" end
    if not matches(tmp,d) then return false,"更新包校验失败" end
    ParaIO.CreateDirectory(cache)
    local zip=cache..d.digest..".zip"
    if not matches(zip,d) and not ParaIO.MoveFile(tmp,zip) then return false,"无法保存更新包" end
    if not remember(d,prepared) then return false,"无法保存版本记录" end
    return true,"已下载，下次打开衣柜时生效"
end

local function activate(d)
    if not d or (d.minimum and not Gate.AtLeast(ParaEngine.GetVersion(),d.minimum)) then return end
    if current and current.digest==d.digest then return runtime end
    local zip = cache..d.digest..".zip"
    if not matches(zip,d) or not ParaAsset.OpenArchive(zip,false) then return end
    local name = "HaqiWardrobe_"..d.revision
    local ok,instance = pcall(function()
        NPL.load("(gl)Mod/"..name.."/Studio.lua")
        local m = Mod[name]
        assert(m and type(m.Open)=="function" and m.LocalLook)
        local looks = m.Wardrobe.Load()
        assert(#looks>0 and #m.ShopArt.read().items>0)
        return m
    end)
    if not ok then ParaAsset.CloseArchive(zip);return end
    if runtime then
        runtime.LocalLook.stop()
        ParaAsset.CloseArchive(cache..current.digest..".zip")
    elseif Mod.HaqiWardrobe and Mod.HaqiWardrobe.LocalLook then
        Mod.HaqiWardrobe.LocalLook.stop()
    end
    current,runtime = d,instance
    runtime.LocalLook.enterWorld()
    return runtime
end

local function launch(d)
    if not d then return end
    local ok,app = pcall(activate,d)
    if not ok or not app then return end
    local opened = pcall(app.Open)
    if opened and ParaUI.GetUIObject("wardrobe-room"):IsValid() then return true end
    if app.Close then pcall(app.Close) end
    ParaUI.Destroy("wardrobe-room")
    app.LocalLook.stop()
    ParaAsset.CloseArchive(cache..d.digest..".zip")
    runtime,current=nil,nil
end

local function finish(d)
    local caller = request
    request = nil
    if not caller or not caller.visible() then return end
    local previous = current or descriptor(pointer)
    d=d or descriptor(prepared)
    if launch(d) then
        if remember(current) then ParaIO.DeleteFile(prepared) end
        caller.status(L"可进入试衣间")
    elseif previous and (not d or previous.digest~=d.digest) and launch(previous) then
        caller.status(L"正在使用本机缓存版本")
    else
        caller.status(L"暂时无法载入衣橱，请点击重试")
    end
end

local function download(url, callback)
    serial = serial+1
    local id = serial
    local job = {path=cache..ParaGlobal.GenerateUniqueID()..".part",callback=callback,id=id}
    transfer = job
    job.timer = commonlib.Timer:new({callbackFunc=function()
        Channel.OnDownload(id,"timeout")
    end})
    job.timer:Change(15000,nil)
    NPL.AsyncDownload(url,job.path,string.format(";MyCompany.Aries.HaqiShop.WardrobeChannel.OnDownload(%d,msg.DownloadState);",id),job.path)
end

function Channel.OnDownload(id,state)
    local job = transfer
    if not job or job.id~=id or (state~="complete" and state~="terminated" and state~="timeout") then return end
    transfer=nil
    job.timer:Change()
    if state=="timeout" then NPL.CancelDownload(job.path) end
    job.callback(state=="complete" and job.path)
    ParaIO.DeleteFile(job.path)
end

local function fetch(visible,status)
    if ParaUI.GetUIObject("wardrobe-room"):IsValid() then return end
    request = {visible=visible,status=status}
    status(L"正在检查衣橱更新…")
    if transfer then return end
    ParaIO.CreateDirectory(cache)
    download(origin.."current.json?v="..ParaGlobal.GenerateUniqueID(),function(path)
        local d = path and descriptor(path)
        local required=d or descriptor(pointer)
        if required and required.minimum and not Gate.AtLeast(ParaEngine.GetVersion(),required.minimum) then
            local caller=request
            request=nil
            if caller and caller.visible() then
                caller.status(L"请更新引擎或到官网体验")
                Gate.Show({name=Gate.wardrobe.name,minimum=tostring(required.minimum)},"请更新客户端，或先在官网网页版预览。")
            end
            return
        end
        if not d or (current and current.digest==d.digest) or matches(cache..d.digest..".zip",d) then
            finish(d)
            return
        end
        if not request or not request.visible() then request=nil;return end
        request.status(L"正在下载试衣间…")
        download(origin..d.digest..".zip",function(tmp)
            if tmp and matches(tmp,d) and ParaIO.MoveFile(tmp,cache..d.digest..".zip") then finish(d)
            else finish() end
        end)
    end)
end

function Channel.Open(visible,status)
    NPL.load("(gl)script/apps/Aries/Mods/Manager.lua")
    if not MyCompany.Aries.HaqiMods.Enabled("HaqiWardrobe") then
        status(L"请在系统设置的 Mod 管理中启用彩虹衣柜")
        return
    end
    local epoch=worldGeneration
    Gate.Run(Gate.wardrobe,function() fetch(visible,status) end,function() return epoch==worldGeneration and visible() end)
end

function Channel.EnterWorld()
    if not ParaIO.DoesFileExist(ParaIO.GetWritablePath().."config/haqi-wardrobe-local.json",false) then return end
    local epoch=worldGeneration
    Gate.Run(Gate.wardrobe,function()
        if runtime then runtime.LocalLook.enterWorld() else activate(descriptor(pointer)) end
    end,function() return epoch==worldGeneration end,true)
end

function Channel.LeaveWorld()
    worldGeneration=worldGeneration+1
    Gate.Close()
    request=nil
    if transfer then
        local job=transfer
        transfer=nil
        job.timer:Change()
        NPL.CancelDownload(job.path)
        ParaIO.DeleteFile(job.path)
    end
    if runtime then
        if runtime.Close then runtime.Close() end
        runtime.LocalLook.stop()
    end
end
