require 'forwardable'

module NginxStage
  # A String-like Class that includes helper methods to better describe the
  # user on the local system.
  class User
    extend Forwardable

    # @!method name
    #   The user name
    #   @return [String] the user name
    # @!method uid
    #   The user's id
    #   @return [Integer] the user id
    # @!method gid
    #   The user's group id
    #   @return [Integer] the group id
    # @!method gecos
    #   The user's real name
    #   @return [String] the real name
    # @!method dir
    #   The user's home directory
    #   @return [String] the home path
    # @!method shell
    #   The user's shell
    #   @return [String] the shell
    delegate [:name, :uid, :gid, :gecos, :dir, :shell] => :@passwd

    # List of all groups that user belongs to
    # @return [Array<String>] list of groups user is in
    attr_reader :groups

    # @param user [String] the user name defining this object
    # @raise [InvalidUser] if user doesn't exist on local system
    def initialize(user)
      if !NginxStage.pun_jail_dir.nil?
        # user does not need to exist if we're jailing. choose a random uid
        @passwd = Etc.getpwnam "nobody"
        @group = Etc.getgrgid gid
        @groups = get_groups
        @passwd.uid = 9999
        @passwd.gid = 9999
        @passwd.name = user
      else 
        @passwd = Etc.getpwnam user.to_s
        @group = Etc.getgrgid gid
        @groups = get_groups
      end
    rescue ArgumentError
      raise InvalidUser, "user doesn't exist: #{user}"
    end

    # User's primary group name
    # @return [String] the primary group name
    def group
      @group.name
    end

    # Members of user's primary group
    # @return [Array<String>] list of users in primary group
    def group_mem
      @group.mem
    end

    # Convert object to string using user name as string value
    # @return [String] the user name
    def to_s
      @passwd.name
    end

    # This object is string-like and returns the user name when treated as a
    # string
    # @return [String] the user name
    def to_str
      @passwd.name
    end

    private
      # Use `id` to get list of groups as the /etc/group file can give
      # erroneous results
      def get_groups
        `id -nG #{name}`.split(' ')
      end
  end
end
