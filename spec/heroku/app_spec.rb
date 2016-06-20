require 'spec_helper'

RSpec.describe HerokuHelper::App do
  before do
    @client = double('client')
    expect(PlatformAPI).to receive(:connect_oauth) { @client }

    @logger = double('logger')
    HerokuHelper.logger = @logger
  end

  after do
    HerokuHelper.logger = nil
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
        'attach_url' => 'rendezvous://rendezvous.runtime.heroku.com:5000/{rendezvous-id}'
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
    heroku_app = double('heroku_app')
    git = double('git')

    expect(@logger).to receive(:info).with(/[Hh]eroku repo/)
    expect(@logger).to receive(:info).with(/[Dd]eployed.*APP_NAME/)

    expect(Git).to receive(:open).with('.', hash_including(log: @logger)) { git }
    expect(git).to receive(:config).with(/ssh/, /https/)
    expect(git).to receive(:remotes) { [] }
    expect(git).to receive(:add_remote).with(app.app_name, 'git@heroku.com:example.git', hash_including(fetch: true, track: 'master'))
    expect(git).to receive(:push).with(app.app_name, 'HEAD:master')

    expect(@client).to receive(:app).with(no_args) { heroku_app }
    expect(heroku_app).to receive(:info).with(app.app_name) {
      {
        'git_url' => 'git@heroku.com:example.git'
      }
    }
    expect(app).to receive(:scale).twice
    expect(app).to receive(:migrate)
    expect(app).to_not receive(:maintenance)

    expect(app.deploy(branch: 'HEAD')).to be_truthy
  end

  it 'logs an error when it cannot fetch the remote during deploy' do
    heroku_app = double('heroku_app')
    git = double('git')

    expect(@logger).to receive(:info).with(/[Hh]eroku repo/)
    expect(@logger).to receive(:error).with(/Could not set up git/)

    expect(Git).to receive(:open).with('.', hash_including(log: @logger)) { git }
    expect(git).to receive(:config).with(/ssh/, /https/)
    expect(git).to receive(:remotes) { [] }
    expect(git).to receive(:add_remote).and_raise

    expect(@client).to receive(:app).with(no_args) { heroku_app }
    expect(heroku_app).to receive(:info).with(app.app_name) {
      {
        'git_url' => 'git@heroku.com:example.git'
      }
    }
    expect(app).to_not receive(:scale)
    expect(app).to_not receive(:migrate)
    expect(app).to_not receive(:maintenance)

    expect(app.deploy(branch: 'HEAD')).to be_falsy
  end

  it 'logs an error when an error occurs during deploy' do
    heroku_app = double('heroku_app')
    git = double('git')

    expect(@logger).to receive(:info).with(/[Hh]eroku repo/)
    expect(@logger).to receive(:error).with(/FAILED TO DEPLOY! Your app is in a bad state and needs to be fixed manually./)

    expect(Git).to receive(:open).with('.', hash_including(log: @logger)) { git }
    expect(git).to receive(:config).with(/ssh/, /https/)
    expect(git).to receive(:remotes) { [] }
    expect(git).to receive(:add_remote)
    expect(git).to receive(:push).and_raise

    expect(@client).to receive(:app).with(no_args) { heroku_app }
    expect(heroku_app).to receive(:info).with(app.app_name) {
      {
        'git_url' => 'git@heroku.com:example.git'
      }
    }
    expect(app).to receive(:scale).once
    expect(app).to_not receive(:migrate)
    expect(app).to_not receive(:maintenance)

    expect(app.deploy(branch: 'HEAD')).to be_falsy
  end
end
