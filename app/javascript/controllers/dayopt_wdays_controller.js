import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fieldset", "box"]

  connect() {
    // 初期状態：チェックが1つでもあれば「あり」、なければ「なし」
    const anyChecked = this.boxTargets.some((el) => el.checked)
    this.applyMode(anyChecked ? "some" : "none")
  }

  changeMode(e) {
    this.applyMode(e.target.value)
  }

  applyMode(mode) {
    const isNone = (mode === "none")

    if (isNone) {
        this.boxTargets.forEach((el) => { el.checked = false })
    }

    this.fieldsetTarget.disabled = isNone

    // ★ 追加：グレーアウト用クラス
    this.fieldsetTarget.classList.toggle("wdays-disabled", isNone)
  }
}