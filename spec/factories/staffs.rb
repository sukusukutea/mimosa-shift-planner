FactoryBot.define do
  factory :staff do
    association :user
    association :occupation

    last_name { "山田" }
    first_name { "花子" }
    last_name_kana { "やまだ" }
    first_name_kana { "はなこ" }

    can_day   { true }
    can_early { false }
    can_late  { false }
    can_night { false }

    can_visit { false }
    can_drive { false }
    can_cook  { false }

    workday_constraint { :free }
    assignment_policy  { :candidate }
    active { true }
    weekly_workdays { nil }
  end
end
