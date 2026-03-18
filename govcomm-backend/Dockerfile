FROM node:20-bookworm-slim

WORKDIR /app

COPY --chown=node:node package*.json ./
RUN npm install --only=production

COPY --chown=node:node . .

RUN mkdir -p /app/uploads && chown -R node:node /app/uploads

USER node

EXPOSE 8080

CMD ["node", "server.js"]