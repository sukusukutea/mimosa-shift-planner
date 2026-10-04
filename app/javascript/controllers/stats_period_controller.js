import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "period"]

  connect() {
    const sidebar = this.element.closest("#draft-sidebar")

    const savedPeriod =
      sidebar?.dataset.selectedStatsPeriod || "month"

    const periodExists =
      Array.from(this.selectTarget.options).some(
        (option) => option.value === savedPeriod
      )

    const selectedPeriod =
      periodExists ? savedPeriod : "month"

    this.selectTarget.value = selectedPeriod

    this.showPeriod(selectedPeriod)
  }

  change() {
    const selectedPeriod = this.selectTarget.value
    const sidebar = this.element.closest("#draft-sidebar")

    if (sidebar) {
      sidebar.dataset.selectedStatsPeriod = selectedPeriod
    }

    this.showPeriod(selectedPeriod)
  }

  showPeriod(key) {
    this.periodTargets.forEach((period) => {
      const isSelected =
        period.dataset.periodKey === key

      period.classList.toggle(
        "d-none",
        !isSelected
      )
    })
  }
}
