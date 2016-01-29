require 'spec_helper'

RSpec.describe HerokuHelper do
  it 'has a version number' do
    expect(HerokuHelper::VERSION).not_to be nil
  end

  it 'can set a logger' do
    logger = HerokuHelper.logger
    expect(logger).not_to be nil

    HerokuHelper.logger = Logger.new(STDOUT)
    expect(HerokuHelper.logger).to_not be logger
  end
end
