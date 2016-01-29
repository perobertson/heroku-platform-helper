require 'spec_helper'

RSpec.describe HerokuHelper::App do
  before do
    @client = double('client')
    expect(PlatformAPI).to receive(:connect_oauth) { @client }

    @logger = double('logger')
    HerokuHelper.logger = @logger
  end

  let(:app) { HerokuHelper::App.new('SECRET_KEY', 'APP_NAME') }

  it 'can retrieve the running version' do
    build = double('build')

    expect(@logger).to receive(:info).with(/APP_NAME.*v1.3.0/)

    expect(@client).to receive(:build).with(no_args) { build }
    expect(build).to receive(:list).with(app.app_name) {
      [
        {
          'source_blob' => {
            'version' => "v1.3.0"
          }
        }
      ]
    }
    expect(app.version).to eq 'v1.3.0'
  end

  it 'can restart all the dynos' do
    dyno = double('dyno')

    expect(@logger).to receive(:info).with(/APP_NAME.*restarted/)

    expect(@client).to receive(:dyno).with(no_args) { dyno }
    expect(dyno).to receive(:restart_all).with(app.app_name)
    app.restart
  end

  it 'can scale the worker' do
    formation = double('formation')

    expect(@logger).to receive(:info).with('Scaling worker to 1')

    expect(@client).to receive(:formation).with(no_args) { formation }
    expect(formation).to receive(:list).with(app.app_name) {
      [
        {
          'size' => 'standard-1X',
          'type' => 'worker',
          'quantity' => 0
        },
        {
          'size' => 'standard-1X',
          'type' => 'clock',
          'quantity' => 0
        }
      ]
    }
    expect(formation).to receive(:batch_update).with(app.app_name, hash_including(
      updates: [process: 'worker', quantity: 1, size: 'standard-1X']
    ))

    app.scale worker: 1
  end

  it 'can scale the clock' do
    formation = double('formation')

    expect(@logger).to receive(:info).with('Scaling clock to 1')

    expect(@client).to receive(:formation).with(no_args) { formation }
    expect(formation).to receive(:list).with(app.app_name) {
      [
        {
          'size' => 'standard-1X',
          'type' => 'worker',
          'quantity' => 0
        },
        {
          'size' => 'standard-1X',
          'type' => 'clock',
          'quantity' => 0
        }
      ]
    }
    expect(formation).to receive(:batch_update).with(app.app_name, hash_including(
      updates: [process: 'clock', quantity: 1, size: 'standard-1X']
    ))

    app.scale clock: 1
  end

  it 'can scale both the worker and the clock' do
    formation = double('formation')

    expect(@logger).to receive(:info).with('Scaling worker to 1')
    expect(@logger).to receive(:info).with('Scaling clock to 1')

    expect(@client).to receive(:formation).with(no_args) { formation }
    expect(formation).to receive(:list).with(app.app_name) {
      [
        {
          'size' => 'standard-1X',
          'type' => 'worker',
          'quantity' => 0
        },
        {
          'size' => 'standard-1X',
          'type' => 'clock',
          'quantity' => 0
        }
      ]
    }
    expect(formation).to receive(:batch_update).with(app.app_name, hash_including(
      updates: [
        { process: 'worker', quantity: 1, size: 'standard-1X' },
        { process: 'clock', quantity: 1, size: 'standard-1X' }
      ]
    ))

    app.scale worker: 1, clock: 1
  end

  it 'must log a warning when trying to scale to the current scale' do
    formation = double('formation')

    expect(@logger).to receive(:warn).with('Worker is already scaled to 1')
    expect(@logger).to receive(:warn).with('Clock is already scaled to 1')
    expect(@logger).to receive(:warn).with('Nothing to scale. Please check your configurations')

    expect(@client).to receive(:formation).with(no_args) { formation }
    expect(formation).to receive(:list).with(app.app_name) {
      [
        {
          'size' => 'standard-1X',
          'type' => 'worker',
          'quantity' => 1
        },
        {
          'size' => 'standard-1X',
          'type' => 'clock',
          'quantity' => 1
        }
      ]
    }

    app.scale worker: 1, clock: 1
  end

  it 'can run migrations' do
    dyno = double('dyno')

    expect(@logger).to receive(:info).with(/[Rr]unning migrations/)

    expect(@client).to receive(:dyno).with(no_args) { dyno }
    expect(dyno).to receive(:create).with(app.app_name, kind_of(Hash)) {
      {
        "attach_url" => "rendezvous://rendezvous.runtime.heroku.com:5000/{rendezvous-id}"
      }
    }
    expect(Rendezvous).to receive(:start).with(kind_of(Hash))
    app.migrate
  end

  it 'will log errors when connecting to log output fails for migrations' do
    dyno = double('dyno')

    expect(@logger).to receive(:info).with(/[Rr]unning migrations/)
    expect(@logger).to receive(:error).with(/Error capturing output for dyno/)

    expect(@client).to receive(:dyno).with(no_args) { dyno }
    expect(dyno).to receive(:create).with(app.app_name, kind_of(Hash))
    app.migrate
  end

  it 'can enable maintenance mode' do
    heroku_app = double('heroku_app')

    expect(@logger).to receive(:info).with(/[Ee]nabling maintenance/)

    expect(@client).to receive(:app).with(no_args) { heroku_app }
    expect(heroku_app).to receive(:update).with(app.app_name, hash_including(maintenance: true))
    app.maintenance(true)
  end

  it 'can disable maintenance mode' do
    heroku_app = double('heroku_app')

    expect(@logger).to receive(:info).with(/[Dd]isabling maintenance/)

    expect(@client).to receive(:app).with(no_args) { heroku_app }
    expect(heroku_app).to receive(:update).with(app.app_name, hash_including(maintenance: false))
    app.maintenance(false)
  end

  it 'can deploy the app' do
    app.define_singleton_method 'system' do |*_args|
      # TODO: find a better way to manage git
      # this just prevents the system calls from actually being run
      true
    end

    heroku_app = double('heroku_app')

    expect(@logger).to receive(:info).with(/[Dd]eployed.*APP_NAME/)

    expect(@client).to receive(:app).with(no_args) { heroku_app }
    expect(heroku_app).to receive(:info).with(app.app_name) {
      {
        'git_url' => 'git@heroku.com:example.git'
      }
    }
    expect(app).to receive(:scale).twice
    expect(app).to receive(:migrate)

    app.deploy branch: 'HEAD'
  end
end
