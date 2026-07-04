import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"
import { Japanese } from "flatpickr/dist/l10n/ja.js"

export default class extends Controller {
  static targets = ["input", "hiddenDates", "summary"]

  connect() {
    if (!this.hasInputTarget) return

    const presetDates = this.hiddenDatesTargets.map((input) => input.value)

    try {
        this.picker = flatpickr(this.inputTarget, {
          mode: "multiple",
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

  handleChange(_selectedDates, _dateStr, instance) {
    const dates = instance.selectedDates.map((d) => instance.formatDate(d, "Y-m-d"))
    this.syncHiddenInputs(dates)
    this.renderSummary(dates)
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

    this.summaryTarget.textContent = dates
      .map((date) => {
        const [_, m, d] = date.split("-")
        return `${Number(m)}/${Number(d)}`
      })
      .join("、")
  }
}
