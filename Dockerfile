FROM node:5
MAINTAINER Octoblu <docker@octoblu.com>

EXPOSE 80

ENV NPM_CONFIG_LOGLEVEL error

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY . /usr/src/app
RUN npm -s install --production

CMD [ "node", "command.js" ]
