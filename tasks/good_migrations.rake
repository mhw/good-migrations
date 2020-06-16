require "active_support/dependencies"
require "good_migrations"

def __good_migrations_zeitwerk_enabled?
  Rails.singleton_class.method_defined?(:autoloaders) &&
    Rails.autoloaders.zeitwerk_enabled?
end

def __good_migrations_raise(path_or_constant)
  raise GoodMigrations::LoadError, <<~ERROR
    Rails attempted to auto-load:

    #{path_or_constant}

    Which is in your project's `app/` directory. The good_migrations
    gem was designed to prevent this, because migrations are intended
    to be immutable and safe-to-run for the life of your project, but
    code in `app/` is liable to change at any time.

    The most common reason for this error is that you may be referencing an
    ActiveRecord model inside the migration in order to use the ActiveRecord API
    to implement a data migration by querying and updating objects.

    For instance, if you want to access a model "User" in your migration, it's safer
    to redefine the class inside the migration instead, like this:

    class MakeUsersOlder < ActiveRecord::Migration
      class User < ActiveRecord::Base
        # Define whatever you need on the User beyond what AR adds automatically
      end

      def up
        User.find_each do |user|
          user.update!(:age => user.age + 1)
        end
      end

      def down
        #...
      end
    end

    For more information, visit:

    https://github.com/testdouble/good-migrations

  ERROR
end

namespace :good_migrations do
  task :disable_autoload do
    next if ENV["GOOD_MIGRATIONS"] == "skip"
    if __good_migrations_zeitwerk_enabled?
      ::GOOD_MIGRATIONS_AUTOLOADED_CONSTANTS_AT_START =
        ActiveSupport::Dependencies.autoloaded_constants
    else
      ActiveSupport::Dependencies.class_eval do
        extend Module.new {
          def load_file(path, const_paths = loadable_constants_for_path(path))
            if path.starts_with? File.join(Rails.application.root, "app")
              __good_migrations_raise(path)
            else
              super
            end
          end
        }
      end
    end
  end

  task :after_migrations do
    next if ENV["GOOD_MIGRATIONS"] == "skip"
    if ::GOOD_MIGRATIONS_AUTOLOADED_CONSTANTS_AT_START !=
        ActiveSupport::Dependencies.autoloaded_constants
      __good_migrations_raise(
        (ActiveSupport::Dependencies.autoloaded_constants -
          ::GOOD_MIGRATIONS_AUTOLOADED_CONSTANTS_AT_START).first
      )
    end
  end
end

Rake.application.in_namespace("db:migrate") do |namespace|
  ([Rake::Task["db:migrate"]] + namespace.tasks).each do |task|
    task.prerequisites << "good_migrations:disable_autoload"
    if __good_migrations_zeitwerk_enabled?
      task.enhance do
        Rake::Task["good_migrations:after_migrations"].invoke
      end
    end
  end
end
