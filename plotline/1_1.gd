extends Node

## 示例剧情 1_1 — 演示基础的 chat_start / chat / chat_end 用法

func play() -> void:
	PlotlineManager.chat_start()

	await PlotlineManager.chat("雪影", "你好，我是雪影。", ["雪影"])
	await PlotlineManager.chat("薇芯", "我是薇芯，很高兴认识你。", ["雪影", "薇芯"])
	await PlotlineManager.chat("雪影", "我们一起来冒险吧！", ["雪影", "薇芯"])

	PlotlineManager.chat_end()
