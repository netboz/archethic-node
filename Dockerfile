FROM elixir:alpine AS uniris-ci

# CI
#  - compile
#  - release
#  - gen PLT

# running CI with proposal should generate release upgrade
#  - commit proposal
#  - compile
#  - run ci
#  - generate release upgrade

######### TODO
# TESTNET
#  - code
#  - release

# running TESTNET with release upgrade should ???

RUN apk add --no-cache --update \
  build-base bash gcc git npm python3 wget openssl libsodium-dev gmp-dev

# Install hex and rebar
RUN mix local.rebar --force \
 && mix local.hex --if-missing --force

WORKDIR /opt/code

COPY . .

RUN git config user.name uniris \
 && git config user.email uniris@uniris.io \
 && git remote add origin https://github.com/UNIRIS/uniris-node

# Compile
RUN mix deps.get \
 && cd assets \
 && npm ci \
 && npm run deploy

# Release
RUN mix phx.digest \
 && mix distillery.release

# gen PLT
RUN mix git_hooks.run pre_push

# Install
RUN mkdir /opt/app \
 && cd /opt/app \
 && tar zxf /opt/code/_build/dev/rel/uniris_node/releases/*/uniris_node.tar.gz
CMD /opt/app/bin/uniris_node foreground

################################################################################

FROM uniris-ci as build

FROM alpine

RUN apk add --no-cache --update bash git openssl libsodium

COPY --from=build /opt/app /opt/app
COPY --from=build /opt/code/.git /opt/code/.git

WORKDIR /opt/code
RUN git reset --hard

WORKDIR /opt/app
CMD /opt/app/bin/uniris_node foreground
