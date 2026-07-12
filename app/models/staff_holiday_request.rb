class StaffHolidayRequest < ApplicationRecord
  belongs_to :shift_month
  belongs_to :staff

  enum :holiday_type, {
    admin_off: 0,
    requested_off: 1,
    paid_leave: 2
  }

  validates :date, presence: true
  validates :staff_id, uniqueness: { scope: [ :shift_month_id, :date ] }
end
