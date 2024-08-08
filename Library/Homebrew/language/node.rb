# typed: strict
# frozen_string_literal: true

module Language
  # Helper functions for Node formulae.
  #
  # @api public
  module Node
    sig { returns(String) }
    def self.npm_cache_config
      odeprecated "Language::Node.npm_cache_config"
      "cache=#{HOMEBREW_CACHE}/npm_cache"
    end

    sig { returns(String) }
    def self.pack_for_installation
      # Homebrew assumes the buildpath/testpath will always be disposable
      # and from npm 5.0.0 the logic changed so that when a directory is
      # fed to `npm install` only symlinks are created linking back to that
      # directory, consequently breaking that assumption. We require a tarball
      # because npm install creates a "real" installation when fed a tarball.
      package = Pathname("package.json")
      return unless package.exist?

      # Due to a bug in npm not respecting `--ignore-scripts`, we must remove
      # pack's lifecyle scripts ourselves: https://docs.npmjs.com/cli/v10/using-npm/scripts#npm-pack
      # TODO: remove with npm v11: https://github.com/npm/cli/issues/7211
      begin
        pkg_json = JSON.parse(package.read)
      rescue JSON::ParserError
        opoo "Could not parse package.json!"
        raise
      end
      modified = pkg_json["scripts"]&.delete("prepare")
      modified ||= pkg_json["scripts"]&.delete("prepack")
      modified ||= pkg_json["scripts"]&.delete("postpack")
      package.atomic_write(JSON.pretty_generate(pkg_json)) if modified
      output = Utils.popen_read("npm", "pack", "--ignore-scripts")
      raise "npm failed to pack #{Dir.pwd}" if !$CHILD_STATUS.exitstatus.zero? || output.lines.empty?

      output.lines.last.chomp
    end

    sig { void }
    def self.setup_npm_environment
      # guard that this is only run once
      return if @env_set

      @env_set = T.let(true, T.nilable(T::Boolean))
      # explicitly use our npm and node-gyp executables instead of the user
      # managed ones in HOMEBREW_PREFIX/lib/node_modules which might be broken
      begin
        ENV.prepend_path "PATH", Formula["node"].opt_libexec/"bin"
      rescue FormulaUnavailableError
        nil
      end
    end

    sig { params(libexec: Pathname).returns(T::Array[String]) }
    def self.std_npm_install_args(libexec)
      odeprecated "Language::Node.std_npm_install_args", "`std_npm_args`"
      setup_npm_environment

      pack = pack_for_installation

      # npm 7 requires that these dirs exist before install
      # https://github.com/npm/cli/pull/2497
      (libexec/"lib").mkpath

      # npm install args for global style module format installed into libexec
      args = %W[
        -ddd
        --global
        --build-from-source
        --prefix=#{libexec}
        #{Dir.pwd}/#{pack}
      ]

      args << "--unsafe-perm" if Process.uid.zero?

      args
    end

    sig { returns(T::Array[String]) }
    def self.local_npm_install_args
      odeprecated "Language::Node.local_npm_install_args", "`std_npm_args(prefix: false)`"
      setup_npm_environment
      # npm install args for local style module format
      %w[
        -ddd
        --build-from-source
      ]
    end

    # Mixin module for {Formula} adding shebang rewrite features.
    module Shebang
      module_function

      # A regex to match potential shebang permutations.
      NODE_SHEBANG_REGEX = %r{^#! ?/usr/bin/(?:env )?node( |$)}

      # The length of the longest shebang matching `SHEBANG_REGEX`.
      NODE_SHEBANG_MAX_LENGTH = T.let("#! /usr/bin/env node ".length, Integer)

      # @private
      sig { params(node_path: T.any(String, Pathname)).returns(Utils::Shebang::RewriteInfo) }
      def node_shebang_rewrite_info(node_path)
        Utils::Shebang::RewriteInfo.new(
          NODE_SHEBANG_REGEX,
          NODE_SHEBANG_MAX_LENGTH,
          "#{node_path}\\1",
        )
      end

      sig { params(formula: Formula).returns(Utils::Shebang::RewriteInfo) }
      def detected_node_shebang(formula = T.cast(self, Formula))
        node_deps = formula.deps.map(&:name).grep(/^node(@.+)?$/)
        raise ShebangDetectionError.new("Node", "formula does not depend on Node") if node_deps.empty?
        raise ShebangDetectionError.new("Node", "formula has multiple Node dependencies") if node_deps.length > 1

        node_shebang_rewrite_info(Formula[node_deps.first].opt_bin/"node")
      end
    end
  end
end
