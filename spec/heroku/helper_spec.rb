require 'spec_helper'

RSpec.describe HerokuHelper do
  after do
    HerokuHelper.logger = nil
  end

  it 'has a version number' do
    expect(HerokuHelper::VERSION).not_to be nil
  end

  it 'can set a logger' do
    logger = HerokuHelper.logger
    expect(logger).not_to be nil

    HerokuHelper.logger = Logger.new(STDOUT)
    expect(HerokuHelper.logger).to_not be logger
  end

  it 'initializes the log level from the environment' do
    initial = ENV['LOG_LEVEL']

    ENV['LOG_LEVEL'] = nil
    logger = HerokuHelper.logger
    expect(logger.level).to be Logger::DEBUG

    ENV['LOG_LEVEL'] = 'info'
    HerokuHelper.logger = nil
    logger = HerokuHelper.logger
    expect(logger.level).to be Logger::INFO

    ENV['LOG_LEVEL'] = initial
  end
end
