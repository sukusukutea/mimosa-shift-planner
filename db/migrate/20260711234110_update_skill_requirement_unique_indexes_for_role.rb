class UpdateSkillRequirementUniqueIndexesForRole < ActiveRecord::Migration[8.0]
  def change
    remove_index :shift_month_skill_requirements,
                 column: [ :shift_month_id, :day_of_week, :skill ],
                 if_exists: true

    add_index :shift_month_skill_requirements,
              [ :shift_month_id, :day_of_week, :skill, :role ],
              unique: true,
              name: :idx_shift_month_skill_requirements_unique

    remove_index :shift_day_skill_requirements,
                 column: [ :shift_month_id, :date, :shift_kind, :skill ],
                 if_exists: true

    add_index :shift_day_skill_requirements,
              [ :shift_month_id, :date, :shift_kind, :skill, :role ],
              unique: true,
              name: :idx_shift_day_skill_requirements_unique
  end
end
