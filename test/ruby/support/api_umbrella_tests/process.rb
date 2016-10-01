module ApiUmbrellaTests
  class Process
    EMBEDDED_ROOT = File.join(API_UMBRELLA_SRC_ROOT, "build/work/stage/opt/api-umbrella/embedded")
    CONFIG_PATH = "/tmp/integration_test_suite.yml:/tmp/integration_test_suite_overrides.yml"

    def self.start
      Minitest.after_run do
        ApiUmbrellaTests::Process.stop
      end

      start_time = Time.now
      FileUtils.rm_rf("/tmp/api-umbrella-test")
      FileUtils.mkdir_p("/tmp/api-umbrella-test/var/log")

      Bundler.with_clean_env do
        $config = YAML.load_file(File.join(API_UMBRELLA_SRC_ROOT, "test/config/test.yml"))
        #config["services"] = ["general_db", "log_db", "router"]
        $config["mongodb"]["url"] = "mongodb://127.0.0.1:13001/api_umbrella_test"
        File.write("/tmp/integration_test_suite.yml", YAML.dump($config))
        File.write("/tmp/integration_test_suite_overrides.yml", YAML.dump({ "version" => 0 }))

        #config_path = File.join(API_UMBRELLA_SRC_ROOT, "test/config/test.yml")

        progress = Thread.new do
          print "Waiting for api-umbrella to start..."
          loop do
            print "."
            sleep 2
          end
        end

        # Spin up API Umbrella and the embedded databases as a background
        # process.
        $api_umbrella_process = ChildProcess.build(File.join(API_UMBRELLA_SRC_ROOT, "bin/api-umbrella"), "run")
        $api_umbrella_process.io.inherit!
        $api_umbrella_process.environment["API_UMBRELLA_EMBEDDED_ROOT"] = EMBEDDED_ROOT
        $api_umbrella_process.environment["API_UMBRELLA_CONFIG"] = CONFIG_PATH
        $api_umbrella_process.leader = true
        $api_umbrella_process.start

        # Run the health command to wait for API Umbrella to fully startup.
        health = ChildProcess.build(File.join(API_UMBRELLA_SRC_ROOT, "bin/api-umbrella"), "health", "--wait-for-status", "green", "--wait-timeout", "90")
        health.io.inherit!
        health.environment["API_UMBRELLA_EMBEDDED_ROOT"] = EMBEDDED_ROOT
        health.environment["API_UMBRELLA_CONFIG"] = CONFIG_PATH
        health.start
        health.wait

        progress.exit

        end_time = Time.now
        puts sprintf("(%.2fs)", end_time - start_time)

        # If anything exited unsuccessfully, abort tests.
        if(health.crashed? || $api_umbrella_process.crashed?)
          raise "Did not start api-umbrella process for integration tests"
        end
      end
    rescue Exception => e
      self.stop
      raise e
    end

    def self.stop
      if($api_umbrella_process && $api_umbrella_process.alive?)
        puts "Stopping api-umbrella..."

        begin
          stop = ChildProcess.build(File.join(API_UMBRELLA_SRC_ROOT, "bin/api-umbrella"), "stop")
          stop.io.inherit!
          stop.environment["API_UMBRELLA_EMBEDDED_ROOT"] = EMBEDDED_ROOT
          stop.environment["API_UMBRELLA_CONFIG"] = CONFIG_PATH
          stop.start
          stop.wait
        ensure
          $api_umbrella_process.stop
        end
      end
    end

    def self.reload
      reload = ChildProcess.build(File.join(API_UMBRELLA_SRC_ROOT, "bin/api-umbrella"), "reload")
      reload.io.inherit!
      reload.environment["API_UMBRELLA_EMBEDDED_ROOT"] = EMBEDDED_ROOT
      reload.environment["API_UMBRELLA_CONFIG"] = CONFIG_PATH
      reload.start
      reload.wait
    end

    def self.wait_for_config_version(field, version)
      data = nil
      begin
        Timeout.timeout(10) do
          loop do
            response = Typhoeus.get("http://127.0.0.1:9080/api-umbrella/v1/state?#{rand}")
            data = MultiJson.load(response.body)
            break if(data[field] == version)
            sleep 0.1
          end
        end
      rescue Timeout::Error
        raise Timeout::Error, "API Umbrella configuration changes were not detected. Waiting for version #{version}. Last seen: #{data.inspect}"
      end
    end
  end
end
