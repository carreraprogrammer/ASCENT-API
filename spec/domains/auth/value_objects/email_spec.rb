require 'rails_helper'

RSpec.describe Auth::ValueObjects::Email do
  it 'accepts valid email' do
    expect { described_class.new('user@example.com') }.not_to raise_error
  end
  it 'normalizes to lowercase' do
    expect(described_class.new('USER@EXAMPLE.COM').value).to eq('user@example.com')
  end
  it 'raises InvalidEmail for missing @' do
    expect { described_class.new('notanemail') }.to raise_error(Auth::Errors::InvalidEmail)
  end
  it 'raises InvalidEmail for empty string' do
    expect { described_class.new('') }.to raise_error(Auth::Errors::InvalidEmail)
  end
end
