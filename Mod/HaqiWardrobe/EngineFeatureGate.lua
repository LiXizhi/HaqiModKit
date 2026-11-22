-- Shared script-only entry gate for Haqi features. Check the real engine,
-- then optionally test a capability shared by builds with the same version.
NPL.load("(gl)script/ide/commonlib.lua")
NPL.load("(gl)script/ide/timer.lua")
NPL.load("(gl)script/ide/Json.lua")
local Gate=commonlib.gettable("MyCompany.Aries.EngineFeatureGate")
Gate.wardrobe={name="彩虹衣柜",minimum="1.9.1.0",capability="glb"}
local official="https://haqi.keepwork.com/"
local statusURL="https://cdn.keepwork.com/haqi/features/haqi-platforms.json"
local platforms={{"web","网页版"},{"windows","Windows"},{"mac","Mac"},{"android","安卓"},{"ios","iOS"}}
local screen="haqi-engine-feature-guide"

local function version(s)
    if type(s)~="string" or not s:match("^%d+[%.%d]*$") or s:match("%.%.") or s:sub(-1)=="." then return end
    local v={}
    for n in s:gmatch("%d+") do v[#v+1]=tonumber(n) end
    if #v<=4 then return v end
end

function Gate.AtLeast(current,minimum)
    local a,b=version(current),version(minimum)
    if not a or not b then return false end
    for i=1,4 do
        local x,y=a[i] or 0,b[i] or 0
        if x~=y then return x>y end
    end
    return true
end

local function installed()
    return ParaEngine.GetVersion and tostring(ParaEngine.GetVersion() or "") or ""
end

local function validate(data)
    if type(data)~="table" or data.schema~=1 or type(data.asOf)~="string" or not data.asOf:match("^%d%d%d%d%-%d%d%-%d%d$") then return end
    for _,row in ipairs(platforms) do
        local value=data[row[1]]
        if type(value)~="string" or #value>120 or value:find("%c") then return end
    end
    return data
end

local function snapshot()
    for _,path in ipairs({"Mod/HaqiWardrobe/haqi-platforms.json","script/apps/Aries/Service/haqi-platforms.json"}) do
        local f=ParaIO.open(path,"r")
        if f:IsValid() then
            local raw=f:GetText(0,-1);f:close()
            local ok,d=pcall(commonlib.Json.Decode,raw)
            if ok and validate(d) then return d end
        end
    end
end

function Gate.Close()
    local view=Gate.view
    Gate.view=nil
    ParaUI.Destroy(screen)
    if view and view.onClose then view.onClose() end
end

local function externalBrowser(url)
    if ParaGlobal.ShellExecute("openExternalBrowser",url,"","",1) then return true end
    -- Older Windows engines may lack the dedicated verb. Explorer dispatches
    -- the HTTPS URL to the user's registered browser outside the game.
    local osId=System and System.os and System.os.GetPlatform and System.os.GetPlatform()
    if osId=="win32" or osId=="win64" then
        return ParaGlobal.ShellExecute("open","explorer.exe",url,"",1)
    end
end

function Gate.OpenOfficial()
    if not externalBrowser(official) then
        if ParaMisc.CopyTextToClipboard then ParaMisc.CopyTextToClipboard(official) end
        if Gate.view then Gate.view.link.text="请在浏览器打开 haqi.keepwork.com" end
    end
end

function Gate.Download()
    local view=Gate.view
    if not view then return end
    if view.download then
        if not externalBrowser(view.download) then Gate.OpenOfficial() end
    elseif ParaMisc.CopyTextToClipboard then
        ParaMisc.CopyTextToClipboard(official)
        view.link.text="已复制官网网址"
    end
end

function Gate.Show(feature,reason,onClose)
    Gate.Close()
    local root=ParaUI.CreateUIObject("container",screen,"_fi",0,0,0,0)
    root.zorder=1000;root.background="Texture/whitedot.png";root.color="25 46 42 207";root:AttachToRoot()
    local _,_,w,h=root:GetAbsPosition()
    local s=math.min(1,w/572,h/478)
    local function px(n) return math.floor(n*s+.5) end
    local panel=ParaUI.CreateUIObject("container","guide","_ct",-px(280),-px(232),px(560),px(464))
    panel.background="Texture/whitedot.png";panel.color="255 252 242";root:AddChild(panel)
    local function box(name,x,y,w,h,color)
        local e=ParaUI.CreateUIObject("container",name,"_lt",px(x),px(y),px(w),px(h))
        e.background="Texture/whitedot.png";e.color=color;panel:AddChild(e)
    end
    local function label(name,x,y,w,h,value,size,color,bold)
        local e=ParaUI.CreateUIObject("text",name,"_lt",px(x),px(y),px(w),px(h))
        e.font="System;"..math.max(9,px(size))..";"..(bold and "bold" or "norm")
        e.text=value;e.shadow=false;e:GetFont("text").color=color;panel:AddChild(e);return e
    end
    local function hit(name,x,y,w,h,method)
        local e=ParaUI.CreateUIObject("button",name,"_lt",px(x),px(y),px(w),px(h))
        e.background="";e.onclick=";MyCompany.Aries.EngineFeatureGate."..method.."();";panel:AddChild(e)
    end
    local ink="42 71 62"
    box("line",0,0,560,5,"54 108 88")
    label("title",28,20,480,33,reason and "这个功能需要更新引擎" or "各平台发布情况",24,ink,true)
    label("dismiss",511,18,28,28,"×",22,ink,true);hit("close",499,10,48,44,"Close")
    local actual=installed()
    label("versions",28,65,506,23,feature.name.."  ·  本机引擎 "..(actual~="" and actual or "未知").."  /  需要 "..feature.minimum,15,ink)
    label("intro",28,94,503,25,reason or "可前往官网下载适合本机的客户端。",15,"91 92 73")
    label("policy",28,119,504,24,"可先用官网网页版体验。测试通过后，功能可能陆续发布到其他平台。",14,ink)
    label("heading",28,159,270,26,"官网客户端发布情况",18,ink,true)
    local stamp=label("date",331,161,201,22,"",13,"99 110 96")
    local rows={}
    for i,p in ipairs(platforms) do
        local y=198+(i-1)*34
        if i%2==1 then box("stripe"..i,22,y-3,516,31,"236 240 226") end
        label("platform"..i,34,y,105,25,p[2],15,ink,true)
        rows[p[1]]=label("release"..i,152,y,379,25,"待核实",15,ink)
    end
    box("cta",28,381,200,44,"49 100 81")
    label("action",42,391,185,32,"用浏览器体验网页版",17,"255 255 247",true)
    hit("preview",28,381,200,44,"OpenOfficial")
    box("secondary",246,381,192,44,"226 237 220")
    local secondary=label("downloadLabel",265,391,173,30,"复制官网网址",16,ink,true)
    hit("download",246,381,192,44,"Download")
    local link=label("link",28,432,495,25,"haqi.keepwork.com",14,ink)
    local view={link=link,onClose=onClose}
    Gate.view=view
    local function show(data)
        if Gate.view~=view or not stamp:IsValid() or not validate(data) or (view.date and data.asOf<view.date) then return end
        view.date=data.asOf;stamp.text="核实于 "..data.asOf
        for k,e in pairs(rows) do e.text=data[k] end
        local osId=System and System.os and System.os.GetPlatform and System.os.GetPlatform()
        local windows=osId=="win32" or osId=="win64"
        local key=windows and "windows" or osId=="android" and "android"
        local url=key and type(data.downloads)=="table" and data.downloads[key]
        local pattern=windows and "^https://cdn%.keepwork%.com/haqi/[%w_.%-]+%.exe$" or "^https://cdn%.keepwork%.com/dist/haqi/[%w_.%-]+%.apk$"
        view.download=type(url)=="string" and url:match(pattern)
        secondary.text=view.download and "下载最新版客户端" or "复制官网网址"
    end
    show(snapshot())
    if System and System.os and System.os.GetUrl then
        System.os.GetUrl(statusURL.."?v="..ParaGlobal.GenerateUniqueID(),function(status,_,data)
            if status==200 then
                if type(data)=="string" then local ok,v=pcall(commonlib.Json.Decode,data);data=ok and v end
                show(data)
            end
        end)
    end
end

-- Tiny local glTF triangle. IsLoaded on a ParaX asset requires a parsed model.
local function probeGLB()
    local folder="temp/haqi-feature-probes/"
    ParaIO.CreateDirectory(folder)
    local path=folder.."triangle-v1.glb"
    local function u32(n) return string.char(n%256,math.floor(n/256)%256,0,0) end
    local meta='{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"buffers":[{"byteLength":36}],"bufferViews":[{"buffer":0,"byteLength":36,"target":34962}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]}]}'
    meta=meta..string.rep(" ",(4-#meta%4)%4)
    local zero,one=u32(0),string.char(0,0,128,63)
    local bin=zero..zero..zero..one..zero..zero..zero..one..zero
    local bytes="glTF"..u32(2)..u32(28+#meta+#bin)..u32(#meta).."JSON"..meta..u32(#bin).."BIN\0"..bin
    local f=ParaIO.open(path,"w")
    assert(f:IsValid());f:write(bytes,#bytes);f:close()
    local asset=ParaAsset.LoadParaX("",path)
    assert(asset:IsValid());asset:LoadAsset()
    return asset
end

-- Gate.Run(feature, allowed, stillActive, quiet). A module without a
-- capability requirement only needs a display name and a dotted minimum version.
function Gate.Run(feature,allowed,stillActive,quiet,denied)
    local function done(ok,reason)
        if stillActive and not stillActive() then return end
        if ok then allowed() elseif denied then denied(reason) elseif not quiet then Gate.Show(feature,reason) end
    end
    if not Gate.AtLeast(installed(),feature.minimum) then
        done(false,"请到官网下载最新版客户端，或先在网页版预览。");return
    end
    if not feature.capability then done(true);return end
    if feature.capability~="glb" then done(false,"当前引擎无法使用此功能，请先在网页版预览。");return end
    if Gate.glbReady then done(true);return end
    if Gate.waiters then table.insert(Gate.waiters,done);return end
    Gate.waiters={done}
    local ok,asset=pcall(probeGLB)
    local start=ParaGlobal.timeGetTime()
    local function settle(works)
        local list=Gate.waiters
        Gate.waiters=nil;Gate.glbReady=works
        for _,cb in ipairs(list) do cb(works,"当前引擎无法显示 GLB 配饰。请更新客户端或使用网页版。") end
    end
    if not ok then settle(false);return end
    if asset:IsLoaded() then settle(true);return end
    local timer=commonlib.Timer:new({callbackFunc=function(t)
        local loaded=asset:IsLoaded()
        if loaded or ParaGlobal.timeGetTime()-start>=5000 then t:Change();settle(loaded) end
    end})
    timer:Change(20,50)
end
