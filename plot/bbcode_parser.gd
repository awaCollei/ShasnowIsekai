class_name BBCodeParser
extends RefCounted

## BBCode解析器
## 负责解析、存储和查询BBCode标签

# ==========================
# 数据结构
# ==========================
class BBCodeTag:
	var pos: int
	var length: int
	var tag: String
	var params: String  # 包含=xxx的部分
	var is_close: bool
	var is_self_closing: bool  # 自闭合标签如[br]
	
	func _init(p: int, l: int, t: String, params_str: String, close: bool, self_close: bool = false):
		pos = p
		length = l
		tag = t
		params = params_str
		is_close = close
		is_self_closing = self_close
	
	func _to_string() -> String:
		return "BBCodeTag(pos=%d, tag=%s, is_close=%s, is_self_closing=%s)" % [pos, tag, is_close, is_self_closing]

var _tags: Array[BBCodeTag] = []
var _current_text: String = ""

# 自闭合标签列表（不产生闭合标签）
const SELF_CLOSING_TAGS := ["br", "hr", "img"]

# ==========================
# 公共方法
# ==========================

## 解析文本中的所有BBCode标签
func parse(text: String) -> void:
	_current_text = text
	_tags.clear()
	
	var regex := RegEx.new()
	# 匹配 [tag] 或 [tag=xxx] 或 [tag/] 或 [/tag]
	regex.compile("\\[(/?)(\\w+)([^\\]]*)\\]")
	
	for match in regex.search_all(text):
		var tag_name := match.get_string(2)
		var is_close := match.get_string(1) == "/"
		var params := match.get_string(3)
		var is_self_closing := tag_name in SELF_CLOSING_TAGS
		
		# 对于自闭合标签，即使有闭合标记也忽略
		if is_self_closing and is_close:
			continue
		
		_tags.append(BBCodeTag.new(
			match.get_start(),
			match.get_string().length(),
			tag_name,
			params,
			is_close,
			is_self_closing
		))


## 获取所有标签
func get_all_tags() -> Array[BBCodeTag]:
	return _tags


## 获取指定位置之前所有已开未闭的标签
## 注意：返回顺序为从内到外（后开的先闭），以便正确补全
func get_unclosed_tags_at_position(pos: int) -> Array[String]:
	var open_stack: Array[String] = []  # 使用栈来跟踪打开的标签
	var tag_stack: Array[String] = []   # 记录所有打开标签的顺序
	
	for tag_info in _tags:
		# 跳过自闭合标签
		if tag_info.is_self_closing:
			continue
		
		# 只处理开始标签位置在当前显示范围内的
		if tag_info.pos >= pos:
			break
		
		if not tag_info.is_close:
			# 开始标签：压栈
			open_stack.append(tag_info.tag)
			tag_stack.append(tag_info.tag)
		else:
			# 闭合标签：从栈中弹出对应的开始标签
			if not open_stack.is_empty() and open_stack[-1] == tag_info.tag:
				open_stack.pop_back()
				# 从tag_stack中移除对应的标签（最后一个匹配的）
				for i in range(tag_stack.size() - 1, -1, -1):
					if tag_stack[i] == tag_info.tag:
						tag_stack.remove_at(i)
						break
			else:
				# 标签不匹配，但为了容错，尝试从栈中移除
				var index := open_stack.find(tag_info.tag)
				if index != -1:
					open_stack.remove_at(index)
					tag_stack.remove_at(index)
	
	# 返回所有未闭合的标签（从内到外顺序）
	var result: Array[String] = []
	for tag in tag_stack:
		result.append(tag)
	
	# 反转顺序：从内到外（后开的先闭）
	result.reverse()
	
	return result


## 获取指定位置之后下一个有效字符的位置（跳过所有标签）
func get_next_char_position(pos: int, text: String) -> int:
	var current_pos := pos
	
	while current_pos < text.length():
		var in_tag := false
		for tag in _tags:
			if current_pos >= tag.pos and current_pos < tag.pos + tag.length:
				in_tag = true
				current_pos = tag.pos + tag.length
				break
		
		if not in_tag:
			break
	
	return current_pos


## 判断指定位置是否在标签内部
func is_position_in_tag(pos: int) -> bool:
	for tag in _tags:
		if pos >= tag.pos and pos < tag.pos + tag.length:
			return true
	return false


## 获取指定位置的标签信息（如果有）
func get_tag_at_position(pos: int) -> BBCodeTag:
	for tag in _tags:
		if pos >= tag.pos and pos < tag.pos + tag.length:
			return tag
	return null


## 清理所有数据
func clear() -> void:
	_tags.clear()
	_current_text = ""


## 获取标签统计信息（调试用）
func get_statistics() -> Dictionary:
	var total := _tags.size()
	var opening := 0
	var closing := 0
	var self_closing := 0
	
	for tag in _tags:
		if tag.is_self_closing:
			self_closing += 1
		elif tag.is_close:
			closing += 1
		else:
			opening += 1
	
	return {
		"total": total,
		"opening": opening,
		"closing": closing,
		"self_closing": self_closing
	}

# ==========================
# 高级功能
# ==========================

## 验证BBCode标签是否配对正确
func validate_tags() -> Dictionary:
	var errors: Array[String] = []
	var stack: Array[String] = []
	
	for tag in _tags:
		if tag.is_self_closing:
			continue
		
		if not tag.is_close:
			stack.append(tag.tag)
		else:
			if stack.is_empty():
				errors.append("多余的闭合标签: [/%s] 在位置 %d" % [tag.tag, tag.pos])
			elif stack[-1] != tag.tag:
				errors.append("标签不匹配: 期望 [/%s]，实际 [/%s] 在位置 %d" % [stack[-1], tag.tag, tag.pos])
			else:
				stack.pop_back()
	
	if not stack.is_empty():
		errors.append("未闭合的标签: %s" % str(stack))
	
	return {
		"is_valid": errors.is_empty(),
		"errors": errors,
		"unclosed_tags": stack
	}


## 移除文本中的所有BBCode标签（获取纯文本）
func strip_tags(text: String) -> String:
	var result := text
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]+\\]")
	return regex.sub(result, "", true)


## 获取标签之间的文本内容
func get_tag_content(tag_name: String) -> Array[String]:
	var contents: Array[String] = []
	var depth := 0
	var start_pos := -1
	
	for i in range(_current_text.length()):
		var tag := get_tag_at_position(i)
		if tag and tag.tag == tag_name and not tag.is_self_closing:
			if not tag.is_close and depth == 0:
				start_pos = tag.pos + tag.length
			elif tag.is_close and depth > 0:
				depth -= 1
				if depth == 0 and start_pos != -1:
					var content := _current_text.substr(start_pos, tag.pos - start_pos)
					if not content.is_empty():
						contents.append(content)
					start_pos = -1
			elif not tag.is_close:
				depth += 1
	
	return contents