FROM node:22-alpine
WORKDIR /srv/oagent
COPY package.json ./
COPY apps ./apps
COPY packages ./packages
RUN mkdir -p /data && chown -R node:node /data /srv/oagent
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 OAGENT_DATA_FILE=/data/oagent-data.json
USER node
EXPOSE 8787
CMD ["node", "apps/control-plane/src/server.mjs"]
