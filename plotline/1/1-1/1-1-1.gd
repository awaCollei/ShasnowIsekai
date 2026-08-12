extends Node

## 1-1 赴往芦星的开端
## 进入房车后检测是否触发过剧情1-1-1，若没有则立即触发本对话。

func play() -> void:
	var player = PlotlineManager._get_player()
	await PlotlineManager.black_fade_in()
	# 传送玩家（shasnow）到房车内右侧位置
	await PlotlineManager.character_move(player, Vector2(126, 546), "teleport")
	PlotlineManager.character_set_direction(player, "left")
	# 创建薇芯在房车内左侧位置
	var vising = PlotlineManager.create_character("vising", Vector2(-115, 542))
	PlotlineManager.character_set_direction(vising, "right")
	PlotlineManager.change_sub_scene("rv_indoor")
	await PlotlineManager.black_fade_out()

	PlotlineManager.lock_player()

	PlotlineManager.chat_start()
	await PlotlineManager.chat("薇芯", "hi，怎么称呼？", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "雪影。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "哪个雪哪个影？", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "小雪的雪，阴影的影（", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "上了我的车就是我的人了哦~", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "不是哥们。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "是哥们也没用，哼哼~", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "好啦开玩笑，欢迎来到芦星。", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "[color=yellow]……星芦？[/color]", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "[color=gray]（白眼）[/color]不许倒过来念。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "这可是异世界，有各种魔物和丧尸，这几天可吓死我了。", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "[color=gray]（环顾四周）[/color]这房车你带过来的？", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "没有，路边捡的。上任主人似乎是魔素紊乱死这里面了，费了我好大功夫才清理干净呢。", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "[color=gray]（后背一凉）[/color]魔素是啥？", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "魔力？反正是类似的东西。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "我接手了原主人的手稿和资料，这可不是一般的房车。[br]咱老家的技术原理在这已经用不了了。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "这车的动力就跟这个世界的魔素相关，但手稿上的某些文字我还看不懂。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "我需要一点富含魔素的材料来研究原理，我想魔物身上肯定会有。[br]就交给你了雪影！", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "我…我吗？", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "又寸。房车里有武器来着，还有一些剩下的食物。[br] 你降临的地方附近应该就有史莱姆。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "加油！我们两个能不能做大做强再创辉煌就看你了！", ["雪影", "薇芯"])
	PlotlineManager.chat_end()

	PlotlineManager.unlock_player()
	PlotlineManager.mark_quest_completed("1-1-1")
