class CreateShiftMonthSkillRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_month_skill_requirements do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.integer :day_of_week
      t.integer :skill
      t.integer :required_number, null: false, default: 0

      t.timestamps
    end

    add_index :shift_month_skill_requirements,
              [ :shift_month_id, :day_of_week, :skill ],
              unique: true,
              name: :idx_shift_month_skill_requirements_unique
  end
end
