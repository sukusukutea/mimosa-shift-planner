import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
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

      const cell = document.getElementById(
        `client-schedule-cell-${data.date}`
      )

      if (cell && data.cell_html) {
        cell.innerHTML = data.cell_html
      }
    } catch (_error) {
      alert("利用者予定の追加に失敗しました。")
      select.value = ""
    } finally {
      select.disabled = false
    }
  }

  async changeExisting(event) {
    const select = event.currentTarget

    if (select.value !== "delete") return

    const scheduleId = select.dataset.scheduleId
    const url = select.dataset.deleteUrl

    if (!scheduleId || !url) {
      select.value = "keep"
      return
    }

    const tokenEl = document.querySelector('meta[name="csrf-token"]')
    const csrfToken = tokenEl ? tokenEl.getAttribute("content") : null

    select.disabled = true

    try {
      const response = await fetch(url, {
        method: "DELETE",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({
          schedule_id: scheduleId
        })
      })

      const data = await response.json().catch(() => null)

      if (!response.ok || !data || data.ok !== true) {
        alert(data?.error || "利用者予定の削除に失敗しました。")
        select.value = "keep"
        return
      }

      const cell = document.getElementById(
        `client-schedule-cell-${data.date}`
      )

      if (cell && data.cell_html) {
        cell.innerHTML = data.cell_html
      }
    } catch (_error) {
      alert("利用者予定の削除に失敗しました。")
      select.value = "keep"
    } finally {
      select.disabled = false
    }
  }
}
