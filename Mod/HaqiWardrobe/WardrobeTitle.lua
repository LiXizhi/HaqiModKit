-- Shared by the kids shop and the independently packaged boutique.
local Title=commonlib.gettable("MyCompany.Aries.HaqiShop.WardrobeTitle")
Title.letters={"彩","虹","衣","柜"}
Title.defaults={"B73D59","A05A10","137064","654499"}
function Title.rgb(value)
    return string.format("%d %d %d",tonumber(value:sub(1,2),16),tonumber(value:sub(3,4),16),tonumber(value:sub(5,6),16))
end

function Title.read()
    return commonlib.clone(Title.defaults)
end
