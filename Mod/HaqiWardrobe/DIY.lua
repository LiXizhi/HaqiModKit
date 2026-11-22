-- Player recipes contain catalog selections and an optional immutable user CDN texture.
local DIY=commonlib.gettable("Mod.HaqiWardrobe.DIY")
local groups={top=true,lower=true,shoes=true,head=true,back=true,trim=true,effect=true}
local fabric={top=true,lower=true,shoes=true}
DIY.maxBytes=200*1024

function DIY.image(url)
    if type(url)~="string" or #url>512 then return end
    local owner,id=url:match("^https://cdn%.keepwork%.com/users/([^/]+)/wardrobe/([0-9a-f]+%.png)$")
    if owner and owner~="." and owner~=".." and #id==44 then
        local safe=owner:gsub("%%[89a-fA-F]%x","x")
        if safe:match("^[%w_.~%-]+$") then return id end
    end
end

function DIY.parse(raw,ids)
    if type(raw)~="string" or #raw>8192 then return nil,"方案请控制在 8 KB 以内" end
    raw=raw:match("^%s*```[jJ]?[sS]?[oO]?[nN]?%s*(.-)%s*```%s*$") or raw
    local ok,r=pcall(commonlib.Json.Decode,raw)
    if not ok or type(r)~="table" or r.version~=1 then return nil,"需要 version 为 1 的 JSON 方案" end
    local base=ids[r.base]
    if not base or not base.atlas then return nil,"基础套装 ID 不在衣柜里" end
    local mix=Mod.HaqiWardrobe.Mix
    local parts=mix.full(base)
    if r.parts~=nil and type(r.parts)~="table" then return nil,"parts 需要填写部件表" end
    for group,id in pairs(r.parts or {}) do
        if not groups[group] then return nil,"方案含有未知部件" end
        if id==false and not fabric[group] then parts[group]=nil
        elseif type(id)=="string" and ids[id] and mix.contains(ids[id],group) then parts[group]=id
        else return nil,"请检查"..mix.labels[group].."的款式 ID" end
    end
    if r.texture~=nil then
        if not DIY.image(r.texture) then return nil,"贴图需要使用发布工具返回的 Keepwork 图片地址" end
        parts.textures={top=r.texture,lower=r.texture,shoes=r.texture}
    end
    if r.name~=nil and (type(r.name)~="string" or #r.name>60 or r.name:find("%c")) then
        return nil,"造型名过长或含有换行"
    end
    parts.name=r.name~="" and r.name or nil
    return parts
end

function DIY.prompt(shop,ids)
    local lines={
        "请按我的描述或参考图为魔法哈奇设计本机造型。只返回一个 JSON 对象。",
        '格式示例 {"version":1,"name":"月光鲸","base":"deepseek-whale-maid","parts":{"head":"moon-moth","effect":"moon-moth","trim":false}}',
        "base 是整套的 ID。parts 可省略或覆盖下列部件，false 可卸下配饰。top 上装、lower 下装、shoes 鞋履、head 头饰、back 背饰、trim 裙饰、effect 特效。保留原角色脸部。",
        "可选：如能绘图，用基础套装的透明 PNG 作 UV 模板，保持 512×512 RGBA、每张最多 204800 字节。用衣柜 tools/diy.py publish 发布到自己的 Keepwork CDN；把返回的真实 URL 填入 texture。没有发布图片就省略 texture。",
        "工具与指南 https://github.com/LiXizhi/HaqiModKit",
        "可用套装 / 可换部件 / UV 模板："
    }
    for _,item in ipairs(shop.items) do
        local look=ids[item.id]
        local available={}
        for _,g in ipairs(Mod.HaqiWardrobe.Mix.order) do
            if Mod.HaqiWardrobe.Mix.contains(look,g) then available[#available+1]=g end
        end
        lines[#lines+1]=item.id.." "..item.title.." ("..table.concat(available,",")..") "..look.base..look.atlas
    end
    return table.concat(lines,"\n")
end
