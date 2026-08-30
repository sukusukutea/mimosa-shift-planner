class ClientRegularSchedule < ApplicationRecord
  belongs_to :client

  enum :service_kind, {
    day_service: 0,
    visit: 1
  }

  validates :service_kind, presence: true
  validates :wday, presence: true, inclusion: { in: 0..6 }
  validates :wday, uniqueness: { scope: [:client_id, :service_kind] }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:service_kind, :wday, :id) }
end
