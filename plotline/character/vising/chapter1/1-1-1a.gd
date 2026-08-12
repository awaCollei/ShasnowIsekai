extends Node

## 薇芯分支对话 1-1-1a — 雪影搭讪

func play() -> void:
	PlotlineManager.lock_player()

	PlotlineManager.chat_start()
	await PlotlineManager.chat("薇芯", "你要干嘛？", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "要（", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "去去去一边去。", ["雪影", "薇芯"])
	await PlotlineManager.chat("薇芯", "(薇芯撇了撇嘴，不再看你)", ["雪影", "薇芯"])
	PlotlineManager.chat_end()

	PlotlineManager.unlock_player()
	PlotlineManager.mark_quest_completed("1-1-1a")
