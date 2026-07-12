class CreateBaseSkillRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :base_skill_requirements do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :day_of_week
      t.integer :skill
      t.integer :required_number, null: false, default: 0

      t.timestamps
    end

    add_index :base_skill_requirements,
              [ :user_id, :day_of_week, :skill ],
              unique: true,
              name: :idx_base_skill_requirements_unique
  end
end
