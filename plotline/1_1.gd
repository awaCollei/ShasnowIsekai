extends Node

## 示例剧情 1_1 — 演示基础的 chat_start / chat / chat_end 用法

func play() -> void:
	var player = PlotlineManager._get_player()
	var vising = PlotlineManager.create_character("vising", Vector2(-1400, 630))
	PlotlineManager.lock_player()
	await PlotlineManager.character_move(player, Vector2(-2000, 630), "teleport")
	await PlotlineManager.black_fade_in(0)
	await PlotlineManager.show_black_text("16岁，500天，18岁，懂？")
	await PlotlineManager.show_black_text("你，宅，便利店，女孩，大运，懂？")
	await PlotlineManager.black_fade_out()
	PlotlineManager.chat_start()
	await PlotlineManager.chat("雪影", "...", [])
	await PlotlineManager.chat("雪影", "...", ["雪影"])
	await PlotlineManager.chat("雪影", "我艹了，给我干哪儿来了，这还是国内吗？", ["雪影"])
	PlotlineManager.chat_end()
	await get_tree().create_timer(1.0).timeout
	PlotlineManager.character_set_direction(player, "right")
	await get_tree().create_timer(1.0).timeout
	PlotlineManager.chat_start()
	await PlotlineManager.chat("雪影", "？", ["雪影",""],"right")
	PlotlineManager.character_set_direction(vising, "left")
	await PlotlineManager.character_move(vising, Vector2(-1800, 630), "walk")
	await get_tree().create_timer(1.0).timeout
	await PlotlineManager.chat(["？？？","薇芯"], "你醒啦，你已经是女孩子啦！", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "我本来就是女的...", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "不对你谁啊？！", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "我也是撞大运来的，比你早几天", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "走，先去基地", ["雪影", "薇芯"])
	PlotlineManager.chat_end()
	await PlotlineManager.character_move(vising, Vector2(-150, 630), "teleport")
	PlotlineManager.character_set_direction(vising, "right")
	await PlotlineManager.character_move(player, Vector2(0, 630), "teleport")
	await get_tree().create_timer(2.0).timeout

	await PlotlineManager.black_fade_in()
	await PlotlineManager.show_black_text("你雪影姐只用了一秒就接受了异世界有房车这个事实")
	await PlotlineManager.black_fade_out()

	PlotlineManager.destroy_character(vising)
	PlotlineManager.unlock_player()

	PlotlineManager.mark_quest_completed("1_1")
