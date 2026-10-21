class_name WorldClock
extends RefCounted
## Domain calendar for one campaign.
##
## The canonical unit is one in-game minute. Presentation and real-time
## speed controls may change later without changing saved world time.
## Baseline calendar: 24 hours/day, 30 days/season, 4 seasons/year.

const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := MINUTES_PER_HOUR * HOURS_PER_DAY
const DAYS_PER_SEASON := 30
const SEASONS_PER_YEAR := 4
const DAYS_PER_YEAR := DAYS_PER_SEASON * SEASONS_PER_YEAR

var _total_minutes: int = 0


func setup(total_minutes: int = 0) -> void:
	_total_minutes = maxi(total_minutes, 0)


func total_minutes() -> int:
	return _total_minutes


func minute_of_day() -> int:
	return _total_minutes % MINUTES_PER_DAY


func hour_of_day() -> int:
	return minute_of_day() / MINUTES_PER_HOUR


func minute_of_hour() -> int:
	return minute_of_day() % MINUTES_PER_HOUR


func total_days_elapsed() -> int:
	return _total_minutes / MINUTES_PER_DAY


func day_of_season() -> int:
	return (total_days_elapsed() % DAYS_PER_SEASON) + 1


func season_index() -> int:
	return (total_days_elapsed() / DAYS_PER_SEASON) % SEASONS_PER_YEAR


func year_number() -> int:
	return (total_days_elapsed() / DAYS_PER_YEAR) + 1


## Advances time and reports how many calendar boundaries were crossed.
## The future scheduler uses these counters instead of letting individual
## nodes guess boundaries from accumulated frame delta.
func advance_minutes(amount: int) -> Dictionary:
	if amount < 0:
		push_warning("WorldClock.advance_minutes: negative amount %d ignored" % amount)
		return _boundary_report(0, 0, 0, 0)

	var before_hours := _total_minutes / MINUTES_PER_HOUR
	var before_days := _total_minutes / MINUTES_PER_DAY
	var before_seasons := before_days / DAYS_PER_SEASON
	var before_years := before_days / DAYS_PER_YEAR

	_total_minutes += amount

	var after_hours := _total_minutes / MINUTES_PER_HOUR
	var after_days := _total_minutes / MINUTES_PER_DAY
	var after_seasons := after_days / DAYS_PER_SEASON
	var after_years := after_days / DAYS_PER_YEAR

	return _boundary_report(
		after_hours - before_hours,
		after_days - before_days,
		after_seasons - before_seasons,
		after_years - before_years
	)


func snapshot_state() -> Dictionary:
	return {"total_minutes": _total_minutes}


func restore_state(snapshot: Dictionary) -> bool:
	if not snapshot.has("total_minutes"):
		return false
	setup(int(snapshot["total_minutes"]))
	return true


func _boundary_report(hours: int, days: int, seasons: int, years: int) -> Dictionary:
	return {
		"hours_crossed": hours,
		"days_crossed": days,
		"seasons_crossed": seasons,
		"years_crossed": years,
	}
