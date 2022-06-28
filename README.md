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

This setup is useful if you want to do a full end-to-end test where you enter the slash command
in Slack and the chatops bot posts a response, which is exactly how slash commands are used by end-users.

You also have the option of [executing the chatops executable from the command line](#local-testing).

## Using GitPod

1. Use this link to create a Gitpod already containing GDK (with a working docker runner) and Chatops:
<https://gitpod.io#snapshot/ea79d2bb-00ad-4728-9e09-71aa86c7359e>. The username & password for the GDK in this
snapshot is available in the engineering vault in 1password. The entry is named "GitPod Chatops GDK".

   - Community contributors can use the following snapshot instead, which has the GDK username and password set to `root`/`5iveL!fe`:
<https://gitpod.io#snapshot/b7017335-876d-4390-b458-9e2487b876ad>.

2. Once GDK (in the GitPod) is up and running, you need to click on "ports" on the bottom right and set port 3000 to public. This is so
that Slack is able to connect to GDK. The GitPod sleeps after some period of
inactivity. You'll need to make the port public whenever you start the pod up again.

3. Login to GDK using the username and password that is available in the engineering vault in 1password. It is named "GitPod Chatops GDK".

4. Follow https://slack.com/intl/en-in/help/articles/206845317-Create-a-Slack-workspace to create your own Slack workspace.

5. Follow https://docs.gitlab.com/ee/user/project/integrations/slack_slash_commands.html to setup the slash commands configuration.

6. Then try running a command in Slack: `/chatops run help`. It should ask you to "Connect your GitLab account". After you do
that, you can run the chatops command again, and it should create a CI job under the chatops project in the GDK.

7. You can pull the latest Chatops code from https://gitlab.com/gitlab-com/chatops into the local Chatops repository by
running the following in a GitPod terminal:

   1. `cd /workspace/chatops`
   2. `git fetch origin master`
   3. `git rebase origin/master`
   4. `git push local master`  
      This will push the changes to the Chatops project in GDK. It will ask for username and password. You can use
      the username and password you used to login to GDK.

8. After making changes to the Chatops project under `/workspace/chatops` (on the GitPod disk, not in GDK), or pulling
the latest code from gitlab.com, you need to upload a new chatops image to the Container Registry of the chatops project in
GDK. Execute the following commands on the GitPod terminal:

   1. `docker build -t localhost:5000/root/chatops:latest -f docker/chatops.Dockerfile .`
   2. `docker push localhost:5000/root/chatops:latest`

Notes:
1. Chatops is already imported into the GDK, and it is also cloned onto the GitPod disk under `/workspace/chatops`.
2. Whenever you start the GitPod, make sure to set port 3000 to public.
3. The GDK password has been changed from the default because using Chatops often requires the use of tokens as CI/CD environment
variables. Since GitPod is publicly accessible, it could result in token leakage if anyone can login to the GDK.

## Using GDK/GCK

1. To use this repository with GitLab Chatops you need to have a GitLab EE Ultimate
instance (like [GDK](https://gitlab.com/gitlab-org/gitlab-development-kit) or [GCK](https://gitlab.com/gitlab-org/gitlab-compose-kit))
that is somehow publicly reachable. If you're using a development
environment you can use [localtunnel](https://localtunnel.github.io/www/) to
expose your development environment.

1. Once your environment is reachable you'll need to import this repository into
your environment so you can easily test your changes. Once done you need to set
up slash Commands integration following the guide at [Slack slash
commands](https://docs.gitlab.com/ee/user/project/integrations/slack_slash_commands.html).
You can [create your own workspace](https://slack.com/intl/en-in/help/articles/206845317-Create-a-Slack-workspace)
(unrelated to the GitLab workspace) in Slack, for testing purposes.

1. When Slash commands are set up you need to set up the CI runner in your local
environment. The easiest way of setting this up is by using the shell executor
as this removes the need for also setting up Docker.

1. You also need to build and push a chatops container image into the Container Registry
of your local chatops project.

   This can be done with the following commands:

   These commands assume that the Container Registry for your GDK instance is accessible at `gdk.test:5000`,
   and your chatops project is at `root/chatops`. You should be in your local
   chatops project folder when running these commands:

   1. `docker build -t gdk.test:5000/root/chatops:latest -f docker/chatops.Dockerfile .`
   1. `docker push gdk.test:5000/root/chatops:latest`

      If asked for username and password, you can enter your GDK username and password.

## After setup

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

## Logging

This project uses the [SemanticLogger](https://logger.rocketjob.io/) library.

All requests to the GitLab API will have the request URL, request method
and response status logged automatically.

Developers can choose to log any other information as well. To use the logger
in a class, include `::SemanticLogger::Loggable`, and then use the `logger` variable
that is made available.

```ruby
class Deploy
   include ::SemanticLogger::Loggable

   logger.info("About to perform edit action", relevant_data: data)
end
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
unless stated otherwise. A copy of this license can be found in the file "LICENSE".
