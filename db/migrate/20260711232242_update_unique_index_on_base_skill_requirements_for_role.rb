class UpdateUniqueIndexOnBaseSkillRequirementsForRole < ActiveRecord::Migration[8.0]
  def change
    remove_index :base_skill_requirements, name: :idx_base_skill_requirements_unique

    add_index :base_skill_requirements,
              [ :user_id, :day_of_week, :skill, :role ],
              unique: true,
              name: :idx_base_skill_requirements_unique
  end
end
