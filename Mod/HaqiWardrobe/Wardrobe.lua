NPL.load("(gl)script/ide/commonlib.lua")
NPL.load("(gl)script/ide/Json.lua")
NPL.load("(gl)script/ide/timer.lua")
NPL.load("(gl)Mod/HaqiWardrobe/Assets.lua")
NPL.load("(gl)Mod/HaqiWardrobe/Skin.lua")
local W=commonlib.gettable("Mod.HaqiWardrobe.Wardrobe")
local A=Mod.HaqiWardrobe.Assets
local active,pending={},{}
local timer
local firstSlot=41000
-- Existing kids equipment selects these X geosets. Its fabric is replaced on this actor.
local styles={
    {16,"8",{[1]=11,[8]=1075,[16]=1072}},
    {17,"9",{[1]=1002,[3]=1006,[6]=1029}},
    {19,"5",{[1]=205,[3]=1007,[5]=2078,[7]=1024}},
}
local function shapeItems(look)
    local slots={}
    for _,p in ipairs(styles) do
        slots[p[1]]=assert(p[3][look.geosets[p[2]]],"Unknown stock Elf clothing shape")
    end
    return slots
end
function W.Load()
    local f=ParaIO.open("Mod/HaqiWardrobe/catalog.json","r")
    assert(f:IsValid(),"Missing wardrobe catalog")
    local catalog=commonlib.Json.Decode(f:GetText(0,-1))
    f:close()
    assert(catalog.version==2 and type(catalog.base)=="string","Invalid wardrobe catalog")
    local ids={}
    for _,look in ipairs(catalog.looks) do
        assert(not ids[look.id],"Duplicate outfit ID")
        look.base=catalog.base
        ids[look.id]=look
    end
    return catalog.looks,ids
end
function W.Clear(actor)
    if not actor or not actor:IsValid() then return end
    local id=actor:GetID()
    pending[id]=nil
    local s=active[id]
    if not s then return end
    active[id]=nil
    local ch=actor:ToCharacter()
    for i,p in ipairs(s.look.attachments) do ch:RemoveAttachment(p.socket,firstSlot+i) end
    for k,v in pairs(s.previous) do
        if ch:GetCharacterSlotItemID(k)==s.applied[k] then ch:SetCharacterSlot(k,v) end
    end
    if s.ears~=nil then ch:SetDisplayOptions(-1,s.ears,-1) end
    if s.hair~=nil then ch:SetDisplayOptions(-1,-1,s.hair) end
    if s.texture then ch:RefreshModel() end
end
local function pose(s,seconds)
    local ch=s.actor:ToCharacter()
    if s.hair~=nil and ch:GetDisplayOptions(2) then ch:SetDisplayOptions(-1,-1,0) end
    if s.ears~=nil and ch:GetDisplayOptions(1) then ch:SetDisplayOptions(-1,0,-1) end
    for i,p in ipairs(s.look.attachments) do
        local key=p.asset
        if p.frames then key=p.frames[1+math.floor(((seconds/p.period+p.phase)%1)*#p.frames)] end
        if s.showing[i]~=key then
            if s.showing[i] then ch:RemoveAttachment(p.socket,firstSlot+i) end
            ch:AddAttachment(ParaAsset.LoadParaX("",A.path(key)),p.socket,firstSlot+i,p.scale or 1)
            s.showing[i]=key
        end
    end
    if s.texture and s.actor:GetReplaceableTexture(1):GetKeyName()~=s.texture:GetKeyName() then
        s.actor:SetReplaceableTexture(1,s.texture)
    end
end

function W.PoseAt(actor,seconds)
    local s=active[actor:GetID()]
    if s then pose(s,seconds) end
end
local function tick(self)
    local now=ParaGlobal.timeGetTime()
    for id,s in pairs(active) do
        if s.actor:IsValid() then pose(s,(now-s.start)/1000) else active[id]=nil end
    end
    if not next(active) then self:Change() end
end
-- Called after assets have been verified. Any public equip call uses TryOn below.
local function equip(actor,look)
    local ch=actor:ToCharacter()
    local texture,items
    if look.kind~="model" then
        assert(ch:IsCustomModel(),"Choose a Haqi Elf actor")
        texture=Mod.HaqiWardrobe.Skin.forActor(actor,look)
        items=shapeItems(look)
    end
    W.Clear(actor)
    local s={actor=actor,look=look,texture=texture,start=ParaGlobal.timeGetTime(),previous={},applied={},showing={}}
    active[actor:GetID()]=s
    local changes=items or {}
    for _,k in ipairs(look.hideSlots or {}) do changes[k]=changes[k] or 0 end
    for k,v in pairs(changes) do
        s.previous[k]=ch:GetCharacterSlotItemID(k)
        s.applied[k]=v
        ch:SetCharacterSlot(k,v)
    end
    for _,p in ipairs(look.attachments) do
        if p.coversHair and s.hair==nil then s.hair=ch:GetDisplayOptions(2) and 1 or 0; ch:SetDisplayOptions(-1,-1,0) end
        if p.coversEars and s.ears==nil then s.ears=ch:GetDisplayOptions(1) and 1 or 0; ch:SetDisplayOptions(-1,0,-1) end
    end
    if texture then ch:RefreshModel() end
    pose(s,0)
    if not timer then timer=commonlib.Timer:new({callbackFunc=tick}) end
    if not timer:IsEnabled() then timer:Change(50,50) end
    return actor
end
function W.TryOn(actor,look,callback)
    assert(actor and actor:IsValid() and look and look.kind~="model","Select a CCS outfit and an Elf")
    local id,request=actor:GetID(),{}
    pending[id]=request
    A.prepare(look,function(ok,err)
        if pending[id]~=request then return end
        pending[id]=nil
        if not actor:IsValid() then return end
        if ok then ok,err=pcall(equip,actor,look) end
        if callback then callback(ok,err) elseif not ok then log("Wardrobe: "..tostring(err).."\n") end
    end)
end
function W.Create(name,look)
    local model=look.kind=="model" and A.path(look.model) or look.model
    local actor=ParaScene.CreateCharacter(name,ParaAsset.LoadParaX("",model),"",true,.35,3.2,1)
    assert(actor:IsValid(),"Cannot create fitting room actor")
    if look.kind~="model" then actor:ToCharacter():SetBodyParams(0,1,0,1,1) end
    if look.animation then actor:SetField("AnimID",look.animation) end
    return equip(actor,look)
end
