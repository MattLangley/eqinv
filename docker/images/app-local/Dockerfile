FROM elixir:1.9

WORKDIR /app
RUN apt update && apt install -y inotify-tools
RUN mix local.hex --force && mix local.rebar --force