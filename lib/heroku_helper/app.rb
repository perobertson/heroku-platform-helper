require 'logger'
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

      # Fetch whats currently deployed
      system "[ \"$(git remote | grep -e ^#{remote})\" != '' ] && git remote rm #{remote}"
      unless system "git remote add #{remote} #{git_url}"
        fail "Could not add #{remote} remote #{git_url}"
      end
      unless system "git fetch #{remote} master"
        fail "Could not fetch master from #{remote}"
      end

      scale worker: 0, clock: 0
      maintenance(true) if enable_maintenance

      unless system "git push #{remote} #{branch}:master"
        fail "Failed to push branch(#{branch}) to remote(#{remote})"
      end

      migrate
      maintenance(false) if enable_maintenance
      scale worker: worker, clock: clock
      HerokuHelper.logger.info "Deployed #{@app_name}"
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
