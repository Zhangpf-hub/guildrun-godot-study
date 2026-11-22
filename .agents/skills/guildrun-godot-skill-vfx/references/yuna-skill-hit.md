# 悠娜暗影手里剑实装

## 找到命中事件

基准为 Steam Windows Demo 构建 26551710。角色资产在 `sharedassets1.assets:11625`，`VfxHandlerComponent:63172` 的技能事件 150 会播放以下组件。时间为相对于技能动画开始的秒数，每个发射器还可以有独立的启动延时。

| 时间 | 组件 PathID | 特效 |
| --- | --- | --- |
| 1.000 | 63281 | SkillAttack_01 |
| 1.620 | 61017 | SkillAttack_02 |
| 2.334 | 62365 | SkillAttack_03 |
| 2.370 | 61696 | SkillAttack_04 |
| 2.650 | 62694 | SkillHit |
| 3.620 | 63162 | SkillAttack_05 |

`SkillHit` 对应 prefab 16788，根下 `root` 抬高 0.5。首战回放使用战斗种子 500813409，伤害在第 374 步结算，第 401 步落格，第 409 步胜利。Godot 在 1 倍速的动作时间 2.65 秒固定特效的世界坐标并发射第一批残烟，第 381 步已能看到 5 颗。白芯与短芒按同种子亮峰校准到 2.85 秒，约第 386 步起播。

## 装配六组动作事件

- [导入器](../../../../tools/import_battle_revival.py) 的 `--yuna-skill` 模式生成 [蓄力场景](../../../../game/battle/yuna_skill_charge.tscn) 和 [命中场景](../../../../game/battle/yuna_skill_hit.tscn)。蓄力段接入九个发射器。红弧 `Charge_01:54326` 使用网格 `2735`、材质 `350`，在动画起点后 1.72、1.82、1.87 秒按 3、3、2 个发射，跟随 `hand_R`。闪光和圆环从右手取世界发射位置，持续光晕与线芒保留各自的频率和模拟空间。命中段装入十一个发射器，保留原版贴图、尺寸、寿命、透明度和 `Slash_01` 额外的 0.02 秒延时。

- 蓄力光晕 `Flare_02:53965` 在 1.62 秒时从右手发射一次，寿命为 1.2 秒，出生后固定在世界空间。材质 `331` 对应 `resources.assets:712` 的透明前向片元程序 20。按常量缓冲区的绑定还原径向噪声、扭曲遮罩、渐变取色和 0.2 单位深度淡出。原版 `Custom1` 的 X 为 0 至 120 的采样偏移，Y 为 −0.4 的扭曲系数，Z 为 0，W 为 3.99 的发光系数。在材质 `331` 的输入区间内，Z 为 0 时溶解阈值恒为 0。Unity `BakeMesh` 确认 Hierarchy 模式在出生时把角色的 1.14 缩放乘进宽度，标称宽 10 对应世界宽 11.4。Godot 导入器将这个继承值写入粒子尺寸。扭曲和噪声卷动使用战斗表现时钟，原版着色器读取场景时间。

- 原版蓄力组件的 `_duration` 为 1 秒，`_disableOnRelease` 为 0。组件释放后，已出生的光晕继续走完 1.2 秒寿命。Godot 按最后一颗粒子的结束时刻回收蓄力场景。回归检查在动作 2.65 秒确认光晕仍在，在 2.83 秒确认光晕进入回收，在 2.93 秒确认剩余粒子也已结束。原版光晕和 Godot 同帧开关对照见 `build/windows/port-yuna-charge-flare-comparison.png`。
- 命中的 `Circle_01:51953` 发射一层圆环，`Spike_01:52598` 在球形发射区生成三个侧向芒刺。`Line_01:53506` 在命中发射时刻后 0.05 秒起播，间隔 0.05 秒共三批，每批 2 至 5 条，带宽和持续时间按 Trail 模块抽样。Unity 烘焙确认面向镜头的广告牌正向滚转在屏幕上为顺时针，轴心偏移随滚转一起旋转。

- 白芯 `CoreWhite_01:52380` 与短芒 `Spikes_01:54056` 均使用固定随机种子 3964，非循环且每次发射一片。按启用的模块重建 Unity 发射器并重播三次，测得滚转分别为 204.8808° 与 356.9663°。两层按 Hierarchy 缩放，起始宽 8 乘角色的 1.14 后实测为 9.12。Godot 在导入时写入两层各自的固定滚转和继承缩放。阶段对齐的截帧中，白芯长轴的屏幕角从约 −53° 修正到 27°，原版约 23°。见 `build/windows/port-yuna-impact-roll-comparison.png`。

- 命中残烟 `Smoke_01:54276` 有两批，每批 5 颗，间隔 0.05 秒。以原版 0.5 半径与 25° 半角重建 Unity 发射器，用 `GetParticles` 测 4,096 个出生点与初速度。令 `r` 为出生点到轴线的距离除以发射半径，实测偏转角符合 `atan(r * tan(25°))`，最大误差约 0.0002°。零半径时先在单位圆盘抽样，再把位置压到轴线上，可保留发射方向的分布。锥形体积发射沿同一射线取出生点，长度设为 5 的小样中，出生点离底面起点的最大距离为 4.9996。`BakeMesh` 还确认 6 × 6 图集首帧位于左上。用隐藏残烟的回放可检查分布与浓度，见 `build/windows/port-yuna-impact-smoke-comparison.png`。
- 发射器使用固定随机种子 3964。按原版输入范围的顺序重建两批发射，在 Unity 重跑两次得到完全相同的十组出生位置、初速度、尺寸、滚转和寿命。Hierarchy 缩放将挂点高度从 0.50 变为 0.57，粒子的起始几何和位移也乘以 1.14。导入器把十组出生样本换算为 Godot 坐标，运行时继续使用原版的减速曲线、寿命尺寸曲线和 6 × 6 图集。按速度调色的阈值为 4 到 12，烟粒子速度低于 4，烘焙后的颜色仍为 RGBA 84、78、89、40。 [Unity 烘焙脚本](../scripts/ImpactSmokeBirthProbe.cs)
- 第 409 步在 Forward+ 的同帧开关对照中，残烟使 8 位亮度下降超过 5 的像素从 1,618 个增至 1,747 个，受影响区域的最左与最右像素跨度从 49 像素增至 54 像素。Compatibility 的回放也验证了两批残烟。原版烟团中心仍更暗，左侧扩散更宽。见 `build/windows/port-yuna-smoke-birth-comparison.png`。
- 用 D3D11 执行原版材质 354 的片元程序，白色默认遮罩和零平滑度在 `Custom2.x=0` 时输出 Alpha 0，寿命进度大于 0 时恢复图集 Alpha 与粒子色、软深度的乘积。早期 Unity 小样误把曲线倍率设为 0。按资产中的 1.0 重跑，粒子系统时间 0.10 秒时读到 `Custom2.x=0.038147`，烘焙网格的 `TEXCOORD1.z` 读回相同数值。Godot 现在直接导入这条曲线并接入材质。
- 同帧分别用 2.85 秒与 2.65 秒发射残烟。第 398 步训练龟左侧固定区域对原版的 8 位亮度平均绝对误差由 29.15 降至 25.61，第 409 步则由 27.00 升至 27.93。第 381 步和 398 步的烟团发射更接近原版，后段浓度仍偏低。测试保留了 0.5 单位软深度淡出。见 `build/windows/port-yuna-smoke-dissolve-timing.png`。
- 从 `PC_Renderer:6668` 读到 `onHitVFX Render:6683`。它在前景之后，使用 17° 竖直视野和视图空间 Z 平移 +3 重绘第 14 层。原版主镜头的普通透明通道也包含这一层。导入器按 GameObject 的层写入标记，Godot 为十个命中发射器追加第二遍材质，复用同一颗粒子的所有寿命数据。第 8 层 `Impact_01` 属于另一个 `VFXRender` 通道。 [Unity Render Objects 前向实现](https://github.com/Unity-Technologies/Graphics/blob/6000.0/staging/Packages/com.unity.render-pipelines.universal/Runtime/Passes/RenderObjectsPass.cs#L143-L184)
- `VFXRender:6689` 在事件 500、角色表面恢复之后，用主镜头重绘第 8 层透明队列。主镜头也在普通透明通道绘制这些发射器。核对原版材质的有效队列后，导入器标记了 28 个发射器，覆盖出手 10 个、命中冲击 1 个、落地 1 个、普攻 3 个和复活 13 个。Godot 的描边与表面使用优先级 8 与 9，第 8 层重绘以 16 为基准并加上发射器的原排序值，前景使用 24，第 14 层重绘以 32 为基准。出手的 `Aura_01` 与 `Glow_01` 需要为第二遍重新上传粒子色，单独复制材质会读到默认白色。 [Unity URP 渲染通道](https://docs.unity.com/en-us/engine/6000.0/manual/render-pipelines/universal-render-pipeline/customizing-urp/urp-renderer-feature/renderer-feature-render-objects)
- 第 376 步只开关第 8 层重绘，局部画面任一 8 位 RGB 通道改变超过 4 级的像素有 1,547 个（Forward+）和 3,660 个（Compatibility）。第 411 采样帧的普攻红斩与角色重叠处也有变化。与原版对应帧比较，两处采样区的平均亮度误差变化均小于 0.1 级。出手末端仍偏橙，普攻姿势和红斩轮廓仍有差异。见 `build/windows/port-layer8-vfx-redraw-comparison.png`。
- 同帧开关这次重绘时，第 409 步的 Forward+ 地面采样区亮度误差从 28.25 降至 7.30。Compatibility 的近黑残烟和黑光晕用 `1 - (1 - alpha)^(1/2.2)` 近似线性光的透射，减少两遍 sRGB 混合导致的压黑，同一区域误差从 35.04 降至 7.33。亮部的泛光、峰值范围和动作姿势仍有差异。见 `build/windows/port-yuna-hit-redraw-comparison.png`。
- 红弧用球面朝向旋转原版网格，出生尺寸和颜色按各批次在发射器中的进度计算。溶解从粒子寿命曲线读取 `Custom2` 的阈值与卷动。Unity 和 Godot 各自生成随机粒子朝向，逐帧轮廓仍有差异。 [Unity 粒子初始朝向](https://docs.unity3d.com/cn/6000.0/ScriptReference/ParticleSystem.ShapeModule.html)
- `VFX_SG`（`resources.assets:711`）用粒子色与强度控制输出，选取红通道或 RGBA。这个透明变体没有读取材料的 `_Color`，照抄该值会把尖刺额外放亮。烟雾使用白色默认溶解遮罩并读入寿命曲线。白芯的白色默认遮罩仍按截帧近似。
- `UberParticles`（`sharedassets1.assets:3022`）的普通透明变体读取 RGBA 图集，亮度系数为 `1 + _AddIntensity + Custom1X`，`Line_02` 的附加强度为 0.46。用 `UVModule` 驱动 3 × 3 图集。烟雾使用 6 × 6 图集。Unity 的负 `sortingFudge` 对应 Godot 的正 `sorting_offset`。分别核对排序与深度测试。 [Unity 粒子排序](https://docs.unity3d.com/cn/2023.1/Manual/PartSysRendererModule.html) [Godot 视觉实例排序](https://docs.godotengine.org/en/stable/classes/class_visualinstance3d.html#class-visualinstance3d-property-sorting-offset)
- [角色入口](../../../../game/battle/board_unit.gd) 在 `shadow_strike` 进入 `SkillAttack` 时实例化场景，并同步表现时钟。原版截帧中，命中残烟留在训练龟附近。Godot 先固定挂点，再发射粒子。实机试验显示，若把挂点取样一并延后，白芯会跟随角色绕到训练龟背后。
- [出手场景](../../../../game/battle/yuna_skill_release.tscn) 由 `SkillAttack_03:62365` 导出。保留 `VFXParent` 下的本地高度与旋转，接入光晕、爆发芒刺、移动圆环和冲击网格。`Aura_01` 使用材质 `328` 的主纹理 Alpha、流动噪声和场景深度生成加色红光。`Rings_01` 的发射器翻转了 180°，本地负 Y 速度沿发射器的旋转轴变换到世界空间。
- 出手的 `Aura_01:53773`、`Glow_01:53216`、`ParticlesAB:51186` 都关闭 `m_ApplyActiveColorSpace`。导入器把这项设置写进粒子数据，运行时按分量传入 `Vector4`。使用 `Color` 会让 Godot Forward+ 在上传时转换为线性颜色。对 `Aura_01` 的同帧对照中，第 376 步有 587 个局部像素的 8 位亮度变化超过 4，单像素红通道最多增加 105 级。对照见 `build/windows/port-yuna-release-aura-color-comparison.png`。 [Unity 粒子颜色上传](https://docs.unity3d.com/cn/2022.3/Manual/PartSysRendererModule.html) [Godot 着色器参数上传](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/storage_rd/material_storage.cpp)
- 同一出手预制体里的 `ParticlesAB:51186` 在 2.334 秒发射 6 至 8 颗暗红粒子。出生后留在世界空间，保留 0.1 至 0.4 的尺寸区间、1.2 至 2 秒寿命和 25° 锥形发射。材质 `339` 的 `GAP_SG/AB_Unlit:3031` 透明前向分支以贴图 `Beam01_03:2215` 的 RGBA 与粒子色相乘。透明前向 DXBC 程序 7 用 `_SoftParticle` 乘视空间深度差，材质值 1.0 对应 1 个世界单位的软淡出。贴图启用 mipmaps。该 Renderer 关闭 `m_ApplyActiveColorSpace`，粒子顶点色直接参与计算。透明排序读原版的 `m_SortingOrder`，粒子与暗光晕为 −2，主红光为 2。Unity 小样显示噪声逐步累积位移，Godot 使用同频率、滚动速度和强度范围的 Perlin 噪声，逐粒子轨迹存在差异。
- [飞行场景](../../../../game/battle/yuna_skill_flight.tscn) 由 `SkillAttack_04:61696` 导出，绑定在原版动画的 `Shuriken/VFX_Slot` 上。`Line_01:55253` 每批从当前挂点发射，世界坐标中的尾丝顶点按寿命保留。粒子本体尺寸为零，带宽来自 Trail 模块，因此用独立的带状网格渲染。手里剑挂点的静止缩放为 0.01，`Ayaka_ActiveAbility_All:3179` 的缩放轨在 1.70 至 2.7667 秒把 `Shuriken` 的三轴保持在 1。用发射帧的挂点变换核对尾丝宽度。 [Unity 拖尾坐标和寿命](https://docs.unity3d.com/kr/560/ScriptReference/ParticleSystem.TrailModule.html)
- 飞行的 `Wave_01:54005` 使用网格 `2731`，关闭自动播放，开启预热。Unity 6000.6.7f1 用固定种子 6457 重播两次，`Play()` 后立即读到年龄约 0.60、0.40、0.20 秒的三片预热波纹。0.01 秒首次烘焙有五片，0.20 秒后最早的波纹到期并在新的挂点位置补发一片。用 `GetCustomParticleData` 核对六片的 `Custom1.x`，按出生时刻和初始年龄写入导入器。Godot 到 2.37 秒才让预热片进入世界空间，随后独立采样寿命曲线。静止挂点的 `BakeMesh` 宽约 0.0409，出手时按原动画的挂点缩放换算约为 4.09。材质 `361` 的 `_RAMPENABLED_ON` 前向程序从 `Custom2.x` 取发光乘数，该值为 0。使用 `resources.assets:567` 的反相溶解噪声，按 0.2 的幅度扭曲，`Custom1.yz` 推进两侧溶解。主贴图沿 V 使用幂曲线与 `Custom2.y` 提供的时间相位。实机截图与隔离波纹可见 `build/windows/port-yuna-wave-prewarm-comparison.png`。用 `--without-flight-wave` 可关掉这一层。 [Unity 预热](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/particlesystem/mainmodule/prewarm)
- 拖尾底端的手里剑由 `Shuriken_01:54552` 和 `Shuriken_02:55301` 组成，分别使用材质 `335` 的菲涅尔红边和材质 `329` 的浅色填充。两层各发射一片同样的网格 `2795`，按原版透明顺序绘制。Unity 烘焙确认粒子使用本地尺寸 2，忽略挂点的 0.01 缩放，展开宽约 1.027 世界单位。两层在出生位置沿世界 Z 轴每秒旋转两周，随飞行场景回收。原版发射器写入 2.37 秒。同种子回放中，Godot 在此时发射会把网格留在半空，因此将两层的表现时刻校准到武器抵达地面时的 2.47 秒。
- 核对红边亮度时，要查 ShaderLab 属性类型和原版 PlayerSettings 的色彩空间。材质 `335` 的 `_Color` 是普通 Color，序列化红色值 4 在线性光中按 `4 ^ 2.2` 上传，实测约 21.11213。Unity 小样通过直接写入 `m_SavedProperties.m_Colors` 并读取浮点渲染目标验证，避开 `SetColor` 引入的转换。0 至 1 的通道按 sRGB 曲线转换，Alpha 原样上传。顶点色仍按粒子 Renderer 的颜色开关处理。恢复线性色值的同帧对照见 `build/windows/port-yuna-rim-linear-color.png`。 [Unity 材质颜色属性](https://docs.unity3d.com/cn/current/Manual/SL-PropertiesInPrograms.html)
- 向地面延伸的红黑长尾来自同一预制体下的 `Trail_02`（`TrailRenderer:50124`）。原版 `InternalPlay` 在起手时激活带有 `_disableOnRelease` 的根节点，长尾因此从起手开始记录挂点。组件在 2.37 秒时另行调用 `PlaySystems`。沿挂点每移动至少 0.05 个世界单位记录一个点，保留 0.20 秒。网格面向镜头，带宽按原版曲线乘以 1.4。UV 从武器头部到尾端按路径长度归一化，烘焙结果可验证这一方向。材质 359 的 `Tex_Trail2:1956` 沿 U 重复 0.5 倍，原版透明前向变体读取共享场景时间并以每秒 −2 卷动。Godot 用战斗场景的共享时钟计算相位，暂停时冻结，战斗中按当前倍速推进。尾迹点仍按各自表现时间到期。`capture_yuna_skill.gd` 在回放开战时将共享时钟设为零，按定步推进以便重复取帧。 [Unity Trail Renderer](https://docs.unity3d.com/es/2020.1/Manual/class-TrailRenderer.html)
- 用 Unity 6000.6.7f1 的 `GetPositions` 和 `BakeMesh` 分别检查历史点与渲染顶点。移动 0.02 和 0.04 单位时，历史点仍只有起点，烘焙带状网格已延伸到武器挂点。Godot 也在绘制时补入当前挂点，并按补入后的路径长度计算 UV。首战第 355 步，历史点到挂点的实际距离约 0.0484 单位，投影相差约 1.05 像素。另将 `TrailRenderer:50124` 的 `m_SortingOrder = -1` 写入透明材质的渲染优先级。第 376 步的长拖尾、光晕和暗波纹重叠处可见变化。见 `build/windows/port-yuna-trail-head-order.png`。 [Unity 拖尾采样间距](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/trailrenderer/minvertexdistance) [Godot 材质渲染优先级](https://docs.godotengine.org/en/stable/classes/class_material.html#class-material-property-render-priority)
- 检查转折时，把 `BakeMesh` 的每组截面顶点与 `GetPositions` 的历史点对应起来。Unity 在当前挂点与最新历史点重合时仍分别输出两组截面。带状网格的横向方向在镜头平面内从头向尾平滑，小角度变化的插值权重更低。以最新历史段的 10% 长度作为活动头部参与转向的阈值，由三组不同段长的小样验证。把首战七帧的历史点与镜头变换送入 Unity 的同参数拖尾后，Godot 的 52 组截面方向最大误差约 0.0014°。原版还会在部分拐角延长截面，例如第 374 步的一处截面为 1.498 世界单位，对应的原始宽度曲线值为 1.400。见 `build/windows/port-yuna-trail-corner-comparison.png`。 [Unity 拖尾网格烘焙](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/trailrenderer/bakemesh)
- 量带宽时用两个截面顶点间的距离。由拖尾头部开始按 0 编号，前三组截面使用宽度曲线原值。内部截面 `i >= 3` 将曲线宽度乘以当前截面方向和前一段平滑方向点积的倒数，放大上限为 `max(1, 1.5 × length(i - 2, i - 1) / widthMultiplier)`。用两点的三维距离算上限，整体 `widthMultiplier` 随预制体导入。首战七帧的 52 组 Godot 实际顶点与 Unity 烘焙的宽度最大相差 0.00014 世界单位。对照见 `build/windows/port-yuna-trail-miter-comparison.png`。
- 核对带状网格的颜色时，用相同路径分别开关 `m_ApplyActiveColorSpace`，对照 Unity 烘焙网格的 `colors32`。材质 359 的拖尾启用这项属性，RGB 由渐变的 8 位值转换到线性光并再量化为 8 位，Alpha 保留。Godot 在顶点着色阶段做转换，便于随后在线性光中插值。首战样本验证了 52 组截面，也用生产材质在 Forward+ 和 Mobile 上测了同输入的色块。拖尾本体的红色亮带已经收敛，手里剑末端的红光外圈仍偏宽。见 `build/windows/port-yuna-trail-linear-vertex-color.png`。
- 飞行预制体的 `Trail_01:51659` 选用网格模式，四个网格槽均为空。Unity 相机读回确认有活粒子时仍无可见像素，给同一个发射器分配四边形可读到 144 个亮像素。`Trail_03:54883` 只绘制世界空间的粒子尾迹，速度和重力都为零。移动发射器并让它在不同位置出生 18 颗粒子，`BakeTrailsMesh` 返回 72 个顶点，但三角形总面积为零。给粒子速度后，带状网格面积变为 2.43。检查缺层时要区分粒子数、烘焙顶点数和实际覆盖面积。
- 飞行的 `Glow_01:53628` 与 `Line_01:55253` 随 `InternalPlay` 启用根节点而自动播放。Unity 6000.6.7f1 小样用 `GetParticles` 验证，光晕启用时已有三颗预热粒子，年龄约为 0、0.20 和 0.40 秒。稍后调用 `Play()` 重置循环相位并再次触发线丝起始爆发，保留已出生粒子的年龄和按时间发射的节奏。Godot 将两层的计时起点设在起手，线丝以 0.80 秒重复爆发，延迟播放时重新起算爆发周期。光晕每秒发射五颗，`BakeMesh` 测得 Local 模式在 0.0114 倍武器挂点下的广告牌仍宽 3.00 世界单位。第 376 步修复前无循环光晕，修复后有三颗。两层还可分别用 `--without-flight-glow` 和 `--without-flight-lines` 截帧复核。见 `build/windows/port-yuna-flight-loop-comparison.png`。 [Unity ParticleSystem.Play](https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/particlesystem/play)
- 核对暗光晕的位置时，用三组相同种子的小样记录 `GetParticles` 首次看到每颗粒子时的 `randomSeed`、年龄和世界坐标。静止组用来取得局部锥体偏移，持续移动和旋转组用来测量出生前后的挂点取样。在 137 帧每秒的小样中，发射时刻落在帧之间，Unity 仍使用当时的插值位置，偏移方向按当前帧旋转。调用 `Play()` 前后，16 个偏移与未调用的对照组一致。导入器复用已烘焙的偏移，运行时只对该发射器插值出生位置。第 376 步的实机对照见 `build/windows/port-yuna-flight-glow-birth.png`。
- 同一飞行预制体下的 `Sparkle_01:53229` 随根节点激活启动。它按距离每移动 0.5 个世界单位发射一颗，寿命 0.10 秒，停止移动后停止发射。Unity 小样中，跨帧的余距会累积，新火星按帧内跨越间距的时刻出生，出生点保持在发射器局部坐标。Godot 为火星保留原版加法混合材质 `333`、贴图 `1742`、寿命尺寸曲线和 1.5 倍拉伸。使用 Local 缩放消除武器挂点的 0.01 缩小。噪声方向和强度曲线用 Godot 的 Perlin 噪声近似，火星的逐像素位置存在差异。
- 飞行预制体的 `Dust_01:55583` 与火星共用每移动 0.5 个世界单位发射一次的规则。它在半径 0.6 的球体内生成宽 0.30 至 0.50 的黑尘，寿命 0.20 至 0.40 秒，使用材质 340 和贴图 2215。前向变体把视空间深度差乘 20 得到软淡出，Godot 对应 0.05 单位。Unity 烘焙确认挂点缩为 0.0114 时，粒子宽度与相对挂点的出生偏移均保留 Local 模式的尺寸。Godot 使用 Perlin 噪声近似漂移。第 376 步切换黑尘可见性后，Forward+ 有 82 个局部像素的 8 位亮度下降超过 3，Compatibility 有 98 个。对照见 `build/windows/port-yuna-flight-dust-comparison.png`。 [Unity 烘焙脚本](../scripts/FlightDustScaleProbe.cs)
- [起手场景](../../../../game/battle/yuna_skill_wind.tscn) 对应 `SkillAttack_01:63281`。绑定脊柱上的原版挂点，保留 `Line_01:52194` 每秒 60 发的局部风线，以及 `Wind_01:54405` 的额外 0.65 秒启动延时。局部风线的轨迹跟随脊柱，宽度来自 Trail 模块，随粒子结束回收。风圈使用原版网格、速度和旋转曲线。
- [落地烟尘场景](../../../../game/battle/yuna_skill_landing.tscn) 对应 `SkillAttack_05:63162`。施法动画开始 3.62 秒后发射 `Smoke_01:52154` 的两团烟，保留环形采样、径向速度、寿命减速、旋转和材质 `353` 的软溶解。发射时取角色当前位置，后续粒子留在世界空间。首战里角色先落格，烟尘在锁定第 409 战斗步的过渡前后可见。 [Unity 寿命速度模块](https://docs.unity3d.com/cn/2018.4/Manual/PartSysVelOverLifeModule.html)

## 校准落格后的普攻红斩

原版日志约在第 402 步收到普攻事件 100，第 409 步记录该次普攻的 80 点暴击。随后一张渲染帧出现鲜红月牙。用 `VfxHandlerComponent:63172` 的 `_basicAttackVfxReferences` 找到 `VFX_Ayaka_BasicAttack_02:61495`，其三个启用发射器共用网格 2853。红弧 `Slash_01:52764` 采样图集 2029，`Slash_02:52927` 叠加两张溶解遮罩，`Wind_01:55087` 使用加法混合。预制体中的 `Highlight_01:54633` 是禁用的 GameObject。混合与深度写入以前向通道为准。

预制体延时 0.12 秒，三个发射器再等 0.18 秒，以 1 倍攻速计算，起手后 0.30 秒发射。原版 `BaseParticleSystemVfxComponent.InternalPlay` 用动作速度除预制体延时，并把动作速度应用到列表中的发射器。红斩的三个发射器都在列表里，2 倍攻速下合计等 0.15 秒。先从 `VFXParent` 读取缩放与位置，再读取子节点 `root:29141` 的朝向。转译后的正前方偏移为 `0.413 × 1.14`，Godot 挂点抵消 FBX 导入所需的 180° 旋转。Unity 烘焙确认该粒子先绕 Z 轴再绕 X 轴、最后绕 Y 轴，Godot 采用 `EULER_ORDER_YXZ` 得到相同矩阵。图集以 4 × 8 排列，两层红弧使用第 10 帧，风纹使用第 2 帧，索引从零起算。普攻起手创建场景，粒子出生后固定在世界坐标。 [普攻红斩场景](../../../../game/battle/yuna_basic_slash.tscn)

## 重跑与验收

除了首战的单次出手，也要完整回放带多名英雄和连续施法的关卡。动画可能把挂点缩到零，使普通粒子、局部尾丝或记录世界出生变换的尾丝得不到有效逆矩阵。绘制前检查实际参与求逆的变换，折叠时跳过网格并保留粒子的寿命推进。种子 491578230 的 10101 完整回放曾记录 326 条矩阵求逆错误，修正 `revival_effect.gd` 后复跑为零。

在项目根目录运行。使用项目现有的 Godot 4.7.2 和读取 Demo 资产的 Python 环境。将变量设为本机对应路径。

```powershell
& $portPython tools/import_battle_revival.py $portUnityData --yuna-skill
& $portPython tools/import_battle_revival.py $portUnityData --yuna-basic
& $portGodot --headless --path game --script ../tools/check_melee_abilities.gd
& $portGodot --headless --path game --script ../tools/check_battle_statistics.gd
& $portGodot --headless --path game --script ../tools/check_battle_aftermath.gd
```

`--yuna-skill` 覆盖六处技能特效场景，`--yuna-basic` 覆盖普攻红斩场景。Godot 编辑器打开时，可将导出放到临时工程目录，导入新增贴图后通过编辑器的 `ResourceLoader` 和 `ResourceSaver` 保存场景。现有复活资源走默认导出路径。

复核烟粒子出生数据时，将 [烘焙脚本](../scripts/ImpactSmokeBirthProbe.cs) 放入一个临时 Unity 项目的 `Assets/Editor`，用 Unity 6000.6.7f1 运行 `-batchmode -nographics -quit -projectPath <临时项目> -executeMethod ImpactSmokeBirthProbe.Measure -logFile <日志路径>`。`SMOKE_BIRTH` 输出两次重播的出生数据，`SMOKE_BAKE` 输出网格宽度和应用层级缩放后的中心位置，`SMOKE_STREAM` 对照粒子的 `Custom2` 和烘焙后的 UV 流。

用同种子回放脚本抓取 Godot 的 819 × 616 画面。需要运行图形渲染器，输出参数为文件名前缀。

```powershell
$portFrames = (New-Item -ItemType Directory -Force build/yuna-skill-frames).FullName
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/godot"
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/control" --without-basic-slash
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/flight-control" --without-flight-trail
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/impact-control" --without-flight-sparks --without-impact-layers
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/smoke-control" --without-impact-smoke
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/hit-redraw-control" --without-hit-redraw
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/vfx-redraw-control" --without-vfx-redraw
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/release-control" --without-release-particles
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/charge-control" --without-charge-flare
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/wave-control" --without-flight-wave
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/shuriken-control" --without-shuriken-mesh
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/rim-control" --without-shuriken-rim
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/impact-core-control" --without-impact-core
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/flight-dust-control" --without-flight-dust
& $portGodot --path game --resolution 819x616 --script ../.agents/skills/guildrun-godot-skill-vfx/scripts/capture_yuna_skill.gd -- "$portFrames/flight-loop-control" --without-flight-glow --without-flight-lines
```

原版用隔离的测试存档跑首战，以战斗日志对齐截帧。比较前裁掉窗口标题栏。脚本保留关键节奏，随机粒子的角度和精确形状会随次序变化。右手蓄力、出手飞行、命中及落地分别见 `build/windows/port-yuna-charge-arc-comparison.png`、`build/windows/port-yuna-throw-comparison.png`、`build/windows/port-yuna-skill-native-comparison.png` 和 `build/windows/port-yuna-landing-smoke-comparison.png`。

Godot 第 375、377 步可看到长尾从武器挂点垂到训练龟一侧。只关闭这一层的对照保存在 `build/windows/port-yuna-flight-trail-comparison.png`。第 373 步可分辨拖尾末端的火星，早期的火星及线芒对照见 `build/windows/port-yuna-sparks-impact-comparison.png`。Godot 的蓄力与出手亮峰偏早。命中星芒的时序见 `build/windows/port-yuna-impact-timing-comparison.png`，残烟的时序见 `build/windows/port-yuna-smoke-dissolve-timing.png`。普攻红斩在 Godot 第 411 采样帧达到亮峰，此时模拟停在第 409 步。只关闭红斩的对照保存在 `build/windows/port-yuna-basic-slash-comparison.png`，边缘、角色姿势和背景光照仍有差异。

出手暗红粒子的早期同帧开关对照见 `build/windows/port-yuna-release-particles-comparison.png`。回放在第 380 步暂停表现时钟后切换发射器可见性。该图拍摄于修正软淡出系数前。

手里剑网格对照见 `build/windows/port-yuna-shuriken-mesh-comparison.png`。两个渲染后端在第 372 步均无可见网格，第 376 步均在拖尾底端显示填充和红边。导入器写成整数的着色器浮点参数会在编辑器重存时退回默认值，因此要在保存并重新加载后检查。红边倍率由 1.0 恢复至 3.0，拖尾倍率由 1.0 恢复至 4.0，同时恢复蓄力、出手、暗波纹、命中和普攻红斩中的同类参数。第 376 步冻结后只切换红边和拖尾两个倍率，Forward+ 的末端局部有 1,277 个像素的 8 位红通道上升超过 8，Compatibility 有 1,695 个。对照见 `build/windows/port-yuna-flight-hdr-comparison.png`。原版末端红光仍扩散得更宽。

冻结飞行帧后逐个关闭发射器，再单独关闭泛光并保留调色。橙色外圈主要由 `Shuriken_01` 的红边像素触发。在低亮度探针中，Forward+ 的线性红通道读回 0.1912，按原版材质上传值和粒子色计算为 0.1929。Forward+ 的手里剑着色器单独把混合前的 RGB 峰值乘 Alpha 后限制在 3.5，以校准参考帧中 HDR 外圈的范围。第 376 步在 `(325,312)–(377,358)` 采样区内，符合 R ≥ 230、120 ≤ G ≤ 235、B < 160 的像素由 725 降至 134，原版对应帧为 158。该区域的 RGB 平均绝对误差由 28.80 降至 21.40，第 381 步由 33.84 降至 25.79。两张原版参考帧的红光更碎，亮芯位置和纯红像素面积仍有差异。见 `build/windows/port-yuna-rim-hdr-comparison.png`。
