-- A fixed editorial spread scales uniformly inside the client window.
local Art=commonlib.gettable("Mod.HaqiWardrobe.ShopArt")
function Art.read()
    local f=ParaIO.open("Mod/HaqiWardrobe/shop.json","r")
    assert(f:IsValid(),"Missing boutique art manifest")
    local value=commonlib.Json.Decode(f:GetText(0,-1))
    f:close()
    return value
end

function Art.image(node,base,id,slice)
    node.background=""
    Mod.HaqiWardrobe.Assets.fetch(base,id,function(path)
        if node:IsValid() and path then node.background=path..(slice and ":15 15 15 15" or "") end
    end)
end
