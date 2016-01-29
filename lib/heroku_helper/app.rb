require 'logger'
require 'git'
require 'platform-api'
require 'rendezvous'

module HerokuHelper
  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new(STDOUT).tap do |log|
        log.progname = self.name
      end
    end
  end

  class App
    attr_reader :app_name

    def initialize(api_key, app_name)
      @api_key = api_key
      @app_name = app_name
    end

    def deploy(branch:, worker: nil, clock: nil, enable_maintenance: false)
      remote = @app_name
      heroku = PlatformAPI.connect_oauth @api_key

      git_url = heroku.app.info(@app_name)['git_url']
      fail 'Cannot determine git url' unless git_url

      # Set up git to deploy
      begin
        git = Git.open('.', log: HerokuHelper.logger)
        remotes = git.remotes.map &:name
        if remotes.include? remote
          HerokuHelper.logger.info "Resetting remote: #{remote}"
          git.remove_remote remote
        end

        git.add_remote remote, git_url, fetch: true, track: 'master'
      rescue => e
        HerokuHelper.logger.error "Could not set up git correctly. Error: #{e}"
        return false
      end

      scale worker: 0, clock: 0
      maintenance(true) if enable_maintenance

      git.push remote, "#{branch}:master"

      migrate
      maintenance(false) if enable_maintenance
      scale worker: worker, clock: clock
      HerokuHelper.logger.info "Deployed #{@app_name}"
      true
    rescue => e
      HerokuHelper.logger.error "FAILED TO DEPLOY! Your app is in a bad state and needs to be fixed manually. Error: #{e}"
    end

    def maintenance(enabled)
      heroku = PlatformAPI.connect_oauth @api_key
      if enabled
        HerokuHelper.logger.info "Enabling maintenance for #{@app_name}"
      else
        HerokuHelper.logger.info "Disabling maintenance for #{@app_name}"
      end
      heroku.app.update(@app_name, maintenance: enabled)
    end

    def migrate
      heroku = PlatformAPI.connect_oauth @api_key
      payload = {
        attach: true,
        command: 'rake db:migrate'
      }
      response = heroku.dyno.create(@app_name, payload)

      begin
        HerokuHelper.logger.info 'Running migrations'
        # set an activity timeout so it doesn't block forever
        Rendezvous.start(url: response['attach_url'], activity_timeout: 600)
      rescue => e
        HerokuHelper.logger.error("Error capturing output for dyno\n#{e.message}")
      end
    end

    def scale(worker: nil, clock: nil)
      heroku = PlatformAPI.connect_oauth @api_key

      payload = {
        updates: []
      }

      heroku_formation = heroku.formation

      formations = heroku_formation.list(@app_name)
      formations.each do |formation|
        size = formation['size']
        if !worker.nil? && formation['type'] == 'worker'
          if formation['quantity'] != worker
            payload[:updates] << {
              process: 'worker',
              quantity: worker,
              size: size
            }
            HerokuHelper.logger.info "Scaling worker to #{worker}"
          else
            HerokuHelper.logger.warn "Worker is already scaled to #{worker}"
          end
        elsif !clock.nil? && formation['type'] == 'clock'
          if formation['quantity'] != clock
            payload[:updates] << {
              process: 'clock',
              quantity: clock,
              size: size
            }
            HerokuHelper.logger.info "Scaling clock to #{clock}"
          else
            HerokuHelper.logger.warn "Clock is already scaled to #{clock}"
          end
        end
      end

      if payload[:updates].empty?
        HerokuHelper.logger.warn 'Nothing to scale. Please check your configurations'
      else
        if payload[:updates].map { |u| u[:size] }.uniq.include? 'Free'
          HerokuHelper.logger.warn 'You can only run 2 dynos on the free tier'
          updates = payload[:updates].sort { |a, b| a[:quantity] <=> b[:quantity] }
          updates.each do |update|
            type = update[:process]
            quantity = update[:quantity]
            heroku_formation.update(@app_name, type, quantity: quantity)
          end
        else
          heroku_formation.batch_update(@app_name, payload)
        end
      end
    end

    def restart
      heroku = PlatformAPI.connect_oauth @api_key
      heroku.dyno.restart_all @app_name
      HerokuHelper.logger.info "#{app_name} restarted"
    end

    def version
      heroku = PlatformAPI.connect_oauth @api_key
      build = heroku.build.list(@app_name).last
      build['source_blob']['version'].tap do |version|
        HerokuHelper.logger.info "#{@app_name}::version #{version}"
      end
    end
  end
end
