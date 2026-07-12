class ShiftDayDesignation < ApplicationRecord
  belongs_to :shift_month
  belongs_to :staff

  enum :shift_kind, { day: 0, early: 1, late: 2, night: 3 }

  validates :date, presence: true
  validates :shift_kind, presence: true
  # day は複数人OKにしたいので「kindのユニーク」は day 以外にだけかける
  validates :shift_kind,
            uniqueness: { scope: [ :shift_month_id, :date ] },
            unless: -> { %w[day late].include?(shift_kind.to_s) }
end
