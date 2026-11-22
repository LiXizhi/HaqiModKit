-- Resolve only the objects needed for the requested outfit. Source art is never mounted.
local A = commonlib.gettable("Mod.HaqiWardrobe.Assets")
local active, verified = {}, {}
local folder = "temp/haqi-wardrobe/objects/"
ParaIO.CreateDirectory(folder)
local function matches(path, id, userImage)
    local f = ParaIO.open(path, "r")
    if not f:IsValid() then return false end
    if userImage and f:GetFileSize()>Mod.HaqiWardrobe.DIY.maxBytes then f:close();return false end
    local data = f:GetText(0,-1)
    f:close()
    if userImage then
        -- Signature, IHDR length/type, 512×512, 8-bit RGBA.
        local header="\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\2\0\0\0\2\0\8\6"
        if not data or data:sub(1,#header)~=header then return false end
    end
    return data and ParaMisc.sha1(data) == id:sub(1,40)
end

function A.path(id)
    assert(type(id)=="string" and #id==44 and id:match("^%x+%.%w+$") and
        (id:sub(41)==".glb" or id:sub(41)==".png"),"Invalid wardrobe asset")
    return folder..id
end

function A.downloaded(id, status)
    local job = active[id]
    if not job or (status~="complete" and status~="terminated") then return end
    local path = A.path(id)
    local ok = status=="complete" and matches(job.tmp,id,job.userImage) and ParaIO.CopyFile(job.tmp,path,true)
    ParaIO.DeleteFile(job.tmp)
    active[id]=nil
    if ok then verified[id]=job.userImage or true end
    for _,cb in ipairs(job.callbacks) do
        if ok then cb(path) else cb(nil,"Could not load "..id) end
    end
end

function A.fetch(base,id,cb,userImage)
    local path=A.path(id)
    if (verified[id] and (not userImage or verified[id]==userImage) and ParaIO.DoesFileExist(path,false)) or matches(path,id,userImage) then
        verified[id]=userImage or true
        cb(path)
        return
    end
    if active[id] then
        active[id].userImage=active[id].userImage or userImage
        table.insert(active[id].callbacks,cb)
        return
    end
    local tmp=path.."."..tostring(ParaGlobal.GenerateUniqueID())..".part"
    active[id]={tmp=tmp,callbacks={cb},userImage=userImage}
    NPL.AsyncDownload(userImage or base..id,tmp,string.format(";Mod.HaqiWardrobe.Assets.downloaded(%q,msg.DownloadState);",id),tmp)
end

function A.prepare(look,cb)
    local files={}
    for _,id in pairs(look.regions or {}) do files[id]=true end
    if look.atlas then files[look.atlas]=true end
    if look.kind=="model" then files[look.model]=true end
    for _,p in ipairs(look.attachments) do
        if p.frames then for _,v in ipairs(p.frames) do files[v]=true end else files[p.asset]=true end
    end
    local count=0
    for id in pairs(files) do A.path(id); count=count+1 end
    if count==0 then cb(true); return end
    local failed
    for id in pairs(files) do
        A.fetch(look.base,id,function(path,err)
            if not path then failed=err end
            count=count-1
            if count==0 then cb(not failed,failed) end
        end,look.userImages and look.userImages[id])
    end
end
