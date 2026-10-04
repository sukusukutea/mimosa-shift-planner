import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "display", "name"]

  change() {
    this.syncFromSelect()
    this.save()
  }

  syncFromSelect() {
    const select = this.selectTarget
    const selectedText = select.options[select.selectedIndex]?.textContent || "夜勤を選択"
    const hasValue = !!select.value

    if (this.hasNameTarget) this.nameTarget.textContent = selectedText
    if (this.hasDisplayTarget) {
      this.displayTarget.classList.toggle("is-selected", hasValue)
    }
  }

  async save() {
    const select = this.selectTarget
    const url = select.dataset.updateUrl
    if (!url) return

    const staffId = parseInt(select.value || "0", 10)
    const date = select.dataset.date
    const nightAction =
      staffId > 0
        ? (select.dataset.nightAction || null)
        : "remove"
    const nightSlot =
      select.dataset.nightSlot !== undefined && select.dataset.nightSlot !== ""
        ? parseInt(select.dataset.nightSlot, 10)
        : null

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
          kind: staffId > 0 ? "night" : "off",
          night_action: nightAction,
          night_slot: nightSlot
        })
      })

      const data = await res.json().catch(() => null)

      if (!res.ok || !data || data.ok !== true) {
        console.error("夜勤保存失敗", data?.error)
        return
      }

      // 右サイドバー(stats)を更新（日勤と同じ）
      if (data.stats_html) {
        const box = document.getElementById("draft-sidebar")

        if (box) {
          const currentSelect =
            box.querySelector('[data-stats-period-target="select"]')

          const selectedPeriod =
            currentSelect ? currentSelect.value : "month"

          box.innerHTML = data.stats_html

          const newSelect =
            box.querySelector('[data-stats-period-target="select"]')

          if (newSelect) {
            const periodExists =
              Array.from(newSelect.options).some(
                (option) => option.value === selectedPeriod
              )

            if (periodExists) {
              newSelect.value = selectedPeriod

              box.querySelectorAll(
                '[data-stats-period-target="period"]'
              ).forEach((period) => {
                const isSelected =
                  period.dataset.periodKey === selectedPeriod

                period.classList.toggle("d-none", !isSelected)
              })
            }
          }
        }
      }

      // アラート行を更新（日勤と同じ）
      if (data.alerts_html_by_date) {
        Object.entries(data.alerts_html_by_date).forEach(([dateStr, html]) => {
          const el = document.getElementById(`alert-cell-${dateStr}`)
          if (el) el.innerHTML = html
        })
      }
      // ★ 夜勤セル（当日＋翌日）を即時差し替え
      if (data.night_slots_html_by_dom_id) {
        Object.entries(data.night_slots_html_by_dom_id).forEach(([domId, html]) => {
          const el = document.getElementById(domId)
          if (el) el.innerHTML = html
        })
      }
      // 日勤枠（3日目など）を差し替え
      if (data.day_slots_html_by_dom_id) {
        Object.entries(data.day_slots_html_by_dom_id).forEach(([domId, html]) => {
          const el = document.getElementById(domId)
          if (el) el.innerHTML = html
        })
      }
    } catch (_e) {
      console.error("夜勤保存失敗")
    }
  }

}
