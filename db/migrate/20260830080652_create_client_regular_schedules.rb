class CreateClientRegularSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :client_regular_schedules do |t|
      t.references :client, null: false, foreign_key: true
      t.integer :service_kind, null: false
      t.integer :wday, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :client_regular_schedules,
              [:client_id, :service_kind, :wday],
              unique: true,
              name: "index_client_regular_schedules_on_client_kind_wday"
  end
end
