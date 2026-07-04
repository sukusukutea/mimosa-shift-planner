import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { collapsed: Boolean }

  connect() {
    this.collapsedValue = localStorage.getItem("sidebar-left-collapsed") === "true"
    this.apply()
  }

  toggle() {
    this.collapsedValue = !this.collapsedValue
    localStorage.setItem("sidebar-left-collapsed", this.collapsedValue ? "true" : "false")
    this.apply()
  }

  apply() {
    document.body.classList.toggle("sidebar-left-collapsed", this.collapsedValue)
  }
}
