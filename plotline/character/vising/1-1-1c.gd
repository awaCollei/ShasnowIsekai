extends Node

## 薇芯分支对话 1-1-1c — 询问进展

func play() -> void:
	PlotlineManager.lock_player()

	PlotlineManager.chat_start()
	await PlotlineManager.chat("薇芯", "没找到吗？", ["雪影", "薇芯"])
	PlotlineManager.chat_end()

	PlotlineManager.unlock_player()
	PlotlineManager.mark_quest_completed("1-1-1c")
