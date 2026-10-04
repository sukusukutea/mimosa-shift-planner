import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "stayClient",
    "stayClientName",
    "stayEnd",
    "stayEndSelect"
  ]

  async add(event) {
    const select = event.currentTarget
    const clientId = select.value

    if (!clientId) return

    const url = select.dataset.updateUrl
    const date = select.dataset.date
    const serviceKind = select.dataset.serviceKind

    const tokenEl = document.querySelector('meta[name="csrf-token"]')
    const csrfToken = tokenEl ? tokenEl.getAttribute("content") : null

    select.disabled = true

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({
          client_id: clientId,
          client_service_kind: serviceKind,
          dates: [date],
          return_to: "edit_draft"
        })
      })

      const data = await response.json().catch(() => null)

      if (!response.ok || !data || data.ok !== true) {
        alert("利用者予定の追加に失敗しました。")
        select.value = ""
        return
      }

      this.updateCells(data)
    } catch (_error) {
      alert("利用者予定の追加に失敗しました。")
      select.value = ""
    } finally {
      select.disabled = false
    }
  }

  selectStayClient() {
    if (!this.hasStayClientTarget || !this.hasStayEndTarget) return

    if (this.stayClientTarget.value) {
      const selectedOption =
        this.stayClientTarget.options[this.stayClientTarget.selectedIndex]

      if (this.hasStayClientNameTarget) {
        this.stayClientNameTarget.textContent =
          selectedOption.text.trim()
      }

      this.stayEndTarget.classList.remove("d-none")
    } else {
      if (this.hasStayClientNameTarget) {
        this.stayClientNameTarget.textContent = ""
      }

      this.stayEndTarget.classList.add("d-none")

      if (this.hasStayEndSelectTarget) {
        this.stayEndSelectTarget.value = ""
      }
    }
  }

  async addStay(event) {
    const endSelect = event.currentTarget
    const endDate = endSelect.value

    if (!endDate) return

    if (endDate === "cancel") {
      if (this.hasStayClientTarget) {
        this.stayClientTarget.value = ""
      }

      if (this.hasStayClientNameTarget) {
        this.stayClientNameTarget.textContent = ""
      }

      endSelect.value = ""

      if (this.hasStayEndTarget) {
        this.stayEndTarget.classList.add("d-none")
      }

      return
    }

    if (!this.hasStayClientTarget) return

    const clientId = this.stayClientTarget.value
    const startDate = endSelect.dataset.startDate
    const url = endSelect.dataset.updateUrl

    if (!clientId || !startDate || !url) return

    const dates = this.buildDateRange(startDate, endDate)

    if (dates.length < 2) {
      alert("泊まりは2日以上の期間を選択してください。")
      endSelect.value = ""
      return
    }

    const tokenEl = document.querySelector('meta[name="csrf-token"]')
    const csrfToken = tokenEl ? tokenEl.getAttribute("content") : null

    this.stayClientTarget.disabled = true
    endSelect.disabled = true

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({
          client_id: clientId,
          client_service_kind: "stay",
          dates: dates,
          return_to: "edit_draft"
        })
      })

      const data = await response.json().catch(() => null)

      if (!response.ok || !data || data.ok !== true) {
        alert("泊まり予定の追加に失敗しました。")
        endSelect.value = ""
        return
      }

      this.updateCells(data)
    } catch (_error) {
      alert("泊まり予定の追加に失敗しました。")
      endSelect.value = ""
    } finally {
      if (this.hasStayClientTarget) {
        this.stayClientTarget.disabled = false
      }

      endSelect.disabled = false
    }
  }

  async changeExisting(event) {
    const select = event.currentTarget

    if (select.value !== "delete") return

    const scheduleId = select.dataset.scheduleId
    const scheduleIds = (select.dataset.scheduleIds || "")
      .split(",")
      .filter(Boolean)

    const url = select.dataset.deleteUrl

    if ((!scheduleId && scheduleIds.length === 0) || !url) {
      select.value = "keep"
      return
    }

    const tokenEl = document.querySelector('meta[name="csrf-token"]')
    const csrfToken = tokenEl ? tokenEl.getAttribute("content") : null

    select.disabled = true

    const body =
      scheduleIds.length > 0
        ? { schedule_ids: scheduleIds }
        : { schedule_id: scheduleId }

    try {
      const response = await fetch(url, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify(body)
      })

      const data = await response.json().catch(() => null)

      if (!response.ok || !data || data.ok !== true) {
        alert(data?.error || "利用者予定の削除に失敗しました。")
        select.value = "keep"
        return
      }

      this.updateCells(data)
    } catch (_error) {
      alert("利用者予定の削除に失敗しました。")
      select.value = "keep"
    } finally {
      select.disabled = false
    }
  }

  buildDateRange(startDate, endDate) {
    const dates = []

    const current = new Date(`${startDate}T00:00:00Z`)
    const last = new Date(`${endDate}T00:00:00Z`)

    while (current <= last) {
      dates.push(current.toISOString().slice(0, 10))
      current.setUTCDate(current.getUTCDate() + 1)
    }

    return dates
  }

  updateCells(data) {
    if (data.cells) {
      Object.entries(data.cells).forEach(([date, html]) => {
        const cell = document.getElementById(
          `client-schedule-cell-${date}`
        )

        if (cell && html) {
          cell.innerHTML = html
        }
      })
    } else {
      const cell = document.getElementById(
        `client-schedule-cell-${data.date}`
      )

      if (cell && data.cell_html) {
        cell.innerHTML = data.cell_html
      }
    }

    if (data.night_enabled_by_date) {
      Object.entries(data.night_enabled_by_date).forEach(
        ([date, enabled]) => {
          const nightCell = document.getElementById(
            `night-kind-${date}`
          )

          if (!nightCell) return

          nightCell.classList.toggle("is-night-on", enabled)
          nightCell.classList.toggle("is-disabled", !enabled)
        }
      )
    }
  }
}
