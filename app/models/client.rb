class Client < ApplicationRecord
  belongs_to :user
  has_many :client_regular_schedules, dependent: :destroy
  has_many :shift_month_client_schedules, dependent: :destroy

  validates :display_name, presence: true, uniqueness: { scope: :user_id }
  validates :sort_key, presence: true
  validates :sort_key,
            format: {
              with: /\A[ぁ-んー]+\z/,
              message: "はひらがなで入力してください"
            },
            allow_blank: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_key, :display_name, :id) }
end
