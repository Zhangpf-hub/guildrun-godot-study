# Dragomir 装配与批量验收

## 顺着原版事件核对

Steam Demo build 26551710 中，单位 24 使用 VisualConfig `sharedassets1.assets:60916`。选择可随正常战斗请求触发的技能和普攻，核对 `VfxHandlerComponent` 原生分发，再解析 prefab 中带数组序号的引用。

| 动作 | 原副本组件 | 延时 | 资源与材质 |
| --- | --- | ---: | --- |
| 普攻 | `sharedassets1.assets:62965` | 0.333 秒 | 2 个启用发射器，原材质使用 Shader Graph 3008 |
| 技能 | `sharedassets1.assets:62767` | 0.25 秒 | 14 个启用发射器，原材质使用 Shader Graph 711、3022 |

两者均挂在 Dragomir 根节点 `23403` 的 `VFXParent` 下。比较 Unity Transform 链和 Godot 战斗中加载的模型实例。样板把前向偏移转为 Godot 坐标，把根缩放 1.18 写入挂载配置。技能根位置从 `(0, 1.5, 2)` 变成单位局部的 `(0, 1.77, -2.36)`。

REA 可用时用它核对本构建的行为和元数据。当前环境从 npm 离线缓存运行 `npx --offline --yes rea-agents@6.9.0 inspect-il2cpp-metadata <global-metadata.dat> --json`。将完整 JSON 写入构建目录，只输出证据 ID 和精简的类型或方法摘要。该结果可确认类型信息，分发逻辑来自原生方法证据。PPtr、Transform 与材质参数从 Unity 序列化资产读取。

## 复用入口

- 从 FX 组件选出真正启用的发射器。调用 `tools/import_battle_revival.py` 的 `export_prefab` 生成场景，逐个核对贴图、渲染网格、材质通道及发射模块。场景文件生成到暂存目录，确认资源依赖可用后通过编辑器桥加载和保存，检查重载后的场景根、发射器数量和浮点字段。
- `game/Characters/action_vfx/<visual_id>.json` 可用 `BasicAttack`、`SkillAttack` 和 `Die` 作为事件，每个值是由 `scene` 和可选 `bone`、`position`、`rotation`、`scale` 组成的数组。坐标以 Godot 局部空间表示。挂载矩阵乘在已导出的 FX 场景根变换之前。骨骼需要实机确认方向，且必须属于运行时实例。等级通过 `ranks` 中的数字字符串查找事件覆盖。特效和模型都按角色实际等级选取。
- 攻速用于动作事件延时和源组件指定的发射器。战斗倍速及暂停走战斗表现时钟。目标、伤害与投射物命中仍由战斗定步推进。
- 专用播放路径包含角色等级变体、`ScalingVfxHandlerComponent` 的有序条件、独立目标点、命中或弹道、相机震动，以及幼娜和 Funke 已有装配。按原分发代码选中分支和调用时点。避免在普通动作入口再播放一次。

## 批处理复跑

用项目已配置的 UnityPy 环境从项目根目录执行。输入目录是该构建的 `Guildrun_Data`。

```text
python tools/character_source_inventory.py <Guildrun_Data> build/character-port/inventory/characters.json
python tools/import_character_action_vfx.py <Guildrun_Data> build/character-port/inventory/characters.json build/character-port/actions
python tools/animation_plan.py <Guildrun_Data> build/character-port/rank-batch/plan.tsv --ranked --output build/character-port/rank-batch/stage
```

先检查暂存资源的依赖和 `coverage.json`。单角色迭代给动作导入器传 `--visual <visual_id>`，给骨骼计划传 `--visual-id <visual_id> --rank <rank>`。使用 `tools/ExportCharacterAnimations.cs` 对计划中的 Animator 和动作导出 FBX。把验证通过的等级模型放到 `game/rigs/<animator_id>/`，并用生成的 `rank_rigs.json` 部署。Godot 编辑器打开时，用桥载入及保存验证过的 PackedScene。普通弹道另用 `tools/import_character_projectiles.py`，复用原目标骨骼、偏移、方向轴及曲线。

原版 `EntityUpdater.PreSpawnEntityView` 调用 `CharacterVisualConfig.GetPrefabForRank`，有效项为 `PrefabsPerRank[rank - 1]`，空项回退到 `Prefab`。Dragomir 的基础 prefab 是二阶，其他三个等级使用独立模型和特效引用。FBX 已包含模型缩放，角色局部特效根仍需应用对应等级从 Unity 读取的原始缩放。Javryn 的弓动画属于默认关闭的特效 Animator，每个等级具有独立 Animator PathID。对照着色器字段与生成后的目标资源，并跑实际等级部署。

等级 FBX 还可能保留原 prefab 的预览平移。Pimenta 的二阶至四阶有非零根节点平移，部署时应根据 `board_origin_node` 将模型根对齐到棋盘格。保留缩放并核对角色可见部分在实际关卡中的位置。仅校验动画和材质资源能否加载会漏掉这种偏移。

四阶的 `Toon_Galaxy_SG` 有专用色阶、遮罩和两张立方体贴图。先确认每张源贴图已在 Godot 导入，并检查普通贴图与 CubeMap 的类型，再保存 ShaderMaterial。贴图导入未完成时，场景保存可能丢掉着色器参数引用。重载后逐项核对 `toon_ramp`、贴图 PathID 和立方体压缩数据，再截查四阶发光、扫过表面的图案和阴影。记录实际运行时使用的渲染后端。

## 验收

通过关卡的 `deploy_hero` 和 `begin_basic_attack`、`begin_active_ability` 检查正常路径。Dragomir 样板验证了两场景的发射器数、2 倍攻速下普攻延时、战斗暂停和倍速、位置与死亡清理。复跑 `tools/check_character_action_vfx.gd`、`tools/check_character_materials.gd` 和已有技能回归。逐角色检查真实招募或部署实例，包含导入节点名、表面槽、描边和动作循环。

先做材质数据对照，再在同镜头、同动作阶段检查原版与 Godot 帧。两个层级都记录。因渲染通道或素材未能验证而未通过的事件，保存组件 ID、剩余差异和复现入口。整批输出中逐角色注明普攻、施法、命中、弹道等有源数据的阶段。
