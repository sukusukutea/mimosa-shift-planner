FactoryBot.define do
  factory :client_regular_schedule do
    client { nil }
    service_kind { 1 }
    wday { 1 }
    active { false }
  end
end
