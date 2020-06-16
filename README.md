# Chatops for GitLab.com

This repository contains various scripts used to automate various tasks for
GitLab.com such as getting the `EXPLAIN ANALYZE` output of a database query.

# Requirements

* Ruby 2.6
* Bundler
* GitLab EE Ultimate for chatops support
* A Slack API token for a bot integration
* A Grafana API token

# Setting Up

To use this repository with GitLab Chatops you need to have a GitLab EE Ultimate
instance that is somehow publicly reachable. If you're using a development
environment you can use [localtunnel](https://localtunnel.github.io/www/) to
expose your development environment.

Once your environment is reachable you'll need to import this repository into
your environment so you can easily test your changes. Once done you need to set
up slash Commands integration following the guide at [Slack slash
commands](https://docs.gitlab.com/ee/user/project/integrations/slack_slash_commands.html).

When Slash commands are set up you need to set up the CI runner in your local
environment. The easiest way of setting this up is by using the shell executor
as this removes the need for also setting up Docker.

With everything set up (and running) you can then run chatops commands by typing
the following into a Slack channel:

    /slash-prefix run COMMAND OPTIONS

Here `/slash-prefix` is the slash command prefix configured earlier on. `run` is
the GitLab slash command used for executing chatops jobs. Here `COMMAND` defines
the chatops command to run. Any additional values are treated as the arguments
to pass to this command. For example, to run the `explain` command you would run
the following slash command:

    /slash-prefix run explain SELECT COUNT(*) FROM users

Certain commands manually produce their output. For example, the `graph` command
uploads a file to Slack. For this to work you also need to:

1. Use an existing or add a new configuration in the
   [Slack Bots App](https://gitlab.slack.com/apps/A0F7YS25R-bots).
1. Make sure the bot is present in the channel.
1. Expose the API token via the `SLACK_TOKEN` environment variable.

Tip: To find the `CHAT_CHANNEL` ID, look at the link to a Slack message from
the channel. The ID is the first set of random looking characters.

Other commands may require additional tokens such as a GitLab or Twitter API
token. All of these are best set using CI/CD secret variables, which can be
configured per project under "Settings" > "CI / CD Settings".

# Adding Commands

While GitLab Chatops supports arbitrary commands (really anything that you can
run in CI) we _highly_ recommend writing your commands in Ruby. Using Ruby
brings several benefits such as:

1. Contributing to the project is easier because most GitLab developers will
   know Ruby, but not all of them will know Go/Bash/Cobol/Pascal/etc.
1. By writing the commands in Ruby you can reuse the existing facilities for
   downloading Grafana graphs, uploading data to Slack, generating Markdown,
   etc.
1. Writing the commands in Ruby means we can easily test them using RSpec,
   including the ability to easily stub out network operations.
1. When using Ruby we can use existing libraries for connecting to databases or
   external services, instead of having to rely on shell commands. This makes it
   much harder to perform shell injections and other similar attacks. For cases
   where you do need to shell out you can use Ruby's Shellwords module to escape
   user input.

The easiest way to add a new command is by running `rake generate[NAME]` where
`NAME` is the name of your command. For example, to generate the code for a
`restart` command you'd run the following:

    rake generate[restart]

This command will then do the following:

1. Create the file `lib/chatops/commands/restart.rb` containing some basic
   boilerplate to get you started.
1. `require` this file in `lib/chatops.rb`.
1. Add some RSpec boilerplate for this command in
   `spec/chatops/commands/restart_spec.rb`.
1. Add the command to `.gitlab-ci.yml`.

## Description

Each command can define a short description that is displayed when running the
`help` command or when passing `--help` to a command. Said description can be
added using the `description` class method available to every command. For
example:

```ruby
class MyCommand
  include Command

  description 'This is the description of my command'
end
```

All commands should provide a short description as otherwise it can be hard for
a user to figure out what they do.

## Options

Commands can also define options (e.g. `--version`) that a user can pass, just
like any other CLI application. These options are defined using
[Slop](https://github.com/leejarvis/slop/), which is less painful to work with
compared to Ruby's own OptionParser class.

## Local Testing
You can run the chatops command locally if you specify the proper environment variables. For example, the following will run a user find command on a user name. You may need other environment variables depending on the command.

``` bash
env SLACK_TOKEN='SLACK_XXX' GITLAB_TOKEN='GITLAB_XXX' CHAT_INPUT='find cmcfarland' CHAT_CHANNEL='SLACK_CHANNEL_ID' bundle exec ./bin/chatops user
```

## Examples

You can use the following existing commands as examples/reference material when
adding new commands:

* [broadcast](/lib/chatops/commands/broadcast.rb)
* [explain](/lib/chatops/commands/explain.rb)
* [feature](/lib/chatops/commands/feature.rb)
* [user](/lib/chatops/commands/user.rb)

# License

All source code in this repository is subject to the terms of the MIT license,
unless stated otherwise. A copy of this license can be found the file "LICENSE".
