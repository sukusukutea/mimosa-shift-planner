import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"
import { Japanese } from "flatpickr/dist/l10n/ja.js"

export default class extends Controller {
  static targets = ["input", "hiddenDates", "summary"]

  connect() {
    if (!this.hasInputTarget) return

    this.selectionMode = this.inputTarget.dataset.selectionMode || "multiple"

    const presetDates = this.hiddenDatesTargets.map((input) => input.value)

    try {
      this.picker = flatpickr(this.inputTarget, {
        mode: this.selectionMode,
        inline: true,
        dateFormat: "Y-m-d",
        defaultDate: presetDates,
        minDate: this.inputTarget.dataset.minDate,
        maxDate: this.inputTarget.dataset.maxDate,
        locale: {
          ...Japanese,
          firstDayOfWeek: 1
        },
        clickOpens: true,
        allowInput: false,
        onChange: this.handleChange.bind(this)
      })

      this.renderSummary(presetDates)
    } catch (e) {
      console.error(e)
    }
  }

  disconnect() {
    if (this.picker) {
      this.picker.destroy()
      this.picker = null
    }
  }

  open(event) {
    if (!this.picker) return

    event.preventDefault()
    this.picker.open()
  }

  handleChange(selectedDates, _dateStr, instance) {
    const dates =
      this.selectionMode === "range"
        ? this.datesInRange(selectedDates, instance)
        : selectedDates.map((date) => instance.formatDate(date, "Y-m-d"))

    this.syncHiddenInputs(dates)
    this.renderSummary(dates)
  }

  datesInRange(selectedDates, instance) {
    if (selectedDates.length === 0) return []

    if (selectedDates.length === 1) {
      return [instance.formatDate(selectedDates[0], "Y-m-d")]
    }

    const startDate = new Date(selectedDates[0])
    const endDate = new Date(selectedDates[1])

    if (endDate < startDate) {
      return []
    }

    const dates = []
    const currentDate = new Date(startDate)

    while (currentDate <= endDate) {
      dates.push(instance.formatDate(currentDate, "Y-m-d"))
      currentDate.setDate(currentDate.getDate() + 1)
    }

    return dates
  }

  syncHiddenInputs(dates) {
    this.hiddenDatesTargets.forEach((el) => el.remove())

    dates.forEach((date) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "dates[]"
      input.value = date
      input.dataset.holidayMultiSelectTarget = "hiddenDates"
      this.element.appendChild(input)
    })
  }

  renderSummary(dates) {
    if (!this.hasSummaryTarget) return

    if (dates.length === 0) {
      this.summaryTarget.textContent = "未選択"
      return
    }

    if (this.selectionMode === "range" && dates.length >= 2) {
      this.summaryTarget.textContent = `${this.formatShortDate(dates[0])}〜${this.formatShortDate(dates[dates.length - 1])}`
      return
    }

    this.summaryTarget.textContent = dates
      .map((date) => this.formatShortDate(date))
      .join("、")
  }

  formatShortDate(date) {
    const parts = date.split("-")
    const month = Number(parts[1])
    const day = Number(parts[2])

    return `${month}/${day}`
  }
}
