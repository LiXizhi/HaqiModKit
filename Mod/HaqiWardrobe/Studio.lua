NPL.load("(gl)Mod/HaqiWardrobe/LocalLook.lua")
NPL.load("(gl)Mod/HaqiWardrobe/ShopArt.lua")
NPL.load("(gl)script/ide/gui_helper.lua")
if ParaIO.DoesFileExist("Mod/HaqiWardrobe/WardrobeTitle.lua",true) then
    NPL.load("(gl)Mod/HaqiWardrobe/WardrobeTitle.lua")
else
    NPL.load("(gl)script/apps/Aries/HaqiShop/WardrobeTitle.lua")
end
local Title=MyCompany.Aries.HaqiShop.WardrobeTitle
local M=Mod.HaqiWardrobe
local W,Mix,Local,Art=M.Wardrobe,M.Mix,M.LocalLook,M.ShopArt
local ink,muted,white="40 73 63","93 113 98","255 253 246"

local function open(requested,onClose)
    if ParaUI.GetUIObject("wardrobe-room"):IsValid() then return end
    local _,ids=W.Load()
    local shop=Art.read()
    local items={}
    for _,item in ipairs(shop.items) do items[item.id]=item end
    local initial=items[requested] or shop.items[1]
    local parts=Mix.full(ids[initial.id])
    local base=ids[initial.id].base
    local saved=Local.read(ids)
    local selected,group,page=initial,"set",1
    local appliedTitle=initial.title
    local state,ready,closed="",false,false
    local requestedLook=ids[requested]
    local standalone=requestedLook and requestedLook.kind=="model" and requestedLook
    local modelActor,framed
    local distance=3.28
    local angle=math.pi/2
    local root=ParaUI.CreateUIObject("container","wardrobe-room","_fi",0,0,0,0)
    root.background="Texture/whitedot.png"
    root.color="240 237 226"
    root.zorder=400
    root:AttachToRoot()
    local scene=ParaScene.GetMiniSceneGraph("wardrobe-live")
    scene:Reset()
    scene:SetRenderTargetSize(1024,1024)
    scene:EnableCamera(true)
    scene:EnableActiveRendering(false)
    for _,key in ipairs({"ShowSky","EnableFog","EnableLight","EnableSunLight"}) do scene:GetAttributeObject():SetField(key,false) end
    scene:SetBackGroundColor("0 0 0 0")
    scene:CameraSetLookAtPos(0,.72,0)
    local wearer=ParaScene.GetPlayer()
    local usePlayer=wearer and wearer:IsValid() and wearer:GetPrimaryAsset():GetKeyName():lower():find("/elf/",1,true)
    local model=usePlayer and wearer:GetPrimaryAsset() or ParaAsset.LoadParaX("",ids[initial.id].model)
    local actor=ParaScene.CreateCharacter("wardrobe-model",model,"",true,.35,3.2,1)
    assert(actor:IsValid(),"Cannot create wardrobe mannequin")
    local ch=actor:ToCharacter()
    if usePlayer then
        -- Use the player's own body, head and face as the preview baseline.
        local src=wearer:ToCharacter()
        ch:SetBodyParams(src:GetBodyParams(0),src:GetBodyParams(1),src:GetBodyParams(2),src:GetBodyParams(3),src:GetBodyParams(4))
        ch:SetSkinColorMask(src:GetSkinColorMask())
        for feature=0,6 do for prop=0,5 do ch:SetCartoonFaceComponent(feature,prop,src:GetCartoonFaceComponent(feature,prop)) end end
    else ch:SetBodyParams(0,1,0,1,1) end
    scene:AddChild(actor)

    local stage,scale,ox,oy,loop,refresh
    local designing,feedback=false,""
    local api=commonlib.gettable("MyCompany.Aries.HaqiWardrobeDIY")
    local uid=0
    local function element(kind,x,y,w,h)
        uid=uid+1
        local el=ParaUI.CreateUIObject(kind,"shop-"..uid,"_lt",math.floor(x*scale+.5),math.floor(y*scale+.5),math.ceil(w*scale),math.ceil(h*scale))
        el.background=""
        stage:AddChild(el)
        return el
    end
    local function picture(x,y,w,h,id,slice)
        local e=element("container",x,y,w,h)
        Art.image(e,base,id,slice)
        return e
    end
    local function text(x,y,w,h,value,size,color,center,bold)
        local e=element("text",x,y,w,h)
        e.font="System;"..math.max(9,math.floor(size*scale+.5))..";"..(bold and "bold" or "norm")
        e.text=value
        e.shadow=false
        e:GetFont("text").color=color or ink
        e:GetFont("text").format=32
        if center then e.x=e.x+math.max(0,math.floor((w*scale-e:GetTextLineSize())/2)) end
        e.y=e.y+math.max(0,math.floor((h-size-3)*scale/2))
        return e
    end
    local function hit(x,y,w,h,fn)
        local e=element("button",x,y,w,h)
        local n=#W.LiveActions+1
        W.LiveActions[n]=fn
        e.onclick=string.format(";Mod.HaqiWardrobe.Wardrobe.LiveActions[%d]();",n)
    end
    local function button(x,y,w,h,label,style,fn)
        picture(x,y,w,h,shop.chrome[style],true)
        text(x,y,w,h,label,15,style=="green" and white or ink,true)
        hit(x,y,w,h,fn)
    end
    local token=0
    local function dress()
        token=token+1
        local request=token
        if standalone then
            standalone=nil
            if modelActor then W.Clear(modelActor);scene:DestroyObject("wardrobe-import");modelActor=nil end
            actor:SetVisible(true)
            scene:CameraSetLookAtPos(0,.72,0)
            distance=3.28
        end
        ready=false
        state="正在试穿…"
        W.TryOn(actor,Mix.resolve(parts,ids),function(ok,err)
            if closed or request~=token then return end
            ready=ok
            state=ok and "" or "载入失败，点选款式重试"
            if not ok then log("Wardrobe: "..tostring(err).."\n") end
            refresh()
            if ok then log("WARDROBE_LIVE "..selected.id.."\n") end
        end)
        refresh()
    end
    function api.Preview(raw)
        local imported,err=M.DIY.parse(raw,ids)
        if not imported then return {ok=false,message=err} end
        parts=imported
        selected=items[parts.top]
        appliedTitle=parts.name or "我的原创造型"
        designing=true
        feedback=""
        dress()
        return {ok=true,message="已收到方案",name=appliedTitle}
    end
    function api.Status()
        return {ready=ready,message=state,name=appliedTitle}
    end
    local function choose(item)
        selected=item
        if group=="set" then parts=Mix.full(ids[item.id]);appliedTitle=item.title
        else
            parts[group]=item.id
            if parts.textures then parts.textures[group]=nil end
            parts.name=nil
            appliedTitle="我的混搭"
        end
        dress()
    end
    local function close()
        if closed then return end
        closed=true
        api.Preview=nil
        api.Status=nil
        if loop then loop:Change() end
        W.Clear(actor)
        if modelActor then W.Clear(modelActor) end
        ParaScene.DeleteMiniSceneGraph("wardrobe-live")
        ParaUI.Destroy("wardrobe-room")
        W.LiveActions={}
        M.Close=nil
        if onClose then onClose() end
    end
    M.Close=close
    local function showSaved()
        if not saved then state="还没有保存的搭配";refresh();return end
        parts=commonlib.clone(saved)
        selected=items[parts.top]
        designing=false
        appliedTitle=parts.name or "我的搭配"
        dress()
    end
    local function save()
        if not ready then return end
        local snapshot=commonlib.clone(parts)
        Local.save(snapshot,ids,function(ok,worn,err)
            if closed then return end
            saved=Local.read(ids)
            state=ok and (worn and "已穿戴 · 仅本机可见" or "搭配已保存到本机") or (worn and "穿戴失败，请重试" or "无法保存本机搭配")
            refresh()
        end)
    end
    refresh=function()
        if closed or not scale then return end
        if stage and stage:IsValid() then ParaUI.Destroy(stage.id) end
        stage=ParaUI.CreateUIObject("container","wardrobe-spread","_lt",ox,oy,math.ceil(1280*scale),math.ceil(720*scale))
        stage.background=""
        root:AddChild(stage)
        W.LiveActions={}
        picture(0,0,1280,720,shop.frame)
        for i,char in ipairs(Title.letters) do
            text(90+(i-1)*31,8,34,37,char,26,Title.rgb(Title.defaults[i]),false,true)
        end
        button(237,20,95,34,"角色 DIY","sage",function() designing=true;feedback="";refresh() end)
        button(345,20,99,34,"平台版本","cream",function() MyCompany.Aries.EngineFeatureGate.Show(Local.feature()) end)
        button(978,20,124,34,"我的搭配","cream",showSaved)
        button(1112,20,87,34,"还原穿戴","cream",function()
            Local.reset();saved=nil;state="已恢复本机原装";refresh()
        end)
        button(1209,20,39,34,"×","sage",close)
        local canvas=element("container",55,120,427,427)
        canvas:SetBGImage(scene:GetTexture())
        button(176,511,45,34,"‹","cream",function() angle=angle-math.pi/6 end)
        text(220,512,95,31,"旋转试穿",14,ink,true)
        button(316,511,45,34,"›","cream",function() angle=angle+math.pi/6 end)
        text(73,588,370,33,standalone and standalone.name or appliedTitle,25,ink,false,true)
        text(73,622,396,25,standalone and "独立模型预览" or appliedTitle==selected.title and selected.note or selected.title.."  ·  "..(Mix.labels[group] or "搭配预览"),15,muted)
        if designing then
            text(552,94,640,46,"设计我的角色",30,ink,false,true)
            text(553,145,670,30,"用你自己的 Codex、DeepSeek 或其他模型设计服饰。",16,muted)
            picture(551,210,697,136,shop.chrome.cream,true)
            text(574,222,620,34,"把衣柜交给 AI",21,ink,false,true)
            text(574,263,610,28,"复制设计说明，连同你的想法或参考图一起发给 AI。",16,muted)
            button(574,297,164,34,"复制设计说明","sage",function()
                ParaMisc.CopyTextToClipboard(M.DIY.prompt(shop,ids))
                feedback="设计说明已复制";refresh()
            end)
            picture(551,368,697,145,shop.chrome.cream,true)
            text(574,382,620,34,"看一眼新造型",21,ink,false,true)
            text(574,426,650,25,"复制 AI 返回的 JSON 方案，然后在这里试穿。",16,muted)
            button(574,462,164,34,"从剪贴板试穿","sage",function()
                local result=api.Preview(ParaMisc.GetTextFromClipboard())
                feedback=result.ok and "" or result.message;refresh()
            end)
            text(553,535,688,30,feedback~="" and feedback or state,16,muted)
            button(552,642,145,46,"返回衣柜","cream",function() designing=false;refresh() end)
            button(1036,641,212,48,"保存并穿戴",ready and "green" or "sage",save)
            return
        end
        text(551,91,320,40,group=="set" and "精选套装" or "单品衣橱",30,ink,false,true)
        text(552,130,310,24,group=="set" and "整套试穿，找到你的新造型。" or "选一件，搭进现在的造型。",15,muted)
        local function category(g) group=g;page=1;state="";refresh() end
        button(1064,98,87,37,"套装",group=="set" and "green" or "cream",function() category("set") end)
        button(1159,98,88,37,"单品",group~="set" and "green" or "cream",function() category("top") end)
        if group~="set" then
            for i,g in ipairs(Mix.order) do
                button(551+(i-1)*76,162,71,30,Mix.labels[g],g==group and "sage" or "cream",function() category(g) end)
            end
            if group~="top" and group~="lower" and group~="shoes" then
                button(1101,162,145,30,"卸下"..Mix.labels[group],"coral",function() parts[group]=nil;parts.name=nil;appliedTitle="我的混搭";dress() end)
            end
        else
            text(552,162,600,26,string.format("本期衣橱   /   %02d 套",#shop.items),14,muted)
        end
        local filtered={}
        for _,item in ipairs(shop.items) do if item.cards[group] then filtered[#filtered+1]=item end end
        local pages=math.max(1,math.ceil(#filtered/6))
        for slot=1,6 do
            local item=filtered[(page-1)*6+slot]
            if item then
                local x=551+(slot-1)%3*235
                local y=202+math.floor((slot-1)/3)*207
                picture(x,y,226,197,item.cards[group])
                local active=group~="set" and parts[group]==item.id and not (parts.textures and parts.textures[group])
                if group=="set" then
                    active=not (parts.textures and next(parts.textures))
                    local full=Mix.full(ids[item.id])
                    for _,g in ipairs(Mix.order) do if full[g]~=parts[g] then active=false;break end end
                end
                if active and not standalone then
                    picture(x-1,y-1,228,199,shop.chrome.active,true)
                    picture(x+147,y+8,68,26,shop.chrome.green,true)
                    text(x+147,y+7,68,26,"试穿中",13,white,true)
                end
                hit(x,y,226,197,function() choose(item) end)
            end
        end
        button(552,648,39,35,"‹","cream",function() page=(page-2)%pages+1;refresh() end)
        text(593,648,74,35,string.format("%02d / %02d",page,pages),15,muted,true)
        button(671,648,39,35,"›","cream",function() page=page%pages+1;refresh() end)
        text(743,645,277,44,state~="" and state or "仅本机可见",15,muted,true)
        button(1036,641,212,48,"保存并穿戴",ready and "green" or "sage",save)
    end
    loop=commonlib.Timer:new({callbackFunc=function()
        local _,_,w,h=root:GetAbsPosition()
        local s=math.min(w/1280,h/720)
        local left,top=math.floor((w-s*1280)/2),math.floor((h-s*720)/2)
        if s>0 and (s~=scale or ox~=left or oy~=top) then scale,ox,oy=s,left,top;refresh() end
        if modelActor and not framed and modelActor:GetPrimaryAsset():IsLoaded() then
            local b=modelActor:GetPrimaryAsset():GetBoundingBox({})
            local x,y,z=b.max_x-b.min_x,b.max_y-b.min_y,b.max_z-b.min_z
            scene:CameraSetLookAtPos((b.min_x+b.max_x)/2,(b.min_y+b.max_y)/2,(b.min_z+b.max_z)/2)
            distance=math.max(.2,3.1*math.sqrt(x*x+y*y+z*z))
            framed=true
        end
        scene:CameraSetEyePosByAngle(angle,.055,distance)
        scene:Draw(.033)
    end})
    loop:Change(1,33)
    if standalone then
        actor:SetVisible(false)
        state="正在载入模型…"
        M.Assets.prepare(standalone,function(ok,err)
            if closed or not standalone then return end
            if ok then
                modelActor=W.Create("wardrobe-import",standalone)
                scene:AddChild(modelActor)
            end
            state=ok and "独立模型预览" or "模型载入失败"
            refresh()
        end)
    else dress() end
end

function M.Open(requested,onClose)
    local gate=MyCompany.Aries.EngineFeatureGate
    local feature=Local.feature()
    if gate.glbReady and gate.AtLeast(ParaEngine.GetVersion(),feature.minimum) then open(requested,onClose);return end
    if ParaUI.GetUIObject("wardrobe-room"):IsValid() then return end
    -- Older shop launchers check for this handle synchronously after Open returns.
    -- The actual fitting room and its assets are created only after the check.
    local pending=ParaUI.CreateUIObject("container","wardrobe-room","_lt",0,0,1,1)
    pending.background=""
    pending:AttachToRoot()
    local function release()
        if pending:IsValid() then ParaUI.Destroy(pending.id) end
        M.Close=nil
    end
    M.Close=function() gate.Close();release() end
    gate.Run(feature,function()
        release()
        open(requested,onClose)
    end,function() return pending:IsValid() end,false,function(reason)
        gate.Show(feature,reason,function() release();if onClose then onClose() end end)
    end)
end
