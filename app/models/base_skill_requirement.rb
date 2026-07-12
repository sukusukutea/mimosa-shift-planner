class BaseSkillRequirement < ApplicationRecord
  belongs_to :user

  enum :skill, { drive: 0, cook: 1, visit: 2 }
  enum :role, { nurse: 0, care: 1, any: 2 }

  validates :day_of_week, inclusion: { in: 0..6 }
  validates :required_number, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
