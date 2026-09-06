FactoryBot.define do
  factory :shift_month_client_schedule do
    shift_month { nil }
    client { nil }
    date { "2026-09-06" }
    service_kind { 1 }
    source { 1 }
    position { 1 }
    client_display_name { "MyString" }
    note { "MyText" }
  end
end
