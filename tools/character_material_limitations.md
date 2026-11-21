# 角色材质证据与待补分支

当前 Steam Demo 的 `sharedassets1.assets` 中，3053（`lilToon`）和 3046（`Hidden/lilToonCutout`）通过 UsePass 指向 3043（`Hidden/ltspass_opaque`）和 3050（`Hidden/ltspass_cutout`）。两个实现都提取出 54 段 D3D11 DXBC。序列化 `_lilToonVersion=45` 与上游 2.1.1 一致，该字段无法确定原构建的确切源码修订。

`import_character_materials.py` 跟踪 `Characters/rigs.json` 中启用的渲染器和表面绑定。当前覆盖 81 个不透明和 3 个裁剪材质，包括原始 `_MainTex`、`_Color`、背面剔除、主与次级阴影分带和 38 个已启用的第一层发光材质。三个裁剪材质使用原版序列化的 0.5 阈值。

44 个启用 `_UseReflection` 的材质均使用卡通直接高光，全部设置了 `_ApplySpecular=1`、`_SpecularToon=1` 和 `_ApplyReflection=0`。17 个有 `_ApplyReflection=1` 的材质均未启用外层 `_UseReflection`。高光沿用原版半角幂函数及色值和贴图，包括 39 个 ReflectionColorTex、7 个 SmoothnessTex 和 38 个启用额外光源高光的材质。

10 个 `_ShadowEnvStrength` 非零的材质从 level3 RenderSettings 9527 取得原 27 项环境 SH 系数。level10–21 的系数与它一致。Godot 用原版逆光方向 SH 采样及暗色插值还原其环境混色。GPU 测试通过实际共享着色器验证裁剪、背面剔除、方向光分带、暗部环境混色和直接高光。

轮廓来自 `globalgamemanagers.assets:6684` 的 `HeroRender` 渲染通道。它以 `Outline_Mat:3` 重绘角色层 10 和层 3 内的几何队列对象。对 `Outline_SG:58` 的前向 DXBC 进行反汇编，可以看到沿法线外扩的长度为 0.0004 乘镜头到网格原点的距离，并除以模型每轴的缩放。Godot 的 `character_outline.gdshader` 在蒙皮后的网格使用这套外扩，复用场景深度，关闭深度写入。描边排在常规透明物后面。Godot 通过不透明颜色和深度恢复第 10 层的可见表面，对应 `HeroRender02:6647`，之后绘制第 12 层前景。这个实现需要复制一次不透明画面，Compatibility 回读的色彩精度略低。原版战斗期间改层的特殊效果与角色倒地后的布娃娃过渡待逐帧复核。

`Hidden/ltspass_cutout` 用贴图 alpha 乘以材质色 alpha，并按屏幕导数过滤裁剪阈值。阵亡过渡的 `_Color.a` 目标值是零。Godot 在保留黑色几何描边的同时，让这些裁剪表面按原材质的 alpha 退出。

待补分支

- 原版 Screen 发光对已合成的总颜色运算。现有 Godot 端对直接光应用 Screen 系数，环境光合成顺序仍有差异。
- 角色弓的 `sharedassets1_619`（`GAP_SG/FresnelShader`）和 `sharedassets1_620`（`Shader Graphs/VFXTrail_SG`）使用其他独立着色程序，沿用原有 Godot 材质。
- Unity 的颜色空间转换、纹理采样器状态、URP 主光源与环境 SH 的总体合成、额外光源和投影阴影仍需逐项核对。当前没有对这些效果做像素级同一性声明。
