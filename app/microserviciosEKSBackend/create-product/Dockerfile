FROM node:22-alpine
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev && npm cache clean --force
COPY index.js .
USER node
EXPOSE 3002
CMD ["node", "index.js"]
