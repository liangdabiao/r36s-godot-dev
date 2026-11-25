extends Reference
class_name Srs

# FSRS-6 记忆状态递推。
#
# 计算部分（init/next stability、difficulty、forgetting curve、next_interval）
# 是 ts-fsrs 6.0.1 / models/fsrs-6/algorithm.ts 的 1:1 翻译，权重与舍入位
# 保持一致，可用 Node 版对拍验证。
#
# 排程部分（学习步长、毕业间隔、复习状态迁移）按 FSRS 官方语义实现：
# ts-fsrs 那套是 middleware 链，逐层照搬会让代码膨胀数倍，而它最终等价于
# 这里的四状态机（New / Learning / Review / Relearning）。

const DECAY := 0.1542
const S_MIN := 0.001
const S_MAX := 36500.0
const D_MIN := 1.0
const D_MAX := 10.0

const MAXIMUM_INTERVAL := 36500
const LEARNING_STEPS := [1, 10]      # 分钟
const RELEARNING_STEPS := [10]       # 分钟
const GRADUATING_INTERVAL := 1       # 天
const EASY_INTERVAL := 4             # 天

const STATE_NEW := 0
const STATE_LEARNING := 1
const STATE_REVIEW := 2
const STATE_RELEARNING := 3

const RATING_AGAIN := 1
const RATING_HARD := 2
const RATING_GOOD := 3
const RATING_EASY := 4

const RATING_NAMES := ["", "忘记", "模糊", "记得", "简单"]
const STATE_NAMES := ["新卡", "学习中", "复习", "重学"]

# FSRS6_DEFAULT_WEIGHTS
const W := [
	0.212, 1.2931, 2.3065, 8.2956, 6.4133,
	0.8334, 3.0194, 0.001, 1.8722, 0.1666,
	0.796, 1.4835, 0.0614, 0.2629, 1.6483,
	0.6014, 1.8729, 0.5425, 0.0912, 0.0658,
]

var desired_retention := 0.9
var _decay := 0.0
var _factor := 0.0


func _init(retention := 0.9) -> void:
	desired_retention = retention
	# computeDecayFactor：decay 取负，factor = exp(decay^-1 * ln 0.9) - 1
	_decay = -DECAY
	_factor = _round8(exp(pow(_decay, -1.0) * log(0.9)) - 1.0)


# ---------------------------------------------------------------- 基础数学

func _round8(value: float) -> float:
	return round(value * 100000000.0) / 100000000.0


func _clamp_s(value: float) -> float:
	return clamp(value, S_MIN, S_MAX)


func forgetting_curve(elapsed_days: float, stability: float) -> float:
	if stability <= 0.0:
		return 0.0
	return _round8(pow(1.0 + _factor * elapsed_days / stability, _decay))


func init_stability(rating: int) -> float:
	return clamp(W[rating - 1], S_MIN, S_MAX)


func init_difficulty(rating: int) -> float:
	return _round8(W[4] - exp(float(rating - 1) * W[5]) + 1.0)


func next_interval(stability: float, retention := -1.0) -> int:
	if retention <= 0.0 or retention > 1.0:
		retention = desired_retention
	var raw: float = stability / _factor * (pow(retention, 1.0 / _decay) - 1.0)
	return int(max(1, round(raw)))


func linear_damping(delta_d: float, old_d: float) -> float:
	return _round8(delta_d * (10.0 - old_d) / 9.0)


func mean_reversion(init: float, current: float) -> float:
	return _round8(W[7] * init + (1.0 - W[7]) * current)


func next_difficulty(difficulty: float, rating: int) -> float:
	var delta_d: float = -float(W[6]) * float(rating - 3)
	var next_d: float = difficulty + linear_damping(delta_d, difficulty)
	return clamp(mean_reversion(init_difficulty(RATING_EASY), next_d), D_MIN, D_MAX)


func next_recall_stability(difficulty: float, stability: float, retrievability: float, rating: int) -> float:
	var hard_penalty: float = float(W[15]) if rating == RATING_HARD else 1.0
	var easy_bound: float = float(W[16]) if rating == RATING_EASY else 1.0
	var growth: float = (1.0 + exp(float(W[8]))
		* (11.0 - difficulty)
		* pow(stability, -W[9])
		* (exp((1.0 - retrievability) * W[10]) - 1.0)
		* hard_penalty * easy_bound)
	return _round8(_clamp_s(stability * growth))


func next_forget_stability(difficulty: float, stability: float, retrievability: float) -> float:
	var value: float = (float(W[11])
		* pow(difficulty, -W[12])
		* (pow(stability + 1.0, W[13]) - 1.0)
		* exp((1.0 - retrievability) * W[14]))
	return _round8(_clamp_s(value))


func next_short_term_stability(stability: float, rating: int) -> float:
	var sinc: float = pow(stability, -float(W[19])) * exp(float(W[17]) * (float(rating) - 3.0 + float(W[18])))
	var masked: float = sinc
	if rating >= RATING_HARD:
		masked = max(sinc, 1.0)
	return _round8(_clamp_s(stability * masked))


# ---------------------------------------------------------------- 状态递推

# 返回 {stability, difficulty}，对应 algorithm.ts 的 next_state。
func next_memory_state(stability: float, difficulty: float, elapsed_days: float, rating: int) -> Dictionary:
	if stability <= 0.0 and difficulty <= 0.0:
		return {
			"stability": init_stability(rating),
			"difficulty": clamp(init_difficulty(rating), D_MIN, D_MAX),
		}
	var r: float = forgetting_curve(elapsed_days, stability)
	var new_s: float = 0.0
	if is_equal_approx(elapsed_days, 0.0):
		new_s = next_short_term_stability(stability, rating)
	elif rating == RATING_AGAIN:
		var s_after_fail: float = next_forget_stability(difficulty, stability, r)
		var next_s_min: float = stability / exp(float(W[17]) * float(W[18]))
		new_s = clamp(_round8(next_s_min), S_MIN, s_after_fail)
	else:
		new_s = next_recall_stability(difficulty, stability, r, rating)
	return {
		"stability": new_s,
		"difficulty": next_difficulty(difficulty, rating),
	}


# ---------------------------------------------------------------- 排程

# 卡片结构（存档里就用这个 dict）：
#   stability / difficulty / state / due / last / reps / lapses
func new_card(now: int) -> Dictionary:
	return {
		"stability": 0.0,
		"difficulty": 0.0,
		"state": STATE_NEW,
		"due": now,
		"last": 0,
		"reps": 0,
		"lapses": 0,
	}


func _elapsed_days(card: Dictionary, now: int) -> float:
	# ts-fsrs 用的是「整天数」（同日复习 = 0，走短期记忆分支），
	# 这里必须取整，否则同日复习会误走长期记忆公式。
	var last := int(card.get("last", 0))
	if last <= 0:
		return 0.0
	return float(max(0, (now - last) / 86400))


# 对一张卡评分，返回更新后的卡（不写盘）。
func schedule(card: Dictionary, rating: int, now: int) -> Dictionary:
	var result: Dictionary = card.duplicate()
	var state := int(card.get("state", STATE_NEW))
	var rep := int(card.get("reps", 0)) + 1
	result["reps"] = rep
	result["last"] = now

	# 新卡：直接建初始记忆状态
	if state == STATE_NEW:
		var ms: Dictionary = next_memory_state(0.0, 0.0, 0.0, rating)
		result["stability"] = ms.stability
		result["difficulty"] = ms.difficulty
		if rating == RATING_EASY:
			result["state"] = STATE_REVIEW
			result["due"] = now + max(EASY_INTERVAL, next_interval(float(ms.stability))) * 86400
		else:
			result["state"] = STATE_LEARNING
			result["due"] = now + _learning_delay(LEARNING_STEPS, 0, rating)
			result["step"] = _learning_step_index(LEARNING_STEPS, 0, rating)
		return result

	var elapsed: float = _elapsed_days(card, now)
	var ms: Dictionary = next_memory_state(
		float(card.get("stability", 0.0)),
		float(card.get("difficulty", 0.0)),
		elapsed,
		rating)
	result["stability"] = ms.stability
	result["difficulty"] = ms.difficulty

	if state == STATE_REVIEW:
		if rating == RATING_AGAIN:
			result["state"] = STATE_RELEARNING
			result["lapses"] = int(card.get("lapses", 0)) + 1
			result["step"] = 0
			result["interval"] = 0
			result["due"] = now + _learning_delay(RELEARNING_STEPS, 0, RATING_AGAIN)
			return result
		var interval := next_interval(float(ms.stability))
		var previous := int(card.get("interval", 0))
		interval = max(interval, previous + 1) if previous > 0 else max(interval, GRADUATING_INTERVAL)
		interval = min(interval, MAXIMUM_INTERVAL)
		result["state"] = STATE_REVIEW
		result["interval"] = interval
		result["due"] = now + interval * 86400
		return result

	# Learning / Relearning：走步长，Good 走完毕业
	var steps: Array = RELEARNING_STEPS if state == STATE_RELEARNING else LEARNING_STEPS
	var index := int(card.get("step", 0))
	if rating == RATING_EASY:
		var interval := max(GRADUATING_INTERVAL, next_interval(float(ms.stability)))
		interval = min(interval, MAXIMUM_INTERVAL)
		result["state"] = STATE_REVIEW
		result["interval"] = interval
		result["due"] = now + interval * 86400
		result["step"] = 0
		return result

	var next_index: int = _learning_step_index(steps, index, rating)
	if next_index >= steps.size():
		var interval := max(GRADUATING_INTERVAL, next_interval(float(ms.stability)))
		interval = min(interval, MAXIMUM_INTERVAL)
		result["state"] = STATE_REVIEW
		result["interval"] = interval
		result["due"] = now + interval * 86400
		result["step"] = 0
		return result

	result["state"] = state
	result["step"] = next_index
	result["due"] = now + _learning_delay(steps, index, rating)
	return result


func _learning_step_index(steps: Array, index: int, rating: int) -> int:
	if rating == RATING_AGAIN:
		return 0
	if rating == RATING_HARD:
		return index
	return int(min(index + 1, steps.size()))


func _learning_delay(steps: Array, index: int, rating: int) -> int:
	var minutes := 0.0
	if rating == RATING_AGAIN:
		minutes = float(steps[0])
	elif rating == RATING_HARD:
		var current := float(steps[min(index, steps.size() - 1)])
		var following := float(steps[min(index + 1, steps.size() - 1)])
		minutes = (current + following) / 2.0
	else:
		minutes = float(steps[min(index + 1, steps.size() - 1)])
	return int(max(60, round(minutes * 60.0)))


# ---------------------------------------------------------------- 展示辅助

# 下次复习的间隔，用于卡片背面提示。
func preview_intervals(card: Dictionary, now: int) -> Dictionary:
	var out: Dictionary = {}
	for rating in [RATING_AGAIN, RATING_HARD, RATING_GOOD, RATING_EASY]:
		var next: Dictionary = schedule(card, rating, now)
		out[rating] = humanize(int(next.get("due", now)) - now)
	return out


static func humanize(seconds: int) -> String:
	if seconds < 60:
		return "<1 分"
	if seconds < 3600:
		return "%d 分" % int(round(float(seconds) / 60.0))
	if seconds < 86400:
		return "%d 小时" % int(round(float(seconds) / 3600.0))
	var days := int(round(float(seconds) / 86400.0))
	if days < 30:
		return "%d 天" % days
	if days < 365:
		return "%d 个月" % int(round(float(days) / 30.0))
	return "%.1f 年" % (float(days) / 365.0)


# 记忆强度，0..1，给界面上的进度条用。
func retrievability(card: Dictionary, now: int) -> float:
	var stability := float(card.get("stability", 0.0))
	if stability <= 0.0:
		return 0.0
	return clamp(forgetting_curve(_elapsed_days(card, now), stability), 0.0, 1.0)
