class ShiftMonthClientSchedule < ApplicationRecord
  belongs_to :shift_month
  belongs_to :client

  enum :service_kind, {
    day_service: 0,
    stay: 1,
    visit: 2
  }

  enum :source, {
    regular: 0,
    manual: 1
  }

  validates :date, presence: true
  validates :service_kind, presence: true
  validates :source, presence: true
  validates :client_display_name, presence: true
  validates :client_id,
            uniqueness: {
              scope: [:shift_month_id, :date, :service_kind]
            }

  scope :ordered, -> { order(:date, :service_kind, :client_display_name, :id) }
end
