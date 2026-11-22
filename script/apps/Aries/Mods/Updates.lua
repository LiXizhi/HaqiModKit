-- Read package metadata without mounting or executing a community ZIP.
NPL.load("(gl)script/ide/Json.lua")
NPL.load("(gl)script/ide/timer.lua")
NPL.load("(gl)script/apps/Aries/HaqiShop/WardrobeChannel.lua")
local U=commonlib.gettable("MyCompany.Aries.HaqiModUpdates")
local channel=MyCompany.Aries.HaqiShop.WardrobeChannel
local official="HaqiWardrobe"
local pending="Mod/.haqi-pending/"
local staging=ParaIO.GetWritablePath().."temp/haqi-mod-updates/"
local jobs,sequence={},0
local limit=32*1024*1024

local function read(path,max,tail)
    local f=ParaIO.open(path,"r")
    if not f:IsValid() then return end
    local size=f:GetFileSize()
    local bytes
    if tail or size<=max then
        local count=math.min(size,max)
        bytes=f:GetText(tail and size-count or 0,count)
    end
    f:close()
    return bytes
end
local function decode(raw)
    if not raw then return end
    local ok,value=pcall(commonlib.Json.Decode,raw)
    if ok and type(value)=="table" then return value end
end
local function version(value)
    return type(value)=="string" and #value<=23 and value:match("^%d+%.%d+%.%d+$")
end
local function newer(a,b)
    if not b then return true end
    local nextB=b:gmatch("%d+")
    for part in a:gmatch("%d+") do
        local x,y=tonumber(part),tonumber(nextB())
        if x~=y then return x>y end
    end
    return false
end
local function feed(url)
    return type(url)=="string" and #url<=512 and url:match("^https://[%w%.%-]+/[%w_%.~/%-]+%.json$") and not url:find("..",1,true)
end
local function metadata(path,id)
    local tail=read(path,4120,true)
    if not tail then return end
    local pos=tail:find("PK\5\6",1,true)
    while pos and pos+21<=#tail do
        local a,b=tail:byte(pos+20,pos+21)
        if pos+21+a+256*b==#tail then
            local m=decode(tail:sub(pos+22))
            if m and type(m.id)=="string" and m.id..".zip"==id and version(m.version) then
                return {version=m.version,name=type(m.name)=="string" and #m.name<=80 and not m.name:find("%c") and m.name or nil,
                    feed=feed(m.feed) and m.feed or nil}
            end
            return
        end
        pos=tail:find("PK\5\6",pos+1,true)
    end
end
-- Inspect the central directory before replacing a working package. Its only
-- entry point must belong to the Mod being updated, independently of the label.
local function numberLE(data,pos,n)
    local v=0
    for i=n-1,0,-1 do v=v*256+data:byte(pos+i) end
    return v
end
local function packageBytes(path,id)
    local raw=read(path,limit)
    if not raw or raw:sub(1,4)~="PK\3\4" then return end
    local ending=raw:find("PK\5\6",math.max(1,#raw-4118),true)
    while ending and (ending+21>#raw or ending+21+numberLE(raw,ending+20,2)~=#raw) do
        ending=raw:find("PK\5\6",ending+1,true)
    end
    if not ending then return end
    local n=numberLE(raw,ending+10,2)
    local pos=numberLE(raw,ending+16,4)+1
    if n==0 or pos+numberLE(raw,ending+12,4)~=ending then return end
    local prefix="Mod/"..id:sub(1,-5).."/"
    local main=false
    for i=1,n do
        if pos+45>=ending or raw:sub(pos,pos+3)~="PK\1\2" then return end
        local size=numberLE(raw,pos+28,2)
        local name=raw:sub(pos+46,pos+45+size)
        if name:sub(1,#prefix)~=prefix or name:find("\\",1,true) or name:find("/../",1,true) or name:find("%c") then return end
        if name==prefix.."main.lua" then
            if main or numberLE(raw,pos+24,4)==0 then return end
            main=true
        end
        pos=pos+46+size+numberLE(raw,pos+30,2)+numberLE(raw,pos+32,2)
    end
    if main and pos==ending then return raw end
end
function U.Local(id)
    if id==official then
        local d=channel.Installed()
        return {version=d and (d.version or d.revision:sub(1,8)),digest=d and d.digest}
    end
    local m=metadata("Mod/"..id,id) or {}
    local staged=metadata(pending..id,id)
    m.pending=staged and staged.version
    return m
end
function U.ApplyPending()
    -- Once per process, before loading community scripts; mounted ZIPs can be locked.
    if U.started then return end
    U.started=true
    for _,entry in ipairs(commonlib.Files.Find(nil,pending,0,10000,"*.zip") or {}) do
        local id=entry.filename
        if id:match("^Haqi[%w_]+%.zip$") then
            local staged=metadata(pending..id,id)
            local installed=metadata("Mod/"..id,id)
            if not ParaIO.DoesFileExist("Mod/"..id,false) or not staged or not newer(staged.version,installed and installed.version) or not packageBytes(pending..id,id) then
                ParaIO.DeleteFile(pending..id)
            elseif not ParaIO.MoveFile(pending..id,"Mod/"..id) then
                U.notice="更新写入失败，请检查 Mod 文件夹的写入权限"
            end
        end
    end
end
local function download(url,cb)
    sequence=sequence+1
    local n=sequence
    ParaIO.CreateDirectory(staging)
    local path=staging..ParaGlobal.GenerateUniqueID()..".part"
    local timer=commonlib.Timer:new({callbackFunc=function() U.Done(n,"timeout") end})
    jobs[n]={path=path,cb=cb,timer=timer}
    timer:Change(20000,nil)
    NPL.AsyncDownload(url,path,string.format(";MyCompany.Aries.HaqiModUpdates.Done(%d,msg.DownloadState);",n),path)
end
function U.Done(n,state)
    local job=jobs[n]
    if not job or (state~="complete" and state~="terminated" and state~="timeout") then return end
    jobs[n]=nil
    job.timer:Change()
    if state=="timeout" then NPL.CancelDownload(job.path) end
    job.cb(state=="complete" and job.path or nil)
    ParaIO.DeleteFile(job.path)
end
function U.Check(id,cb)
    local m=U.Local(id)
    if m.pending then cb(nil,"重启后生效");return end
    if id~=official then
        local path="Mod/updates/"..id
        local candidate=metadata(path,id)
        if candidate and newer(candidate.version,m.version) then
            cb({path=path,version=candidate.version},"可更新");return
        end
        if not m.feed then cb(nil,"本地 ZIP");return end
    end
    local url=id==official and channel.UpdateSource() or m.feed
    download(url.."?v="..ParaGlobal.GenerateUniqueID(),function(path)
        if not path then cb(nil,"检查失败");return end
        if id==official then
            local d=channel.Release(path)
            if not d then cb(nil,"版本信息无效");return end
            if d.digest==m.digest then cb(nil,"已是最新");return end
            d.url=url:gsub("current%.json$",d.digest..".zip")
            cb(d,m.digest and "可更新" or "可下载")
        else
            local d=decode(read(path,4096))
            if not d or type(d.id)~="string" or d.id..".zip"~=id or not version(d.version) or type(d.sha1)~="string" or #d.sha1~=40 or not d.sha1:match("^[0-9a-f]+$") then
                cb(nil,"版本信息无效");return
            end
            if not newer(d.version,m.version) then cb(nil,"已是最新");return end
            cb({url=url:match("^(.*/)")..id.."?v="..d.sha1,version=d.version,digest=d.sha1},"可更新")
        end
    end)
end
function U.Install(id,d,cb)
    local function install(path)
        if not path then cb(false,"下载失败，可以重试");return end
        if id==official then cb(channel.Prepare(d,path));return end
        local m=metadata(path,id)
        local raw=packageBytes(path,id)
        if not m or m.version~=d.version or not raw or (d.digest and ParaMisc.sha1(raw)~=d.digest) then
            cb(false,"更新包校验失败");return
        end
        local current=U.Local(id)
        if not newer(m.version,current.pending or current.version) then cb(false,"已有相同或更新版本");return end
        ParaIO.CreateDirectory(pending)
        local tmp=pending..ParaGlobal.GenerateUniqueID()..".part"
        local f=ParaIO.open(tmp,"w")
        if not f:IsValid() then cb(false,"无法保存更新包");return end
        f:write(raw,#raw);f:close()
        if not ParaIO.MoveFile(tmp,pending..id) then
            ParaIO.DeleteFile(tmp);cb(false,"无法保存更新包");return
        end
        cb(true,"已保存更新，重启客户端后生效")
    end
    if d.path then install(d.path) else download(d.url,install) end
end

-- Keep asynchronous results when the manager is closed or paged.
local states={}
function U.State(id)
    states[id]=states[id] or {}
    return states[id]
end
local function changed()
    if U.onChange then U.onChange() end
end
function U.CheckAll(rows)
    for _,row in ipairs(rows) do
        local id=row.id
        local state=U.State(id)
        if not state.busy then
            state.busy=true
            state.text="检查中…"
            state.candidate=nil
            U.Check(id,function(candidate,message)
                state.busy=false
                state.candidate=candidate
                state.text=message
                changed()
            end)
        end
    end
    changed()
end
function U.Update(id,candidate)
    local state=U.State(id)
    if state.busy or not candidate then return end
    state.busy=true
    state.text="正在更新…"
    changed()
    U.Install(id,candidate,function(ok,message)
        state.busy=false
        if ok then state.candidate=nil end
        state.text=ok and (id==official and "已就绪" or "重启后生效") or "更新失败"
        U.notice=message
        changed()
    end)
end
function U.Import(id,path)
    if not path or path=="" then return end
    local m=metadata(path,id)
    if not m then U.notice="请选择同一个 Mod 的带版本 ZIP";changed();return end
    U.Update(id,{path=path,version=m.version})
end
