extends Node


func play() -> void:
	var player = PlotlineManager._get_player()
	PlotlineManager.lock_player()
	await PlotlineManager.character_move(player, Vector2(-2000, 630), "teleport")
	await PlotlineManager.black_fade_in(0)
	await PlotlineManager.show_black_text("16岁，500天，21岁，懂？")
	await PlotlineManager.show_black_text("你，宅，便利店，女孩，大运，懂？")
	await PlotlineManager.black_fade_out()
	PlotlineManager.chat_start()
	await PlotlineManager.chat("雪影", "...", [])
	await PlotlineManager.chat("雪影", "[color=gray]（你望着飘荡着不明气体的天空）[/color]", ["雪影"])
	await PlotlineManager.chat("雪影", "[color=red]***[/color]，你大爷呀，给我干哪儿来了，这还是国内吗？", ["雪影"])
	await PlotlineManager.chat("雪影", "...", [])
	PlotlineManager.chat_end()
	await get_tree().create_timer(1.0).timeout
	PlotlineManager.character_set_direction(player, "right")
	await get_tree().create_timer(1.0).timeout
	PlotlineManager.chat_start()
	await PlotlineManager.chat("雪影", "？", ["雪影",""],"right")
	var vising = PlotlineManager.create_character("vising", Vector2(-1400, 630))
	PlotlineManager.character_set_direction(vising, "left")
	await PlotlineManager.character_move(vising, Vector2(-1800, 630), "walk")
	await get_tree().create_timer(1.0).timeout
	await PlotlineManager.chat(["？？？","薇芯"], "你醒啦，你已经是女孩子啦！", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "这是好事啊（", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "不对...你谁啊？！", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "我是薇芯，还记得那辆大运吗？", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "...?", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "记得就行，大运为了躲你失控侧翻了。[br]我应该是直接扁了，比你死得还早。", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "...", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "抱歉，微心", ["雪影", "薇芯"])
	#此处薇芯名称错误为剧情设计，笨雪影忘关注薇芯是哪两个字了
	await PlotlineManager.chat("薇芯", "[s]...上辈子的事别提了[/s]，走，先去基地,外面不是很安全。", ["雪影", "薇芯"])
	PlotlineManager.chat_end()
	await PlotlineManager.character_move(vising, Vector2(-150, 630), "teleport")
	PlotlineManager.character_set_direction(vising, "right")
	await PlotlineManager.character_move(player, Vector2(0, 630), "teleport")
	await get_tree().create_timer(2.0).timeout

	await PlotlineManager.black_fade_in()
	await PlotlineManager.show_black_text("......")
	await PlotlineManager.show_black_text("你雪影姐只用了一秒就接受了异世界有房车这件事")
	await PlotlineManager.black_fade_out()

	PlotlineManager.destroy_character(vising)
	PlotlineManager.unlock_player()

	PlotlineManager.mark_quest_completed("0-0-1")
