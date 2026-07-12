class ShiftMonthTimeOption < ApplicationRecord
  belongs_to :shift_month

  enum :shift_kind, {
    early: 0,
    late: 1
  }

  validates :shift_kind, presence: true
  validates :time_text, presence: true
  validates :position, presence: true
  validates :is_default, inclusion: { in: [ true, false ] }

  validates :time_text,
            format: {
              with: /\A[0-9\-:\/ ]+\z/,
              message: "は半角数字と - : / とスペースのみ使えます"
            }

  validate :only_one_default_per_shift_kind

  private

  def only_one_default_per_shift_kind
    return unless is_default?

    scope = shift_month.shift_month_time_options.where(shift_kind: shift_kind, is_default: true)
    scope = scope.where.not(id: id) if persisted?

    if scope.exists?
      errors.add(:is_default, "は同じ勤務種別で1つだけにしてください")
    end
  end
end
