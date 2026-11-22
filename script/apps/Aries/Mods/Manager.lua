-- Local kids-client mods. Community ZIPs share the standard ParaCraft plugin format.
NPL.load("(gl)script/ide/commonlib.lua")
NPL.load("(gl)script/ide/Json.lua")
NPL.load("(gl)script/ide/System/Plugins/PluginManager.lua")
NPL.load("(gl)script/ide/Files.lua")
NPL.load("(gl)script/apps/Aries/Mods/Updates.lua")
local updates=MyCompany.Aries.HaqiModUpdates
local Mods=commonlib.gettable("MyCompany.Aries.HaqiMods")
local plugins=System.Plugins.PluginManager.CreateGetInstance("Haqi")
local folder=ParaIO.GetWritablePath().."config/"
local path=folder.."haqi-mods.json"
local enabled,active,world=nil,{},false
local official="HaqiWardrobe"
Mods.guide="https://github.com/LiXizhi/HaqiModKit"

local function community(name)
    return type(name)=="string" and name:match("^Haqi[%w_]+%.zip$") and name~="HaqiWardrobe.zip"
end
local function settings()
    if enabled then return enabled end
    local f=ParaIO.open(path,"r")
    enabled={}
    if f:IsValid() then
        local raw=f:GetFileSize()<262144 and f:GetText(0,-1)
        f:close()
        local ok,data=pcall(commonlib.Json.Decode,raw or "")
        if ok and type(data)=="table" then enabled=data end
    end
    return enabled
end
function Mods.Enabled(name)
    local value=settings()[name]
    return value==true or (name==official and value~=false)
end
function Mods.List()
    local rows={}
    for _,file in ipairs(commonlib.Files.Find(nil,"Mod/",0,10000,"*.zip") or {}) do
        if community(file.filename) then rows[#rows+1]={id=file.filename,title=file.filename} end
    end
    table.sort(rows,function(a,b) return a.id<b.id end)
    table.insert(rows,1,{id=official,title="彩虹衣柜 · 官方"})
    for _,row in ipairs(rows) do
        local m=updates.Local(row.id)
        row.version=m.version or (row.id==official and "尚未下载" or "未声明")
        row.title=m.name or (row.id==official and "彩虹衣柜" or row.id:gsub("%.zip$",""))
        row.source=row.id==official and "官方" or "社区"
        row.enabled=Mods.Enabled(row.id)
        row.pending=m.pending
        row.online=row.id==official or m.feed~=nil
    end
    return rows
end
local function wardrobe()
    NPL.load("(gl)script/apps/Aries/HaqiShop/WardrobeChannel.lua")
    return MyCompany.Aries.HaqiShop.WardrobeChannel
end
local function start(name)
    if active[name] then return end
    if name==official then wardrobe().EnterWorld()
    else
        local mod=plugins:GetMod(name)
        if not mod then
            assert(plugins:GetLoader():LoadPlugin(name),"无法加载 Mod ZIP")
            mod=assert(plugins:GetMod(name),"Mod 没有注册")
        end
        mod:InvokeMethod("OnWorldLoad")
    end
    active[name]=true
end
local function stop(name)
    if name==official then wardrobe().LeaveWorld()
    elseif active[name] then plugins:GetMod(name):InvokeMethod("OnLeaveWorld") end
    active[name]=nil
end
function Mods.SetEnabled(name,value)
    if (name~=official and not community(name)) or type(value)~="boolean" then return false end
    if value and name~=official and not ParaIO.DoesFileExist("Mod/"..name,false) then return false,"找不到 ZIP" end
    local data=commonlib.clone(settings())
    data[name]=value
    local raw=commonlib.Json.Encode(data)
    ParaIO.CreateDirectory(folder)
    local tmp=path.."."..ParaGlobal.GenerateUniqueID()
    local f=ParaIO.open(tmp,"w")
    if not f:IsValid() then return false,"无法保存 Mod 设置" end
    f:write(raw,#raw);f:close()
    local change=value and start or stop
    local apply=world or not value
    local wasActive=active[name]
    if apply then
        local ok,err=pcall(change,name)
        if not ok then ParaIO.DeleteFile(tmp);return false,tostring(err) end
    end
    if not ParaIO.MoveFile(tmp,path) then
        ParaIO.DeleteFile(tmp)
        if apply and wasActive~=active[name] then pcall(wasActive and start or stop,name) end
        return false,"无法保存 Mod 设置"
    end
    enabled=data
    return true
end
function Mods.EnterWorld()
    if world then return end
    updates.ApplyPending()
    world=true
    local data=settings()
    local function enter(name)
        local ok,err=pcall(start,name)
        if not ok then LOG.std(nil,"error","HaqiMods","%s: %s",name,tostring(err)) end
    end
    if Mods.Enabled(official) then enter(official) end
    for name,value in pairs(data) do if community(name) and value==true then enter(name) end end
end
function Mods.LeaveWorld()
    world=false
    local hadWardrobe=active[official]
    for name in pairs(active) do
        local ok,err=pcall(stop,name)
        if not ok then active[name]=nil;LOG.std(nil,"error","HaqiMods","%s: %s",name,tostring(err)) end
    end
    -- The shop can open before the first world callback.
    if not hadWardrobe and commonlib.getfield("MyCompany.Aries.HaqiShop.WardrobeChannel") then wardrobe().LeaveWorld() end
end
function Mods.RefreshView()
    if Mods.page and Mods.page:IsVisible() then Mods.page:Refresh(0.05) end
end
function Mods.Open()
    NPL.load("(gl)script/ide/System/Windows/Screen.lua")
    System.Windows.Screen:Connect("sizeChanged",Mods,Mods.RefreshView,"UniqueConnection")
    System.App.Commands.Call("File.MCMLWindowFrame",{url="script/apps/Aries/Mods/Manager.html",
        name="HaqiMods",app_key=MyCompany.Aries.app.app_key,zorder=360,enable_esc_key=true,text="Mod 管理",isShowTitleBar=false,style=CommonCtrl.WindowFrame.ContainerStyle,allowDrag=false,directPosition=true,align="_fi",
        x=0,y=0,width=0,height=0,cancelShowAnimation=true,DestroyOnClose=true})
end
function Mods.Connect()
    if System.options.IsWebBrowser or System.os.GetPlatform()=="emscripten" then return "请在桌面客户端连接本机 AI" end
    NPL.load("(gl)script/apps/WebServer/WebServer.lua")
    if not WebServer:IsStarted() then WebServer:Start("script/apps/WebServer/admin","127.0.0.1",8099) end
    local config=WebServer:GetServerConfig()
    if config and config.server and config.server.ip=="127.0.0.1" then
        return "本机 paracraft-cli 端口 "..tostring(config.server.port)
    end
    return "未能连接本机 CLI"
end
