require 'erb'
require 'fileutils'
require 'open3'

require_relative "generator_helpers"

module NginxStage
  # Base class for objects that add new sub-commands to NginxStage. {Generator}
  # is basically a class with helper methods and the ability to invoke all
  # callback methods in a sequence.
  class Generator
    extend GeneratorHelpers

    # Adds a new hook method that is invoked in the order it is defined
    # @param name [Symbol] unique key defining callback method
    # @yield The body of the generator's callback
    # @return [void]
    def self.add_hook(name, &block)
      self.hooks[name] = block
    end

    # Removes a hook method from the callback chain
    # @param name [Symbol] unique key defining callback method
    # @return [void]
    def self.rem_hook(name)
      self.hooks.delete(name)
    end

    # Returns a hash of callback methods in the order they will be invoked
    # @return [Hash] the callback methods
    def self.hooks
      @hooks ||= from_superclass(:hooks, {})
    end

    # Adds a new option expected from CLI and treats it as an attribute
    # @param name [Symbol] unique key defining option
    # @yield The body of the option's callback which should return a hash
    # @return [void]
    def self.add_option(name, &block)
      attr_reader name
      self._options[name] = block
    end

    # Removes an option expected from the CLI and removes attribute method
    # @param name [Symbol] unique key defining option
    # @return [void]
    def self.rem_option(name)
      undef name
      self._options.delete(name)
    end

    # Returns a hash of options with callbacks that return a hash of their
    # attributes
    # @return [Hash] a hash of options with the corresponding callback
    def self._options
      @options ||= from_superclass(:_options, {})
    end

    # Returns a hash of options that point to a hash of their attributes
    # @return [Hash] a hash of options with the corresponding hash of attributes
    def self.options
      Hash[self._options.map { |k,v| [k, v.call] }]
    end

    # Returns the description of generator
    # @return [String] description of generator
    def self.desc(desc = nil)
      @desc ||= desc
    end

    # Returns the footer description of generator
    # @return [String] footer description of generator
    def self.footer(footer = nil)
      @footer ||= footer
    end

    # @param opts [Hash] various options for controlling the behavior of the generator
    def initialize(opts = {})
      self.class.options.each do |k,v|
        value = opts.fetch(k) do
          raise MissingOption, "missing option: #{k}" if v[:required]
          v[:default]
        end
        value = v[:before_init].call(value) if v[:before_init]
        instance_variable_set("@#{k}", value)
      end
    end

    # Invokes all the callbacks in the order they are defined in the {hooks}
    # hash
    # @return [void]
    def invoke
      self.class.hooks.each {|k,v| self.instance_eval(&v)}
    end

    # Gets an ERB template at the relative source, executes it and makes a copy
    # at the relative destination
    # @param source [String] the relative path to the source file
    # @param destination [String] the relative path to the destination file
    # @return [void]
    def template(source, destination)
      data = File.read File.join(NginxStage.template_root, source)
      create_file destination, render(data)
    end

    # Create a new file at the destination path with the given data
    # @param destination [String] the relative path to the destination file
    # @param data [String] the given data
    # @return [void]
    def create_file(destination, data = "", mode: 0644)
      empty_directory File.dirname(destination)
      File.open(destination, "wb", mode) { |f| f.write data }
    end

    # Create an empty directory if it doesn't already exist
    # @param destination [String] the directory path
    # @param mode [Integer] the mode to set the directory as
    # @return [void]
    def empty_directory(destination, mode: 0755)
      FileUtils.mkdir_p destination, mode: mode
    end

    # Create a new namespace
    # @param user [User] A user object
    # @return [Integer] PID of the process leader in the new namespace
    def create_namespace(uid)
      this_dir = File.dirname(__FILE__)
      custom_ns_dir = File.expand_path("#{this_dir}/../../../custom_scripts/ns")
      IO.popen(
        NginxStage.nginx_env(user: user),
        [
        "#{custom_ns_dir}/create_ns.sh",
        "#{NginxStage.pun_jail_dir}",
        "#{user.name}",
        "#{user.uid}"
        ]) {|r|
          ppid = r.readline.strip
          mpid = r.readline.strip
          r.close
          return [ppid,mpid]
      } 
    end

    # Fetch myproxy cert using OIDC token saved in file. Derive the destination from globals.
    # @param user [User] A user object
    # @param mount_pid [Integer] The PID of the mount (not jail) namespace.
    # @param token_file_name [String] The file containing the OIDC token.
    # @return [void]
    def fetch_myproxy_cert(user, mount_pid, token_file_name)
      this_dir = File.dirname(__FILE__)
      custom_setup_dir = File.expand_path("#{this_dir}/../../../custom_scripts/setup_user/")
      IO.popen(
        [
        "#{custom_setup_dir}/setup_user.sh",
        "#{user.name}",
        "#{user.uid}",
        "#{token_file_name}",
        "#{NginxStage.pun_jail_dir}",
        "#{mount_pid}",
        ]) {|r|
          r.close
          return nil
      } 
    end

    # Recursively assign (change ownership) of directory so it can be
    # owned by a namespace
    # @param ppid [Integer] PID of the process leader in the namespace
    # @param target [String] Directory or file to assign ownership to
    def assign_to_namespace(ppid, target)
      this_dir = File.dirname(__FILE__)
      custom_ns_dir = File.expand_path("#{this_dir}/../../../custom_scripts/ns")
      IO.popen([
        "#{custom_ns_dir}/assign_to_ns.sh",
        ppid,
        target]) {|r|
          outstr = r.read
          r.close
          abort(outstr) if $?.to_i != 0
      }
      return nil
    end

    # Bind-mount an assigned file/directory into a namespace
    # @param mpid [Integer] PID of the unshare process for the namespace (before chroot)
    # @param origin [String] Directory or file outside the namespace
    # @param target [String] Directory or file inside the namespace (with pun_jail_dir as root)
    def bind_to_namespace(mpid, origin, target)
      this_dir = File.dirname(__FILE__)
      custom_ns_dir = File.expand_path("#{this_dir}/../../../custom_scripts/ns")
      IO.popen([
        "#{custom_ns_dir}/bind_mount_ns.sh",
        mpid,
        origin,
        NginxStage.pun_jail_dir + "/" + target]) {|r|
          outstr = r.read
          r.close
          abort(outstr) if $?.to_i != 0
      }
      return nil
    end

    # Execute a command in a namespace, don't wait for it to return.
    # @param ppid [Integer] PID of the process leader in the namespace
    # @param cmd [String] Command to run
    # @param args [String array] args to cmd
    def enter_namespace(ppid, cmd, args)
      this_dir = File.dirname(__FILE__)
      custom_ns_dir = File.expand_path("#{this_dir}/../../../custom_scripts/ns")
      IO.popen([
        "#{custom_ns_dir}/enter_ns.sh",
        ppid,
        cmd,
        args].flatten) {|r|
          outstr = r.read
          r.close
          abort(outstr) if $?.to_i != 0
          return outstr
      }
      return nil
    end


    private
      # Retrieves a value from superclass. If it reaches the baseclass,
      # returns default
      def self.from_superclass(method, default = nil)
        if self == NginxStage::Generator || !superclass.respond_to?(method, true)
          default
        else
          superclass.send(method).dup
        end
      end

      # Use ERB to render templates
      def render(data)
        ERB.new(data, nil, '-').result(binding)
      end
  end
end
