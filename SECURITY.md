# Security

## Reporting a problem

Please don't report security problems in a public issue. Use GitHub's private reporting instead: go to the [Security tab](https://github.com/azagsam/musiccast-remote/security) and click **Report a vulnerability**.

You'll get a reply within a week. Fixes go into the next release, and the report is credited unless you'd rather stay anonymous.

## Supported versions

Only the latest release gets fixes.

## Scope

The app talks to your receiver over plain HTTP on the local network, because that's what Yamaha Extended Control supports. Anyone on the same network can control the receiver the same way, so that isn't a problem with this app. Other things are worth reporting, such as the app being made to connect outside the local network, or saved data leaking.
