NPL.load("(gl)Mod/HaqiWardrobe/DIY.lua")
local Mix=commonlib.gettable("Mod.HaqiWardrobe.Mix")
Mix.order={"top","lower","shoes","head","back","trim","effect"}
Mix.labels={top="上装",lower="下装",shoes="鞋履",head="头饰",back="背饰",trim="裙饰",effect="特效"}
local fabrics={top="8",lower="9",shoes="5"}

function Mix.contains(look,group)
    if fabrics[group] then return look.atlas~=nil end
    for _,p in ipairs(look.attachments) do if p.group==group then return true end end
    return false
end

function Mix.full(look)
    local parts={}
    for _,group in ipairs(Mix.order) do
        if Mix.contains(look,group) then parts[group]=look.id end
    end
    return parts
end

function Mix.resolve(parts,ids)
    local top=assert(ids[parts.top],"Missing top")
    local look={kind="ccs",id="local-mix",name="自由搭配",base=top.base,model=top.model,
        hideSlots=top.hideSlots,geosets={},regions={},attachments={}}
    for _,group in ipairs(Mix.order) do
        local owner=parts[group] and assert(ids[parts[group]],"Unknown outfit")
        local geo=fabrics[group]
        if geo then
            assert(owner and owner.atlas,"Missing clothing fabric")
            look.regions[group]=owner.atlas
            look.geosets[geo]=owner.geosets[geo]
        elseif owner then
            assert(Mix.contains(owner,group),"Unavailable accessory")
            for _,p in ipairs(owner.attachments) do
                if p.group==group then look.attachments[#look.attachments+1]=p end
            end
        end
    end
    if parts.textures then
        look.userImages={}
        for group,url in pairs(parts.textures) do
            assert(fabrics[group],"Unknown texture region")
            local id=assert(Mod.HaqiWardrobe.DIY.image(url),"Invalid user CDN texture")
            look.regions[group]=id
            look.userImages[id]=url
        end
    end
    return look
end
