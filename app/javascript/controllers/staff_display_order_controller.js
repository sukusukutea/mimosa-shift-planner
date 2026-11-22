import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "list", "saveButton", "message"]

  static values = {
    updateUrl: String
  }

  connect() {
    this.draggedItem = null
  }

  dragStart(event) {
    this.draggedItem = event.currentTarget
    event.currentTarget.classList.add("opacity-50")

    event.dataTransfer.effectAllowed = "move"
  }

  dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
    this.draggedItem = null
  }

  dragOver(event) {
    event.preventDefault()

    const target = event.currentTarget

    if (!this.draggedItem || target === this.draggedItem) return

    const list = target.parentElement

    // 看護⇔介護の移動は禁止
    if (this.draggedItem.parentElement !== list) return

    const rect = target.getBoundingClientRect()
    const insertAfter =
      event.clientY > rect.top + rect.height / 2

    if (insertAfter) {
      target.after(this.draggedItem)
    } else {
      target.before(this.draggedItem)
    }

    this.saveButtonTarget.disabled = false

    if (this.hasMessageTarget) {
      this.messageTarget.textContent = ""
    }
  }

  async save() {
    const nurseList =
      this.listTargets.find(
        (list) => list.dataset.group === "nurse"
      )

    const careList =
      this.listTargets.find(
        (list) => list.dataset.group === "care"
      )

    if (!nurseList || !careList) return

    const nurseStaffIds =
      Array.from(
        nurseList.querySelectorAll("[data-staff-id]")
      ).map((item) => parseInt(item.dataset.staffId, 10))

    const careStaffIds =
      Array.from(
        careList.querySelectorAll("[data-staff-id]")
      ).map((item) => parseInt(item.dataset.staffId, 10))

    const tokenEl =
      document.querySelector('meta[name="csrf-token"]')

    const csrfToken =
      tokenEl ? tokenEl.getAttribute("content") : null

    this.saveButtonTarget.disabled = true
    this.saveButtonTarget.textContent = "保存中..."

    try {
      const response = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken
            ? { "X-CSRF-Token": csrfToken }
            : {})
        },
        body: JSON.stringify({
          nurse_staff_ids: nurseStaffIds,
          care_staff_ids: careStaffIds
        })
      })

      const data =
        await response.json().catch(() => null)

      if (!response.ok || !data || data.ok !== true) {
        throw new Error(
          data?.error || "表示順の保存に失敗しました。"
        )
      }

      if (this.hasMessageTarget) {
        this.messageTarget.textContent = "保存しました。"
      }
    } catch (error) {
      alert(error.message || "表示順の保存に失敗しました。")

      this.saveButtonTarget.disabled = false
    } finally {
      this.saveButtonTarget.textContent = "保存"
    }
  }
}
