class AddRoleAndVisitToSkillRequirements < ActiveRecord::Migration[8.0]
  def change
    add_column :base_skill_requirements, :role, :integer, null: false, default: 2
    add_column :shift_month_skill_requirements, :role, :integer, null: false, default: 2
    add_column :shift_day_skill_requirements, :role, :integer, null: false, default: 2
  end
end
