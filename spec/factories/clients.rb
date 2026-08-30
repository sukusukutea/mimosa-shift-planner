FactoryBot.define do
  factory :client do
    user { nil }
    display_name { "MyString" }
    sort_key { "MyString" }
    active { false }
  end
end
