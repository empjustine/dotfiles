#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

DIRECTORY_SEPARATOR= '/'
USER_HOME = ENV['HOME']
ATOM_START = '(^|/)'

def dirjoin(*atoms)

  return atoms.join(DIRECTORY_SEPARATOR)
end

REPOSITORIES = dirjoin(USER_HOME, 'repositories')

RELATIONS = {
# {:source_root => :source_glob} => :target_root,
  {dirjoin(REPOSITORIES, 'self', 'dotfiles', 'tilde') => '/**/*'} => USER_HOME,
  {dirjoin(REPOSITORIES, 'vim') => '/*'} => dirjoin(USER_HOME, '.vim', 'bundle'),
}

SYMLINK_PREFIXES = {
# /#{ATOM_START}example-symlink-decorator-/ => 'replacement',
  /#{ATOM_START}dot-/ => '.',
  /#{ATOM_START}vim-/ => 'vim-',
  /#{ATOM_START}symlink-/ => '',
}

NOT_SYMLINK_PREFIXES = {
  /#{ATOM_START}notsymlink-dot-/ => '.',
}

FUNCTORS = {
  lambda { |d| # ---------- ----------

    d[:pipeline] << 'source_populate'
  } =>
    lambda { |d| # ---------- ----------

      source = d[:source]

      source[:absolute].index(source[:root]) == 0 && \
      source[:relative] = source[:absolute][source[:root].size + 1..-1]

      d[:opts] = { :symlink => not(File.directory?(source[:absolute])), }

      d
    },
  lambda { |d| # ---------- ----------

    d[:pipeline] << 'target_populate'
  } =>
    lambda { |d| # ---------- ----------

      source = d[:source]
      target = d[:target]

      target[:dirname], _, target[:basename] = source[:relative].rpartition(
        DIRECTORY_SEPARATOR
      )

      d
    },
  lambda { |d| # ---------- ----------

    d[:pipeline] << 'decorator_filter'
  } =>
    lambda { |d| # ---------- ----------

      target = d[:target]

      [:dirname, :basename].each { |name_part|

        SYMLINK_PREFIXES.each { |regexp, substring|

          d[:opts][:symlink] = true if target[name_part][regexp]
          target[name_part].gsub!(regexp, substring)
        }

        NOT_SYMLINK_PREFIXES.each { |regexp, substring|

          d[:opts][:symlink] = false if target[name_part][regexp]
          target[name_part].gsub!(regexp, substring)
        }
      }

      d
    },
  lambda { |d| # ---------- ----------

    d[:pipeline] << 'folder_generator'
  } =>
    lambda { |d| # ---------- ----------

      target = d[:target]

      target[:mkdir] = {
        :target => dirjoin(d[:target][:root], d[:target][:dirname]),
      }

      d
    },
  lambda { |d| # ---------- ----------

    d[:opts][:symlink] && \
    d[:pipeline] << 'link_generator'
  } =>
    lambda { |d| # ---------- ----------

      source = d[:source]
      target = d[:target]

      target[:ln] = {
        :source => source[:absolute],
        :target => dirjoin([
          target[:root]     .empty? ? nil : target[:root],
          target[:dirname]  .empty? ? nil : target[:dirname],
          target[:basename]
        ].compact),
      }

      d
    },
  lambda { |d| # ---------- ----------

    d[:opts][:symlink] && \
    d[:pipeline] << 'link_output'
  } =>
    lambda { |d| # ---------- ----------

      target = d[:target]

      "ln -s \"#{target[:ln][:source]}\" \"#{target[:ln][:target]}\""
      #d
    },
}

puts RELATIONS.map { |source, target_root|
  source.map { |source_root, source_glob|
    Dir[source_root + source_glob].map { |source_absolute|

      d = {
        :source => {
          :root => source_root,
          :absolute => source_absolute,
        },
        :target => {
          :root => target_root,
        },
        :pipeline => [],
      }

      FUNCTORS.each { |guard, action|
        guard.call(d) && d = action.call(d)
      }

      d
    }.flatten
  }.flatten
}.flatten
