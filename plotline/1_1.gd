extends Node

## 示例剧情 1_1 — 演示基础的 chat_start / chat / chat_end 用法

func play() -> void:
	await PlotlineManager.black_fade_in(0)
	await PlotlineManager.show_black_text("你，宅，便利店，女孩，大运，懂？")
	await PlotlineManager.black_fade_out()

	PlotlineManager.chat_start()
	await PlotlineManager.chat("雪影", "陌生的天花板...", [])
	await PlotlineManager.chat("雪影", "不对这是天空...", [])
	await PlotlineManager.chat("雪影", "...", ["雪影"])
	await PlotlineManager.chat("雪影", "我艹了，给我干哪儿来了，这还是国内吗？", ["雪影"])
	var player = PlotlineManager._get_player()
	PlotlineManager.character_set_direction(player, "right")
	await PlotlineManager.chat("雪影", "？", ["雪影",""],"right")
	var vising = PlotlineManager.create_character("vising", Vector2(-1600, 630))
	PlotlineManager.character_set_direction(vising, "left")
	await PlotlineManager.character_move(vising, Vector2(-1800, 630), "walk")
	await get_tree().create_timer(1.0).timeout
	await PlotlineManager.chat(["？？？","薇芯"], "你醒啦，你已经是女孩子啦！", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "我本来就是女的...", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "不对你谁啊？！", ["雪影", "薇芯"])
	PlotlineManager.destroy_character(vising)
	PlotlineManager.chat_end()
	PlotlineManager.mark_quest_completed("1_1")
