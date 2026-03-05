import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="flash"
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, 5000) //3秒後に消える
  }

  dismiss() {
    this.element.classList.remove("show")
    this.element.classList.add("fade")

    setTimeout(() => {
      this.element.remove()
    }, 200) //Bootstrapのfade時間に合わせる
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
