class Client < ApplicationRecord
  belongs_to :user
  has_many :client_regular_schedules, dependent: :destroy

  validates :display_name, presence: true, uniqueness: { scope: :user_id }
  validates :sort_key, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_key, :display_name, :id) }
end
