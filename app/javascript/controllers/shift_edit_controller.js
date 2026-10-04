import { Controller } from "@hotwired/stimulus"

// 役割：select変更 → 同じ行の表示(.shift-edit-display)更新 → debounceしてPATCH → 成功したら右サイドバー更新
export default class extends Controller {
  connect() {
    this._saveTimer = null
  }

  change(event) {
    const select = event.target
    if (!select) return

    const row = select.closest(".shift-edit-row")
    const display = row ? row.querySelector(".shift-edit-display") : null
    if (!display) return

    const nameBase = select.dataset.staffName || ""
    const raw = select.value // "early" / "late" / "off" / "off:requested_off" / "off:paid_leave" / "day:12"

    let kind = raw
    let holidayType = null
    let staffDayTimeOptionId = null
    let shiftMonthTimeOptionId = null

    if (raw && raw.startsWith("day:")) {
      kind = "day"
      const parts = raw.split(":")
      staffDayTimeOptionId = parts[1] ? parseInt(parts[1], 10) : null
    } else if (raw && raw.startsWith("late:")) {
      kind = "late"
      const parts = raw.split(":")
      shiftMonthTimeOptionId = parts[1] ? parseInt(parts[1], 10) : null
    } else if (raw && raw.startsWith("off:")) {
      kind = "off"
      const parts = raw.split(":")
      holidayType = parts[1] || null
    }

    const isOff = (kind === "off")

    // 表示用の時間文字列（optionのdata-time-textを優先）
    let timeText = ""
    const selectedOpt = select.options[select.selectedIndex]
    const optTime = selectedOpt ? selectedOpt.dataset.timeText : ""

    if (kind === "early") timeText = "(730-1630)"
    if (kind === "late" && optTime)  timeText = `(${optTime})`
    if (kind === "day" && optTime) timeText = `(${optTime})`

    display.classList.toggle("is-off", isOff)

    let nameEl = display.querySelector(".shift-edit-name")
    if (!nameEl) {
      nameEl = document.createElement("span")
      nameEl.className = "shift-edit-name"
      display.appendChild(nameEl)
    }
    let offLabel = ""
    if (isOff) {
      if (holidayType === "requested_off") offLabel = "(希望休)"
      else if (holidayType === "paid_leave") offLabel = "(有休)"
      else offLabel = "(休)"
    }

    nameEl.classList.remove(
      "holiday-in-slot",
      "holiday-admin-off",
      "holiday-requested-off",
      "holiday-paid-leave"
    )

    if (isOff) {
      if (holidayType === "requested_off") {
        nameEl.classList.add("holiday-in-slot", "holiday-requested-off")
      } else if (holidayType === "paid_leave") {
        nameEl.classList.add("holiday-in-slot", "holiday-paid-leave")
      }
    }

    nameEl.textContent = `${nameBase}${offLabel}`

    let timeEl = display.querySelector(".shift-edit-time")
    if (timeText) {
      if (!timeEl) {
        timeEl = document.createElement("span")
        timeEl.className = "shift-edit-time"
        display.appendChild(timeEl)
      }
      timeEl.textContent = timeText
    } else {
      if (timeEl) timeEl.remove()
    }

    this.queueSave(select, { kind, holidayType, staffDayTimeOptionId, shiftMonthTimeOptionId })
  }

  queueSave(select, payload) {
    if (this._saveTimer) clearTimeout(this._saveTimer)
    this._saveTimer = setTimeout(() => this.save(select, payload), 400)
  }

  async save(select, payload) {
    const url = select.dataset.updateUrl
    if (!url) return

    const staffId = select.dataset.staffId
    const date = select.dataset.date

    const kind = payload && payload.kind ? payload.kind : select.value
    const holidayType =
      (payload && payload.holidayType) ? payload.holidayType : null
    const staffDayTimeOptionId =
      (payload && payload.staffDayTimeOptionId) ? payload.staffDayTimeOptionId : null
    const shiftMonthTimeOptionId =
      (payload && payload.shiftMonthTimeOptionId) ? payload.shiftMonthTimeOptionId : null

    const row = select.closest(".shift-edit-row")
    const display = row ? row.querySelector(".shift-edit-display") : null
    if (display) {
      display.classList.remove("is-save-error")
      display.classList.add("is-saving")
    }

    const tokenEl = document.querySelector('meta[name="csrf-token"]')
    const csrfToken = tokenEl ? tokenEl.getAttribute("content") : null

    try {
      const res = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({
          date: date,
          staff_id: staffId,
          kind: kind,
          holiday_type: holidayType,
          staff_day_time_option_id: staffDayTimeOptionId,
          shift_month_time_option_id: shiftMonthTimeOptionId
        })
      })

      const data = await res.json().catch(() => null)

      if (!res.ok || !data || data.ok !== true) {
        if (display) {
          display.classList.add("is-save-error")
          display.title = (data && data.error) ? data.error : "保存に失敗しました"
        }
        return
      }

      if (display) display.title = ""

      // 右サイドバー(stats)を更新
      if (data.stats_html) {
        const box = document.getElementById("draft-sidebar")
        if (box) box.innerHTML = data.stats_html
      }

      if (data.alerts_html_by_date) {
        Object.entries(data.alerts_html_by_date).forEach(([dateStr, html]) => {
          const el = document.getElementById(`alert-cell-${dateStr}`)
          if (el) el.innerHTML = html
        })
      }
    } catch (_e) {
      if (display) {
        display.classList.add("is-save-error")
        display.title = "保存に失敗しました"
      }
    } finally {
      if (display) display.classList.remove("is-saving")
    }
  }
}
