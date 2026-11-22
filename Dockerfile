# Minimal, production-mode Rails testbed for the /proc/self/fd/N + sqlite3
# extension research note. Adapted from a base image published by Luke Jahnke.
# This mirrors the post's testbed but COPYs the complete versions of the two
# files kept in this repo (the post shows them with "..." elisions).
FROM ruby:3.4

RUN gem install rails:8.0.1

RUN rails new vuln_app --minimal --api
WORKDIR vuln_app/

# Deliberately vulnerable routes and controller — see the two .rb files in
# the repository root. Do not reuse outside this disposable container.
COPY routes.rb ./config/routes.rb
COPY vuln_controller.rb ./app/controllers/vuln_controller.rb

ENV RAILS_ENV="production"
EXPOSE 3000
ENTRYPOINT ["./bin/rails", "server", "--binding=0.0.0.0"]
