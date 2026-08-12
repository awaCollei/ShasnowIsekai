# ⚙️ ShasnowIsekai 物品结构 v4.0

---

## 一、品质体系

| 品质 | 名称 | 颜色 | 颜色码 | 数值倍率 | 特征 |
|---|---|---|---|---|---|
| ⬜ | 普通 | 白 | `#FFFFFF` | ×1.0 | 随处可见，基础品质 |
| 🟩 | 精良 | 绿 | `#00CC44` | ×1.5 | 略有价值，常见于商店 |
| 🟦 | 稀有 | 蓝 | `#2288FF` | ×2.5 | 值得关注，精英敌人掉落 |
| 🟪 | 史诗 | 紫 | `#AA44FF` | ×4.0 | 非常珍贵，BOSS/隐藏区域 |
| 🟨 | 传说 | 金 | `#FFAA00` | ×7.0 | 独一无二，主线/世界级奖励 |
| 🟥 | **禁忌** | 红 | `#FF3333` | ×6.0 +副作用 | 蕴含不稳定魔素，使用有代价 |

> **"禁忌"叙事说明**：被污染/异变的魔素结晶化的物品。使用后可能触发诅咒、吸引魔物、或造成不可逆的身体变异。数值回报略低于传说（×6.0 vs ×7.0），但附带独特效果或代价。

---

## 二、物品分类（七大类）

### 1. 🗡️ 装备 `equipment`
> 可穿戴/装备的持续生效物品，占据对应的装备槽

| 子类 | ID | 说明 | 典型槽位 |
|---|---|---|---|
| 武器 | `weapon` | 近战武器、远程武器、特殊武器 | 主手/双手 |
| 防具 | `armor` | 头部、躯干、手部、腿部、足部护具 | 对应身体部位 |
| 饰品 | `accessory` | 戒指、项链、护符、徽章 | 饰品槽(2-3个) |
| 改造装置 | `augment` | 义体植入件、生物湿件义肢、魔导增幅器、外骨骼 | 改造槽(有限) |

> **改造装置 vs 饰品**：改造装置需要与身体结合/替换身体部件（植入型），饰品是外挂佩戴型。设计意图：改造装置提供更强但不可逆的效果，与世界观"生物机械"主题呼应。

### 2. 🧪 消耗品 `consumable`
> 使用后消耗/消失的一次性物品

| 子类 | ID | 说明 |
|---|---|---|
| 食物 | `food` | 恢复体力/生命，部分有临时增益效果 |
| 饮水 | `water` | 恢复口渴度，纯净度影响效果 |
| 魔药 | `potion` | 治疗/强化/抗性/功能型药剂 |
| 卷轴 | `scroll` | 一次性技能释放或技能习得（`scroll_type`: `"use"` / `"learn"`） |
| 投掷物 | `throwable` | 炸弹、陷阱装置、诱饵、烟雾弹等战场消耗品 |

> **卷轴设计**：不再拆分为两个子类。`scroll_type: "use"` = 一次性释放效果后消失；`scroll_type: "learn"` = 习得永久技能/配方后消失。

### 3. 🧱 材料 `material`
> 用于合成/制作的原料，可堆叠

| 子类 | ID | 主要来源 | 说明 |
|---|---|---|---|
| 矿物 | `ore` | 采矿/购买 | 铁、银、魔素水晶矿石等 |
| 丝物与纤维 | `fiber` | 采集/掉落 | 丝线、布料、皮革、合成纤维 |
| 魔物材料 | `monster_drop` | 击杀掉落 | 器官、血液、甲壳、尖牙、骨骼 |
| 异变材料 | `mutant_drop` | 击杀变异魔物 | 不可直接合成但可分解/精炼的稀有掉落 |
| 魔素结晶 | `mana_crystal` | 采集/掉落/提炼 | 不同纯度、不同属性的魔素结晶 |
| 生物湿件 | `wetware` | 掉落/分解 | 神经组织、感知器官、运动单元（可用于制造改造装置） |
| 制成品 | `component` | 合成/购买/拆解 | 零件、电路板、机械组件、半成品 |

> **异变材料 vs 魔物材料**：异变材料来自变异/精英魔物，比普通魔物材料更稀有。部分异变材料可直接高价出售，部分可通过特殊配方精炼后用于高级合成。

### 4. 🔑 关键物品 `key_item`
> 剧情/任务相关，默认不可丢弃、不可出售

| 子类 | ID | 说明 |
|---|---|---|
| 剧情信物 | `story_token` | 与角色/事件关联的关键物品 |
| 任务凭证 | `quest_item` | 任务链中需交付/出示/收集的物品 |
| 钥匙与通行证 | `key` | 解锁区域/宝箱/门的钥匙或权限卡 |
| 工具与容器 | `tool` | 背包扩容、采集工具、钥匙串等功能性永久物品 |

### 5. 📖 知识物品 `knowledge`
> 可阅读/学习，解锁世界观、配方或制造能力

| 子类 | ID | 说明 |
|---|---|---|
| 世界观资料 | `lore` | 书籍、日志、数据芯片、研究报告 |
| 图纸 | `blueprint` | 装备图纸、机械图纸、生物机械图纸（解锁制造配方） |
| 配方 | `recipe` | 魔药配方、合成公式（解锁炼金/合成配方） |

### 6. 💎 贵重品 `valuable`
> 仅用于出售换钱，无合成/实用价值

| 子类 | ID | 说明 |
|---|---|---|
| 精美艺术品 | `artwork` | 画作、雕塑、古董、文物 |
| 精密机械 | `intact_machine` | 完好且仍可运作的古代/外星机械装置 |
| 宝石与贵金属 | `gem` | 钻石、纯金锭、装饰性贵重矿石 |

> ⚠️ **边界提醒**：如果某个"精密机械"可以拆解出材料零件 → 它应该是材料类而非贵重品类。策划录入时需判断是否可拆解。

### 7. 💰 货币 `currency`
> 购买与交换媒介，不占背包格子

| 子类 | ID | 说明 |
|---|---|---|
| 魔能点 | `mana_point` | 主货币，魔能盒存储（上限 2³² ≈ 42.9亿） |
| 特殊代币 | `special_token` | 商店限定、活动限定、阵营货币 |

### 8.其它物品 `others` 
>小巧思
---

## 三、物品标签系统

> 跨分类的附加属性，一个物品可以挂多个标签。

| 标签 | ID | 默认启用条件 | 说明 |
|---|---|---|---|
| 不可丢弃 | `undroppable` | 关键物品 | 不能在背包中丢弃 |
| 不可出售 | `unsellable` | 关键物品 | 商店拒绝收购 |
| 成就物品 | `achievement` | 无 | 首次获得时触发对应成就 |
| 唯一 | `unique` | 传说/禁忌品质 | 全局仅此一件，不可重复获得 |
| 剧情隐藏 | `story_hidden` | 无 | 不通过常规途径获取，仅剧情/彩蛋产出 |

---

## 四、物品数据结构（参考）

每个物品的基础数据字段，可转化为 GDScript `Resource`：

```gdscript
# ItemData Resource 定义
class_name ItemData extends Resource

# 基础字段
@export var id: String              # 唯一标识符，如 "ore_iron_01"
@export var display_name: String    # 显示名称
@export var category: Category      # 七大类枚举
@export var sub_category: SubCategory  # 子类枚举
@export var quality: Quality        # 品质枚举
@export var tags: Array[Tag]        # 标签列表
@export_multiline var description: String  # 描述文本
@export var icon: Texture2D         # 图标
@export var stack_max: int = 99     # 最大堆叠数
@export var base_value: int = 0     # 基础售价（魔能点）

# 分类专属字段
@export var equipment_slot: Slot    # (装备专属) 槽位类型
@export var scroll_type: String     # (卷轴专属) "use" | "learn"

# 计算属性
var sell_value: int:                # 实际售价 = 基础值 × 品质倍率
	get: return int(base_value * quality_mult)

var quality_mult: float:            # 品质倍率
	get:
		match quality:
			Quality.COMMON:    return 1.0
			Quality.UNCOMMON:  return 1.5
			Quality.RARE:      return 2.5
			Quality.EPIC:      return 4.0
			Quality.LEGENDARY: return 7.0
			Quality.FORBIDDEN: return 6.0
		return 1.0
```

---

## 五、枚举定义

```gdscript
enum Category {
	EQUIPMENT,    # 装备
	CONSUMABLE,   # 消耗品
	MATERIAL,     # 材料
	KEY_ITEM,     # 关键物品
	KNOWLEDGE,    # 知识物品
	VALUABLE,     # 贵重品
	CURRENCY,     # 货币
}

enum Quality {
	COMMON,       # 白 普通 ×1.0
	UNCOMMON,     # 绿 精良 ×1.5
	RARE,         # 蓝 稀有 ×2.5
	EPIC,         # 紫 史诗 ×4.0
	LEGENDARY,    # 金 传说 ×7.0
	FORBIDDEN,    # 红 禁忌 ×6.0
}

enum SubCategory {
	# 装备子类
	WEAPON, ARMOR, ACCESSORY, AUGMENT,
	# 消耗品子类
	FOOD, WATER, POTION, SCROLL, THROWABLE,
	# 材料子类
	ORE, FIBER, WOOD, MONSTER_DROP, MUTANT_DROP, MANA_CRYSTAL, WETWARE, COMPONENT,
	# 关键物品子类
	STORY_TOKEN, QUEST_ITEM, KEY, TOOL,
	# 知识物品子类
	LORE, BLUEPRINT, RECIPE,
	# 贵重品子类
	ARTWORK, INTACT_MACHINE, GEM,
	# 货币子类
	MANA_POINT, SPECIAL_TOKEN,
}

enum Tag {
	UNDROPPABLE, UNSELLABLE, ACHIEVEMENT, UNIQUE, STORY_HIDDEN,
}
```
