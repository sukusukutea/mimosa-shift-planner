class AddUserToShiftMonths < ActiveRecord::Migration[8.0]
  def up
    # 1) user_id カラムを一旦 NULL許可で追加
    add_reference :shift_months, :user, null: true, foreign_key: true

    # 2) 既存データに user_id を埋める
    ShiftMonth.reset_column_information

    ShiftMonth.find_each do |sm|
      next if sm.user_id.present?

      # 同じ organization に属するユーザーのうち、最初の1人を暫定的に紐づけ
      user = User.find_by(organization_id: sm.organization_id)
      sm.update_columns(user_id: user.id) if user
      # ※ user が見つからないケースは今の開発状況だとほぼ無い想定
    end

    # 3) ここまでで全レコードに user_id が入っている前提で、NOT NULL に変更
    change_column_null :shift_months, :user_id, false

    # 4) これまでの「organization + year + month」のユニーク制約を外す
    remove_index :shift_months, column: [ :organization_id, :year, :month ]

    # 5) 新しく「user + year + month」でユニークにする
    add_index :shift_months, [ :user_id, :year, :month ], unique: true
  end

  def down
    # 逆順で戻せるように
    remove_index :shift_months, column: [ :user_id, :year, :month ]
    add_index :shift_months, [ :organization_id, :year, :month ], unique: true

    remove_reference :shift_months, :user, foreign_key: true
  end
end
