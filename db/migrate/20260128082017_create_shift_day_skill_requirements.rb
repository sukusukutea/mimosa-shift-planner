class CreateShiftDaySkillRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_day_skill_requirements do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :shift_kind, null: false
      t.integer :skill, null: false
      t.integer :required_number, null: false, default: 0

      t.timestamps
    end

    add_index :shift_day_skill_requirements,
              [ :shift_month_id, :date, :shift_kind, :skill ],
              unique: true,
              name: "idx_unique_day_skill_req"
  end
end
