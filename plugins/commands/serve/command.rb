$LOAD_PATH << Vagrant.source_root.join("lib/vagrant/protobufs").to_s
$LOAD_PATH << Vagrant.source_root.join("lib/vagrant/protobufs/proto").to_s
$LOAD_PATH << Vagrant.source_root.join("lib/vagrant/protobufs/proto/vagrant_plugin_sdk").to_s

require 'vagrant/protobufs/proto/vagrant_server/server_pb'
require 'vagrant/protobufs/proto/vagrant_server/server_services_pb'
require 'vagrant/protobufs/proto/ruby_vagrant/ruby-server_pb'
require 'vagrant/protobufs/proto/ruby_vagrant/ruby-server_services_pb'
require 'vagrant/protobufs/proto/vagrant_plugin_sdk/plugin_pb'
require 'vagrant/protobufs/proto/vagrant_plugin_sdk/plugin_services_pb'
require 'vagrant/protobufs/proto/plugin/grpc_broker_pb'
require 'vagrant/protobufs/proto/plugin/grpc_broker_services_pb'

require "optparse"
require 'grpc'
require 'grpc/health/checker'
require 'grpc/health/v1/health_services_pb'

module VagrantPlugins
  module CommandServe

    autoload :Broker, Vagrant.source_root.join("plugins/commands/serve/broker").to_s
    autoload :Client, Vagrant.source_root.join("plugins/commands/serve/client").to_s
    autoload :Service, Vagrant.source_root.join("plugins/commands/serve/service").to_s

    class Command < Vagrant.plugin("2", :command)

      DEFAULT_PORT = 10001

      def self.synopsis
        "start Vagrant server"
      end

      def execute
        options = {port: DEFAULT_PORT}

        opts = OptionParser.new do |o|
          o.banner = "Usage: vagrant serve"
          o.separator ""
          o.separator "Options:"
          o.separator ""

          o.on("--port PORT", "Port to start the GRPC server on, defaults to 10001") do |port|
            options[:port] = port
          end
        end

        # Parse the options
        argv = parse_options(opts)
        return if !argv
        serve(options[:port])
      end

      private

      def serve(port=DEFAULT_PORT)
        # Set vagrant in server mode
        Vagrant.enable_server_mode!

        s = GRPC::RpcServer.new
        # Listen on port 10001 on all interfaces. Update for production use.
        s.add_http2_port("[::]:#{port}", :this_port_is_insecure)
        health_checker = Grpc::Health::Checker.new

        [Service::InternalService, Service::ProviderService,
          Service::HostService, Service::CommandService, Broker::Streamer].each do |service_klass|
          s.handle(service_klass.new)
          health_checker.add_status(service_klass,
            Grpc::Health::V1::HealthCheckResponse::ServingStatus::SERVING)
        end

        s.handle(health_checker)

        STDOUT.puts "1|1|tcp|127.0.0.1:#{port}|grpc"
        STDOUT.flush
        s.run_till_terminated_or_interrupted([1, 'int', 'SIGQUIT', 'SIGINT'])
      end
    end
  end
end