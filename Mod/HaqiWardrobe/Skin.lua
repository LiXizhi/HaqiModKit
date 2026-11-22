-- Compose a garment over this Elf's stock skin. Only replaceable slot 1 receives the result.
NPL.load("(gl)script/ide/System/Encoding/crc32.lua")
local S = commonlib.gettable("Mod.HaqiWardrobe.Skin")
local A = Mod.HaqiWardrobe.Assets
local function pixels(path)
    local f=ParaIO.open(path,"image")
    assert(f:IsValid(),"Cannot decode "..path)
    f:ReadInt()
    local w,h,bpp=f:ReadInt(),f:ReadInt(),f:ReadInt()
    local data=f:GetText(16,w*h*bpp)
    f:close()
    assert(w>0 and h>0 and (bpp==3 or bpp==4) and #data==w*h*bpp,"Invalid image "..path)
    return data,w,h,bpp
end
local function be(n)
    return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256)
end
local function chunk(tag,data)
    return be(#data)..tag..data..be(System.Encoding.crc32(tag..data))
end
local function composite(path,skin,regions,mask)
    local bg,bw,bh,bc=pixels(skin)
    local maps,cache={},{}
    local w,h=512,512
    for group,id in pairs(regions) do
        if not cache[id] then
            local rgba,tw,th,fc=pixels(A.path(id))
            assert(tw==w and th==h and fc==4,"Expected a 512px RGBA outfit atlas")
            cache[id]=rgba
        end
        maps[group]=cache[id]
    end
    local mul={mask%256,math.floor(mask/256)%256,math.floor(mask/65536)%256}
    local rows={}
    for y=0,h-1 do
        local row={}
        for x=0,w-1 do
            local i=(y*w+x)*4+1
            local fg=maps.top
            if y>=256 then
                if x>=256 then fg=maps.lower elseif y>=384 then fg=maps.shoes end
            end
            local b,g,r,a=fg:byte(i,i+3)
            if a<255 then
                local j=(math.floor(y*bh/h)*bw+math.floor(x*bw/w))*bc+1
                local bb,bg1,br=bg:byte(j,j+2)
                local inv=(255-a)/255
                b=math.floor(b*a/255+bb*mul[1]/255*inv+.5)
                g=math.floor(g*a/255+bg1*mul[2]/255*inv+.5)
                r=math.floor(r*a/255+br*mul[3]/255*inv+.5)
            end
            row[x+1]=string.char(r,g,b)
        end
        rows[#rows+1]="\0"..table.concat(row)
    end
    local z={method="zlib",content=table.concat(rows)}
    assert(NPL.Compress(z),"Failed to compress skin")
    local png="\137PNG\r\n\26\n"..chunk("IHDR",be(w)..be(h)..string.char(8,2,0,0,0))..chunk("IDAT",z.result)..chunk("IEND","")
    local file=ParaIO.open(path,"w")
    assert(file:IsValid(),"Cannot write composed outfit")
    file:write(png,#png)
    file:close()
end

function S.forActor(actor,look)
    local ch=actor:ToCharacter()
    local model=actor:GetPrimaryAsset():GetKeyName():lower()
    local gender=model:match("/elf/(female)/") or model:match("/elf/(male)/")
    assert(gender,"Select a Haqi kids Elf to wear this outfit")
    gender=gender=="female" and "Female" or "Male"
    local skin=string.format("character/v3/Elf/%s/Elf%sSkin00_%02d.dds",gender,gender,ch:GetBodyParams(0))
    local color=ch:GetSkinColorMask()
    local mask=color=="F" and 16777215 or assert(tonumber(color,16))
    local folder="temp/haqi-wardrobe/skins/"
    local regions=look.regions or {top=look.atlas,lower=look.atlas,shoes=look.atlas}
    local path=folder..ParaMisc.sha1("v2/"..skin..color..regions.top..regions.lower..regions.shoes)..".png"
    if not ParaIO.DoesFileExist(path,false) then
        ParaIO.CreateDirectory(folder)
        composite(path,skin,regions,mask)
    end
    return ParaAsset.LoadTexture("",path,1)
end
