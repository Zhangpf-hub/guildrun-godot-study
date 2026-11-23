# 角色材质证据与待补分支

当前 Steam Demo 的 `sharedassets1.assets` 中，3053（`lilToon`）和 3046（`Hidden/lilToonCutout`）通过 UsePass 指向 3043（`Hidden/ltspass_opaque`）和 3050（`Hidden/ltspass_cutout`）。两个实现都提取出 54 段 D3D11 DXBC。序列化 `_lilToonVersion=45` 与上游 2.1.1 一致，该字段无法确定原构建的确切源码修订。

`import_character_materials.py` 跟踪 `Characters/rigs.json` 中启用的渲染器和表面绑定。当前覆盖 81 个不透明和 3 个裁剪材质，包括原始 `_MainTex`、`_Color`、背面剔除、主与次级阴影分带和 38 个已启用的第一层发光材质。三个裁剪材质使用原版序列化的 0.5 阈值。

44 个启用 `_UseReflection` 的材质均使用卡通直接高光，全部设置了 `_ApplySpecular=1`、`_SpecularToon=1` 和 `_ApplyReflection=0`。17 个有 `_ApplyReflection=1` 的材质均未启用外层 `_UseReflection`。高光沿用原版半角幂函数及色值和贴图，包括 39 个 ReflectionColorTex、7 个 SmoothnessTex 和 38 个启用额外光源高光的材质。

10 个 `_ShadowEnvStrength` 非零的材质从 level3 RenderSettings 9527 取得原 27 项环境 SH 系数。level10–21 的系数与它一致。Godot 用原版逆光方向 SH 采样及暗色插值还原其环境混色。GPU 测试通过实际共享着色器验证裁剪、背面剔除、方向光分带、暗部环境混色和直接高光。

轮廓来自 `globalgamemanagers.assets:6684` 的 `HeroRender` 渲染通道。它以 `Outline_Mat:3` 重绘角色层 10 和层 3 内的几何队列对象。对 `Outline_SG:58` 的前向 DXBC 进行反汇编，可以看到沿法线外扩的长度为 0.0004 乘镜头到网格原点的距离，并除以模型每轴的缩放。Godot 的 `character_outline.gdshader` 在蒙皮后的网格使用这套外扩，复用场景深度，关闭深度写入。描边排在常规透明物后面。Godot 通过不透明颜色和深度恢复第 10 层的可见表面，对应 `HeroRender02:6647`，之后绘制第 12 层前景。这个实现需要复制一次不透明画面，Compatibility 回读的色彩精度略低。

`VFXRender:6689` 在角色表面恢复后、前景之前，从主镜头重绘第 8 层透明发射器。悠娜的出手、命中冲击、落地烟尘、普攻红斩和复活粒子已接通。对照见 `build/windows/port-layer8-vfx-redraw-comparison.png`。

`onHitVFX Render:6683` 在前景之后重绘第 14 层命中特效。悠娜的十个该层发射器已接通这个通道，使用 17° 竖直视野和原版的视图 Z 偏移，因此残烟和白芯能再次覆盖角色表面与描边。对照见 `build/windows/port-yuna-hit-redraw-comparison.png`。

42 份 `CharacterVisualConfig` 里有 25 份含 `RagdollAnimator2`，其 `RagdollDummyLayer` 均为 13。`CharacterViewController.HandleRagdollDeath`（RVA `0x39c100`）施加冲量、进入倒地状态并解除配置的挂件。`ResetRagdoll`（RVA `0x39ccc0`）恢复位置、旋转、混合权重和挂件。扫描 `ember.*`、`AD_Fimp*` 与 `Assembly-CSharp*` 中带 RVA 的直接调用，Unity 的 `GameObject.set_layer` 命中布娃娃插件。在挂件创建流程中，`AttachableGeneratePhysicsOn`（RVA `0x67fe0`）给新建代理赋层。原版的 `PhysicsManager.m_LayerCollisionMatrix` 排除了第 13 层与第 10 层和自身的碰撞。

`tools/import_character_ragdolls.py` 导出 464 根物理骨骼的胶囊和球形碰撞体、质量和关节限位。Godot 正常战斗的致死伤害触发布娃娃，碰撞面沿用关卡 `ShadowPlane` 网格。FBX 省略的 Selkhera 尾骨 `tail_069` 按 Unity 变换 `sharedassets1.assets:47061` 补回。可见网格保留原材质、投影和描边，复活时移除布娃娃并恢复动画。武器挂件的脱离、原版逐帧姿态和不同求解器的轨迹仍待复核。10101 的 Godot 实机画面见 `build/windows/port-logan-ragdoll-revival.png`。 [Godot 物理骨骼](https://docs.godotengine.org/en/stable/classes/class_physicalbone3d.html)

`Hidden/ltspass_cutout` 用贴图 alpha 乘以材质色 alpha，并按屏幕导数过滤裁剪阈值。阵亡过渡的 `_Color.a` 目标值是零。Godot 在保留黑色几何描边的同时，让这些裁剪表面按原材质的 alpha 退出。

`lil_common_frag.hlsl` 在受光之后调用 `lilBlendColor`。对每通道处于 0 到 1 的受光颜色 `B`，Screen 的结果为 `E + B * (1 - E)`，其中 `E` 是发光颜色乘以混合强度。浩英、尼克拉斯和蕾娜所用的四份材质选了此模式。Godot 在线性空间中将环境光、直射漫反射和直接高光都乘以 `1 - E`，再叠加发光。Compatibility 的材质输出需按该渲染器的 sRGB 接口编码。`check_character_materials.gd -- --gpu` 会在仅有环境光和另有方向光及高光的条件下检查最终像素。10101 关同镜头对照见 `build/windows/port-hoyoung-screen-emission.png`。 [Godot Compatibility 场景着色器](https://github.com/godotengine/godot/blob/master/drivers/gles3/shaders/scene.glsl)

待补分支

- 原版对合成后高于 1 的 HDR 分量设有保底，Godot 的材质通道仍使用线性 Screen 系数近似这些分量。
- Javryn 的技能弓使用 `sharedassets1_619` 的 Fresnel 加法发光和 `sharedassets1_620` 的透明拖尾，按原版透明通道的 DXBC 移植。弓在技能 63192 的 0.734 秒起播点播放 `BowCurve`。两个渲染后端已验证待机、起播和中断，原版同阶段的雾与 HDR 掩模还需要画面对照。
- Unity 的颜色空间转换、纹理采样器状态、URP 主光源与环境 SH 的总体合成、额外光源和投影阴影仍需逐项核对。当前没有对这些效果做像素级同一性声明。
