# 哈奇 Mod 开发指南

把这个链接和你的一句话想法发给自己的 AI 即可开始。Codex 等能读写文件的助手可以制作 ZIP、连接桌面客户端并检查游戏截图。使用 DeepSeek 等聊天工具时，也可以直接复制衣柜方案进游戏。

> 请读 https://github.com/LiXizhi/HaqiModKit ，帮我做一个哈奇 Mod。我想要____。先做一个能运行的小版本，放进我的本机客户端试用，给我看游戏里的效果。

## 先试试自己的角色

打开 **商城 → 炫彩 → 彩虹衣柜 → 角色 DIY**，点 **复制设计说明**。把它和想法或参考图片一起发给自己的模型。复制模型返回的 JSON，回游戏点 **从剪贴板试穿**。可以旋转看背面，也可以去「单品」继续换鞋或配饰。满意后点 **保存并穿戴**，在本机生效。

一个可以直接试穿的方案：

```json
{"version":1,"name":"月光鲸","base":"deepseek-whale-maid","parts":{"head":"moon-moth","effect":"moon-moth","trim":false}}
```

`base` 选择整套。可覆盖的部位是 `top/lower/shoes/head/back/trim/effect`。服饰 ID、各套可用部件和 UV 模板以游戏复制的说明为准。`false` 可卸下配饰。使用原角色的脸、表情和骨骼。新剪影可以通过单独制作的 GLB 配件扩展，衣柜 JSON 用已有的几何部件。

## 给能操作电脑的 AI

在电脑上使用带 **系统设置 → Mod → 管理 Mod** 的哈奇客户端。点击 **连接本机 AI**，记下显示的端口。这个连接在当前客户端进程内有效。获取工具包：

```sh
git clone https://github.com/LiXizhi/HaqiModKit
cd HaqiModKit
```

### 制作独立 Mod

需要 Python 3.9 或更新版本。以下命令创建一个会在画面上显示问候语的示例：

```sh
python3 kit.py new HaqiMoon ./my-project
python3 kit.py pack ./my-project --out ./dist
```

1. 修改 `my-project/Mod/HaqiMoon/main.lua` 中的文字或行为。入口继承 `Mod.ModBase`，类名为 `Mod.HaqiMoon`。使用 Lua 5.1 和 `NPL.load`。
2. 将 `dist/HaqiMoon.zip` 复制到用户指定的哈奇客户端 `Mod/`。外层 ZIP 名和里面 `Mod/<名字>/main.lua` 的名字一致，以 `Haqi` 开头。打包工具拒绝覆盖旧包，可输出到新的目录。
3. 在 **管理 Mod → 刷新列表** 找到新包，点 **启用**。进入世界会调用 `OnWorldLoad`，停用或离开会调用 `OnLeaveWorld`。在离开回调中清理 UI、计时器及场景对象。启用状态保存在该客户端。更新同名 ZIP 后重新启动客户端以载入新脚本。
4. 第一次制作时，验证启用后能看见效果、停用后效果消失、重新进入世界能恢复。社区 ZIP 在用户主动启用后执行本机 NPL 脚本。只安装信任的作者或自己审阅过的代码。

### 用 paracraft-cli 验证

下面脚本适用于桌面 Python。把 `port` 改为游戏设置里显示的端口。先读 `health` 核对客户端，然后按需调用其他操作。截图保存的是游戏原生界面。

```python
import base64, json, urllib.request
from pathlib import Path

port = 8099
def call(action, **params):
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/ajax/paracraft_cli",
        data=json.dumps({"action": action, "params": params}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=20) as reply:
        data = json.load(reply)
    if not data.get("ok"):
        raise RuntimeError(data.get("error"))
    return data["result"]

print(call("health"))
print(call("run_npl_code", code="return MyCompany.Aries.HaqiMods.List()"))
print(call("tail_log", lines=10))
image = call("screenshot", maxSide=1024)
Path("haqi-preview.jpg").write_bytes(base64.b64decode(image["base64"]))
```

衣柜已打开时，把模型方案存成 UTF-8 文件，用以下命令送进试衣间。返回“已收到方案”后，轮询 `run_npl_code`，代码为 `return MyCompany.Aries.HaqiWardrobeDIY.Status()`，直到 `ready=true` 再截图。`message` 显示加载失败时应修正方案并重试。

```sh
python3 Mod/HaqiWardrobe/tools/diy.py preview my-look.json --port 8099
```

### 发布一张自己的服装贴图

用复制的设计说明里对应套装的 PNG 做 UV 模板。保留透明区域，绘制衣料、纹样或饰边。输出 **512×512、8 位 RGBA PNG，最大 204800 字节**。先本地校验并打印将要发布的地址（把 alice 改为自己的用户名）：

```sh
python3 -m pip install pillow requests
python3 Mod/HaqiWardrobe/tools/diy.py publish atlas.png --account alice
```

实际上传使用 Keepwork 的个人 CDN 接口。运行下方命令时，用户在自己的终端输入密码（隐藏输入），或在本机设置已有的 `KEEPWORK_TOKEN`。凭据只发给 Keepwork。确认要公开这张图片后，传入上一步打印的完整地址：

```sh
python3 Mod/HaqiWardrobe/tools/diy.py publish atlas.png --account alice --confirm-url "<完整地址>"
```

上传成功后，把地址写进方案的可选 `texture` 字段。上装、下装和鞋履会采用这张贴图；再切换某件单品只替换该部位。游戏按文件摘要校验并缓存。这个地址只公开贴图，玩家保存的造型仍在自己的设备上。

## 官方 Mod 与源码

**彩虹衣柜** 默认启用，可在设置里停用。商城按需检查官方 CDN 更新。社区 ZIP 由用户自行安装。公开仓库包含可修改的衣柜脚本、可安装的包、Mod 管理器、开发模板和工具。MIT 许可适用于本工具包的代码；角色原模型、游戏内容和美术素材的权利由各自权利人保留。 [官方 Mod 源码](https://github.com/LiXizhi/HaqiModKit/tree/main/Mod/HaqiWardrobe) · [下载衣柜 ZIP](https://github.com/LiXizhi/HaqiModKit/raw/refs/heads/main/dist/HaqiWardrobe.zip) · [美术与提示词归档](https://github.com/LiXizhi/HaqiWardrobe)
